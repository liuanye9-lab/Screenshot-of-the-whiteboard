// LeafStyle.swift — 共享设计令牌
import AppKit

enum LeafStyle {
    static let primaryBlue = NSColor(calibratedRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
    static let systemRed = NSColor(calibratedRed: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
    static let systemGreen = NSColor(calibratedRed: 0.204, green: 0.78, blue: 0.349, alpha: 1.0)
    static let systemYellow = NSColor(calibratedRed: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
    static let systemPurple = NSColor(calibratedRed: 0.686, green: 0.322, blue: 0.871, alpha: 1.0)
    static let cornerRadius: CGFloat = 16
    static let smallRadius: CGFloat = 10
    static let toolbarHeight: CGFloat = 52
    static let toolbarPadding: CGFloat = 8
    static let strokeWidth: CGFloat = 2.5
    static let arrowSize: CGFloat = 14
    static let magnifierSize: CGFloat = 100
    static let magnifierZoom: CGFloat = 2.0

    static func makeToolbarBackground(frame: NSRect) -> NSVisualEffectView {
        let v = NSVisualEffectView(frame: frame)
        v.material = .popover
        v.state = .active
        v.blendingMode = .behindWindow
        v.wantsLayer = true
        v.layer?.cornerRadius = LeafStyle.cornerRadius
        v.layer?.masksToBounds = true
        return v
    }

    static var appAccentColor: NSColor { primaryBlue }
}

extension NSColor {
    static var leafAccent: NSColor { LeafStyle.primaryBlue }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        let a = Int(round(c.alphaComponent * 255))
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
