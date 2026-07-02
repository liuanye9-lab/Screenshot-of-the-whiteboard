// ToastWindow.swift — 全局轻量提示浮窗
import AppKit

class ToastWindow: NSWindow {
    init(message: String, screen: NSScreen, icon: String = "checkmark.circle.fill") {
        let width: CGFloat = 220
        let height: CGFloat = 44
        let frame = NSRect(
            x: (screen.frame.width - width) / 2,
            y: screen.frame.height * 0.7,
            width: width,
            height: height
        )
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.alphaValue = 0

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = height / 2
        container.layer?.masksToBounds = true
        self.contentView = container

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.frame = NSRect(x: 40, y: 0, width: frame.width - 52, height: frame.height)
        container.addSubview(label)

        if let checkmark = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            let iconView = NSImageView(image: checkmark.withSymbolConfiguration(config)!)
            iconView.contentTintColor = LeafStyle.systemGreen
            iconView.frame = NSRect(x: 16, y: (height - 18) / 2, width: 18, height: 18)
            container.addSubview(iconView)
        }
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 1
        } completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    self.animator().alphaValue = 0
                }, completionHandler: {
                    self.orderOut(nil)
                })
            }
        }
    }
}
