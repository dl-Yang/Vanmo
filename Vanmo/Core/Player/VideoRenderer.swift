import Foundation
import Metal
import MetalKit
import CoreVideo
import UIKit

final class VideoRenderer: NSObject {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?

    private(set) var metalView: MTKView

    private var currentPixelBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()
    private let scaleModeLock = NSLock()
    private var scaleMode: VideoScaleMode = .fit
    private var drawCallCount = 0
    private var drawFailCount = 0

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.metalView = MTKView(frame: .zero, device: device)
        VanmoLogger.player.info("[VideoRenderer] Metal device: \(device.name)")

        let library = device.makeDefaultLibrary()
            ?? Self.makeShaderLibrary(device: device)
        VanmoLogger.player.info("[VideoRenderer] shader library: \(library != nil ? "loaded" : "nil!")")
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        VanmoLogger.player.info("[VideoRenderer] vertex=\(pipelineDescriptor.vertexFunction != nil), fragment=\(pipelineDescriptor.fragmentFunction != nil)")

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }

        super.init()

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
        VanmoLogger.player.info("[VideoRenderer] textureCache: \(cache != nil ? "created" : "nil!")")

        configureMetalView()
        VanmoLogger.player.info("[VideoRenderer] initialized successfully")
    }

    // MARK: - Public Methods

    private var enqueueCount = 0

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        bufferLock.lock()
        currentPixelBuffer = pixelBuffer
        bufferLock.unlock()
        enqueueCount += 1

        if enqueueCount == 1 {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            VanmoLogger.player.info("[VideoRenderer] first frame enqueued: \(w)x\(h)")
        }

        DispatchQueue.main.async { [weak self] in
            self?.metalView.setNeedsDisplay()
        }
    }

    /// Called from main thread (CADisplayLink) to avoid async dispatch latency.
    func displayImmediately(_ pixelBuffer: CVPixelBuffer) {
        bufferLock.lock()
        currentPixelBuffer = pixelBuffer
        bufferLock.unlock()
        enqueueCount += 1

        if enqueueCount == 1 {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            VanmoLogger.player.info("[VideoRenderer] first frame enqueued: \(w)x\(h)")
        }

        metalView.setNeedsDisplay()
    }

    func clear() {
        bufferLock.lock()
        currentPixelBuffer = nil
        bufferLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.metalView.setNeedsDisplay()
        }
    }

    func setScaleMode(_ mode: VideoScaleMode) {
        scaleModeLock.lock()
        scaleMode = mode
        scaleModeLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.metalView.setNeedsDisplay()
        }
    }

    // MARK: - Private

    private func configureMetalView() {
        metalView.device = device
        metalView.delegate = self
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.backgroundColor = .black
        metalView.contentMode = .scaleAspectFit
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private static func makeShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(
            uint vertexID [[vertex_id]],
            const device float2 *positions [[buffer(0)]]
        ) {
            float2 texCoords[] = {
                float2(0, 1), float2(1, 1),
                float2(0, 0), float2(1, 0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment half4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<half> texture [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            return texture.sample(s, in.texCoord);
        }
        """

        return try? device.makeLibrary(source: shaderSource, options: nil)
    }
}

// MARK: - MTKViewDelegate

extension VideoRenderer: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        bufferLock.lock()
        let pixelBuffer = currentPixelBuffer
        bufferLock.unlock()

        guard let pixelBuffer else {
            drawFailCount += 1
            if drawFailCount == 1 {
                VanmoLogger.player.debug("[VideoRenderer] draw: no pixelBuffer")
            }
            return
        }
        guard let texture = createTexture(from: pixelBuffer) else {
            drawFailCount += 1
            if drawFailCount <= 3 {
                VanmoLogger.player.warning("[VideoRenderer] draw: createTexture failed, pbSize=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
            }
            return
        }
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            drawFailCount += 1
            if drawFailCount <= 3 {
                VanmoLogger.player.warning("[VideoRenderer] draw: Metal pipeline objects unavailable (drawable=\(view.currentDrawable != nil), viewSize=\(view.drawableSize.width)x\(view.drawableSize.height))")
            }
            return
        }

        drawCallCount += 1
        if drawCallCount == 1 {
            VanmoLogger.player.info("[VideoRenderer] first successful draw, texture \(texture.width)x\(texture.height), drawableSize=\(view.drawableSize.width)x\(view.drawableSize.height)")
        }

        let vertices = quadVertices(
            textureWidth: texture.width,
            textureHeight: texture.height,
            drawableSize: view.drawableSize
        )
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func quadVertices(textureWidth: Int, textureHeight: Int, drawableSize: CGSize) -> [Float] {
        guard textureWidth > 0, textureHeight > 0, drawableSize.width > 0, drawableSize.height > 0 else {
            return [-1, -1, 1, -1, -1, 1, 1, 1]
        }

        let videoAspect = Float(textureWidth) / Float(textureHeight)
        let viewAspect = Float(drawableSize.width) / Float(drawableSize.height)
        let mode: VideoScaleMode = {
            scaleModeLock.lock()
            defer { scaleModeLock.unlock() }
            return scaleMode
        }()

        var scaleX: Float = 1
        var scaleY: Float = 1

        switch mode {
        case .fit:
            if videoAspect > viewAspect {
                scaleY = viewAspect / videoAspect
            } else {
                scaleX = videoAspect / viewAspect
            }
        case .fill:
            if videoAspect > viewAspect {
                scaleX = videoAspect / viewAspect
            } else {
                scaleY = viewAspect / videoAspect
            }
        case .stretch:
            break
        }

        return [
            -scaleX, -scaleY,
             scaleX, -scaleY,
            -scaleX,  scaleY,
             scaleX,  scaleY
        ]
    }
}
