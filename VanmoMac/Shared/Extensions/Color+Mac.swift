import SwiftUI

extension Color {
    init?(rgbaHex: String) {
        var hex = rgbaHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }

        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let r, g, b, a: Double
        if hex.count == 8 {
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var rgbaHex: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return "#FFFFFFFF"
        }

        let r = Int((components[safe: 0] ?? 1) * 255)
        let g = Int((components[safe: 1] ?? 1) * 255)
        let b = Int((components[safe: 2] ?? 1) * 255)
        let a = Int((components[safe: 3] ?? 1) * 255)
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

private extension Array where Element == CGFloat {
    subscript(safe index: Int) -> CGFloat? {
        indices.contains(index) ? self[index] : nil
    }
}
