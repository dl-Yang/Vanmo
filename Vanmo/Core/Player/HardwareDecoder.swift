import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

enum DecoderError: LocalizedError {
    case unsupportedCodec(String)
    case sessionCreationFailed
    case decompressionFailed(OSStatus)
    case formatDescriptionFailed
    case pixelBufferUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedCodec(let codec):
            return "不支持的编码格式: \(codec)"
        case .sessionCreationFailed:
            return "硬件解码器创建失败"
        case .decompressionFailed(let status):
            return "硬件解码失败: \(status)"
        case .formatDescriptionFailed:
            return "格式描述创建失败"
        case .pixelBufferUnavailable:
            return "像素缓冲区不可用"
        }
    }
}

struct DecodedVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let pts: CMTime
    let duration: CMTime
    let width: Int
    let height: Int
}

final class HardwareDecoder {

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    private let outputQueue = DispatchQueue(label: "com.vanmo.decoder.output")
    private var pendingFrames: [DecodedVideoFrame] = []
    private let frameLock = NSLock()

    private(set) var isHardwareAccelerated = false
    private(set) var codecFourCC: FourCharCode = 0

    var onFrameDecoded: ((DecodedVideoFrame) -> Void)?

    deinit {
        invalidate()
    }

    // MARK: - Public Methods

    /// Configure the hardware decoder for H.264 or H.265 video.
    /// - Parameters:
    ///   - codec: Codec type (kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, etc.)
    ///   - width: Video width in pixels
    ///   - height: Video height in pixels
    ///   - extradata: Codec extradata (SPS/PPS for H.264, VPS/SPS/PPS for H.265)
    func configure(
        codec: CMVideoCodecType,
        width: Int32,
        height: Int32,
        extradata: Data?
    ) throws {
        invalidate()
        codecFourCC = codec

        let formatDesc = try createFormatDescription(
            codec: codec,
            width: width,
            height: height,
            extradata: extradata
        )
        self.formatDescription = formatDesc

        let outputAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(width),
            kCVPixelBufferHeightKey as String: Int(height),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: outputAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )

        guard status == noErr, session != nil else {
            VanmoLogger.player.error("[HWDecoder] VTDecompressionSessionCreate failed: status=\(status), codec=\(codec), \(width)x\(height)")
            throw DecoderError.sessionCreationFailed
        }

