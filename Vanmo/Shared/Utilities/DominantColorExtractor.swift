import SwiftUI
import Kingfisher

enum DominantColorExtractor {
    private static let cache = NSCache<NSString, UIColor>()

    private static let sampleWidth = 48
    private static let hueBinCount = 16

    // MARK: - Public API

    static func cachedColor(for url: URL?) async -> Color {
        guard let url else { return .black.opacity(0.9) }
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return Color(cached)
        }
        guard let image = await retrieveImage(for: url),
              let color = extractDominantColor(from: image) else {
            return .black.opacity(0.9)
        }
        cache.setObject(UIColor(color), forKey: key)
        return color
    }

    static func extractDominantColor(from image: UIImage) -> Color? {
        let allPixels = extractPixelHSB(from: image)
        guard !allPixels.isEmpty else { return nil }

        let chromatic = allPixels.filter {
            $0.saturation > 0.08 && $0.brightness > 0.06 && $0.brightness < 0.94
        }

        if chromatic.count >= 8, let best = selectBestHue(from: chromatic) {
            return refineForBackground(best)
        }

        return averageFallback(from: allPixels)
    }

    // MARK: - Image Retrieval (Kingfisher cache → network)

    private static func retrieveImage(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Pixel Extraction

    private struct HSBPixel {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    private static func extractPixelHSB(from image: UIImage) -> [HSBPixel] {
        guard let cgImage = image.cgImage else { return [] }
        let aspect = Double(cgImage.height) / max(Double(cgImage.width), 1)
        let w = sampleWidth
        let h = max(Int(Double(w) * aspect), 1)
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: h * bytesPerRow)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &buffer, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return [] }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var pixels: [HSBPixel] = []
        pixels.reserveCapacity(w * h)

        for i in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Double(buffer[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(Double(buffer[i]) / (255 * alpha), 1)
            let g = min(Double(buffer[i + 1]) / (255 * alpha), 1)
            let b = min(Double(buffer[i + 2]) / (255 * alpha), 1)
            pixels.append(rgbToHSB(r: r, g: g, b: b))
        }
        return pixels
    }

    // MARK: - Palette Scoring

    private static func selectBestHue(from pixels: [HSBPixel]) -> HSBPixel? {
        var binWeight = [Double](repeating: 0, count: hueBinCount)
        var binHueX   = [Double](repeating: 0, count: hueBinCount)
        var binHueY   = [Double](repeating: 0, count: hueBinCount)
        var binSatSum = [Double](repeating: 0, count: hueBinCount)
        var binBriSum = [Double](repeating: 0, count: hueBinCount)

        for p in pixels {
            let bin = min(Int(p.hue * Double(hueBinCount)), hueBinCount - 1)
            let w = p.saturation
            binWeight[bin] += w
            binHueX[bin]   += cos(p.hue * 2 * .pi) * w
            binHueY[bin]   += sin(p.hue * 2 * .pi) * w
            binSatSum[bin] += p.saturation * w
            binBriSum[bin] += p.brightness * w
        }

        let totalWeight = binWeight.reduce(0, +)
        guard totalWeight > 0 else { return nil }

        var bestScore = -1.0
        var bestPixel: HSBPixel?

        for i in 0..<hueBinCount {
            let w = binWeight[i]
            guard w > totalWeight * 0.02 else { continue }

            var avgHue = atan2(binHueY[i] / w, binHueX[i] / w) / (2 * .pi)
            if avgHue < 0 { avgHue += 1 }
            let avgSat = binSatSum[i] / w
            let avgBri = binBriSum[i] / w
            let population = w / totalWeight

            let satRaw = 1 - pow(abs(avgSat - 0.55) * 1.3, 2)
            let satQ = avgSat * clamp(satRaw, low: 0, high: 1)

            let briQ: Double
            if avgBri < 0.15 {
                briQ = avgBri * 3
            } else if avgBri > 0.85 {
                briQ = (1 - avgBri) * 3
            } else {
                briQ = 0.5 + 0.5 * max(0, 1 - abs(avgBri - 0.45) * 1.5)
            }

            let score = pow(population, 0.45) * 0.35 + satQ * 0.40 + briQ * 0.25

            if score > bestScore {
                bestScore = score
                bestPixel = HSBPixel(hue: avgHue, saturation: avgSat, brightness: avgBri)
            }
        }

        return bestPixel
    }

    // MARK: - Background Refinement

    private static func refineForBackground(_ pixel: HSBPixel) -> Color {
        let sat = min(pixel.saturation * 1.2, 0.78)
        let bri = clamp(pixel.brightness * 0.55, low: 0.13, high: 0.35)
        return Color(hue: pixel.hue, saturation: sat, brightness: bri)
    }

    // MARK: - Fallback

    private static func averageFallback(from pixels: [HSBPixel]) -> Color? {
        guard !pixels.isEmpty else { return nil }
        var hueX = 0.0, hueY = 0.0, satSum = 0.0, briSum = 0.0
        for p in pixels {
            hueX += cos(p.hue * 2 * .pi)
            hueY += sin(p.hue * 2 * .pi)
            satSum += p.saturation
            briSum += p.brightness
        }
        let n = Double(pixels.count)
        var avgHue = atan2(hueY / n, hueX / n) / (2 * .pi)
        if avgHue < 0 { avgHue += 1 }
        return Color(
            hue: avgHue,
            saturation: min(satSum / n * 1.1, 0.65),
            brightness: clamp(briSum / n * 0.5, low: 0.10, high: 0.30)
        )
    }

    // MARK: - Helpers

    private static func rgbToHSB(r: Double, g: Double, b: Double) -> HSBPixel {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        let brightness = maxC
        let saturation = maxC > 0 ? delta / maxC : 0

        var hue = 0.0
        if delta > 0 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return HSBPixel(hue: hue, saturation: saturation, brightness: brightness)
    }

    private static func clamp(_ v: Double, low: Double, high: Double) -> Double {
        Swift.max(low, Swift.min(high, v))
    }
}