        isHardwareAccelerated = true
        VanmoLogger.player.info("HardwareDecoder configured: \(width)x\(height), codec=\(codec)")
    }

    /// Decode a compressed video sample.
    /// - Parameters:
    ///   - data: Compressed frame data (NAL units)
    ///   - pts: Presentation timestamp
    ///   - dts: Decode timestamp
    ///   - duration: Frame duration
    ///   - isKeyframe: Whether this is an IDR/keyframe
    private var totalDecodeAttempts = 0
    private var blockBufferErrors = 0
    private var sampleBufferErrors = 0
    private var vtDecodeErrors = 0

    func decode(
        data: UnsafePointer<UInt8>,
        size: Int,
        pts: CMTime,
        dts: CMTime,
        duration: CMTime,
        isKeyframe: Bool
    ) throws {
        guard let session, let formatDescription else {
            VanmoLogger.player.error("[HWDecoder] session or formatDescription is nil")
            throw DecoderError.sessionCreationFailed
        }

        totalDecodeAttempts += 1

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: UnsafeMutableRawPointer(mutating: data),
            blockLength: size,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: size,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            blockBufferErrors += 1
            if blockBufferErrors <= 3 {
                VanmoLogger.player.error("[HWDecoder] CMBlockBuffer creation failed: \(status), size=\(size)")
            }
            throw DecoderError.decompressionFailed(status)
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = size
        var timingInfo = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )
        status = CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer else {
            sampleBufferErrors += 1
            if sampleBufferErrors <= 3 {
                VanmoLogger.player.error("[HWDecoder] CMSampleBuffer creation failed: \(status), size=\(size)")
            }
            throw DecoderError.decompressionFailed(status)
        }

        let decodeFlags: VTDecodeFrameFlags = isKeyframe ? [] : [._EnableAsynchronousDecompression]

        status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            infoFlagsOut: nil
        ) { [weak self] decodeStatus, _, imageBuffer, presentationTS, presentationDur in
            self?.handleDecodedFrame(
                pixelBuffer: imageBuffer,
                pts: presentationTS,
                duration: presentationDur,
                status: decodeStatus
            )
        }

        if status != noErr {
            vtDecodeErrors += 1
            if vtDecodeErrors <= 5 {
                VanmoLogger.player.error("[HWDecoder] VTDecompressionSessionDecodeFrame failed: \(status), keyframe=\(isKeyframe), size=\(size), pts=\(pts.seconds)s, attempt #\(self.totalDecodeAttempts)")
            }
            throw DecoderError.decompressionFailed(status)
        }
    }

    func flush() {
        guard let session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        isHardwareAccelerated = false

        frameLock.lock()
        pendingFrames.removeAll()
        frameLock.unlock()
    }

    // MARK: - Supported Codec Check

    static func isCodecSupported(_ codec: CMVideoCodecType) -> Bool {
        VTIsHardwareDecodeSupported(codec)
    }

    // MARK: - Private

    private func createFormatDescription(
        codec: CMVideoCodecType,
        width: Int32,
        height: Int32,
        extradata: Data?
    ) throws -> CMVideoFormatDescription {
        var formatDesc: CMVideoFormatDescription?
        let status: OSStatus

        if let extradata, !extradata.isEmpty {
            let atomKey: String
            switch codec {
            case kCMVideoCodecType_HEVC:
                atomKey = "hvcC"
            case kCMVideoCodecType_H264:
                atomKey = "avcC"
            default:
                atomKey = "avcC"
            }

            let extensions: [String: Any] = [
                "SampleDescriptionExtensionAtoms": [atomKey: extradata]
            ]
            status = CMVideoFormatDescriptionCreate(
                allocator: nil,
                codecType: codec,
                width: width,
                height: height,
                extensions: extensions as CFDictionary,
                formatDescriptionOut: &formatDesc
            )
        } else {
            status = CMVideoFormatDescriptionCreate(
                allocator: nil,
                codecType: codec,
                width: width,
                height: height,
                extensions: nil,
                formatDescriptionOut: &formatDesc
            )
        }

        guard status == noErr, let formatDesc else {
            VanmoLogger.player.error("[HWDecoder] CMVideoFormatDescriptionCreate failed: status=\(status), codec=\(codec), \(width)x\(height)")
            throw DecoderError.formatDescriptionFailed
        }
        return formatDesc
    }

    private var outputFrameCount = 0
    private var outputErrorCount = 0

    func handleDecodedFrame(
        pixelBuffer: CVPixelBuffer?,
        pts: CMTime,
        duration: CMTime,
        status: OSStatus
    ) {
        guard status == noErr else {
            outputErrorCount += 1
            if outputErrorCount <= 5 {
                VanmoLogger.player.warning("[HWDecoder] output callback error: \(status), pixelBuffer=\(pixelBuffer != nil)")
            }
            return
        }
        guard let pixelBuffer else {
            outputErrorCount += 1
            if outputErrorCount <= 5 {
                VanmoLogger.player.warning("[HWDecoder] output callback: pixelBuffer is nil, status=\(status)")
            }
            return
        }

        outputFrameCount += 1
        if outputFrameCount == 1 {
            VanmoLogger.player.info("[HWDecoder] first output frame: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)), pts=\(pts.seconds)s")
        }

        let frame = DecodedVideoFrame(
            pixelBuffer: pixelBuffer,
            pts: pts,
            duration: duration,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        onFrameDecoded?(frame)
    }
}

