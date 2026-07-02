// PermissionsPanel.swift — 权限引导面板
import AppKit

class PermissionsPanel {

    func showGuide() {
        let panelW: CGFloat = 420
        let panelH: CGFloat = 360

        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.title = "SnapLeaf 权限设置"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isOpaque = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        root.wantsLayer = true

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        blur.material = .sidebar
        blur.state = .active
        blur.blendingMode = .withinWindow
        blur.wantsLayer = true
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)

        let titleLabel = NSTextField(labelWithString: "权限设置")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.frame = NSRect(x: 28, y: panelH - 70, width: panelW - 56, height: 30)
        root.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "SnapLeaf 需要以下权限才能正常工作")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 28, y: panelH - 92, width: panelW - 56, height: 18)
        root.addSubview(subtitle)

        addPermissionRow(
            to: root, y: panelH - 170,
            icon: "rectangle.on.rectangle",
            title: "屏幕录制",
            description: "截取屏幕内容需要此权限",
            isGranted: PermissionManager.checkScreenRecording(),
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )

        addPermissionRow(
            to: root, y: panelH - 250,
            icon: "hand.tap",
            title: "辅助功能",
            description: "注册全局快捷键和窗口控制需要此权限",
            isGranted: PermissionManager.checkAccessibility(),
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )

        let hint = NSTextField(labelWithString: "授权后可能需要重启 SnapLeaf 才能生效")
        hint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 28, y: 58, width: panelW - 56, height: 14)
        root.addSubview(hint)

        let closeBtn = NSButton(frame: NSRect(x: (panelW - 150) / 2, y: 16, width: 150, height: 34))
        closeBtn.bezelStyle = .rounded
        closeBtn.title = "关闭"
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = LeafStyle.primaryBlue.cgColor
        closeBtn.contentTintColor = .white
        closeBtn.layer?.cornerRadius = 10
        closeBtn.target = self
        closeBtn.action = #selector(closePanel(_:))
        root.addSubview(closeBtn)

        panel.contentView = root
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addPermissionRow(to parent: NSView, y: CGFloat, icon: String, title: String, description: String, isGranted: Bool, settingsURL: String) {
        let card = NSView(frame: NSRect(x: 24, y: y, width: 372, height: 68))
        card.wantsLayer = true
        card.layer?.cornerRadius = LeafStyle.smallRadius
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        parent.addSubview(card)

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            let iconView = NSImageView(image: img.withSymbolConfiguration(config)!)
            iconView.contentTintColor = isGranted ? LeafStyle.systemGreen : LeafStyle.primaryBlue
            iconView.frame = NSRect(x: 16, y: (68 - 22) / 2, width: 22, height: 22)
            card.addSubview(iconView)
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.frame = NSRect(x: 50, y: 38, width: 180, height: 18)
        card.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 50, y: 16, width: 180, height: 16)
        card.addSubview(descLabel)

        let statusBtn = NSButton(frame: NSRect(x: 260, y: 18, width: 96, height: 32))
        statusBtn.bezelStyle = .rounded
        statusBtn.wantsLayer = true
        statusBtn.layer?.cornerRadius = 8

        if isGranted {
            statusBtn.title = "已授权"
            statusBtn.isEnabled = false
            statusBtn.layer?.backgroundColor = LeafStyle.systemGreen.withAlphaComponent(0.15).cgColor
            statusBtn.contentTintColor = LeafStyle.systemGreen
        } else {
            statusBtn.title = "去授权"
            statusBtn.layer?.backgroundColor = LeafStyle.primaryBlue.cgColor
            statusBtn.contentTintColor = .white
            let target = PermissionButtonTarget(settingsURL: settingsURL)
            statusBtn.target = target
            statusBtn.action = #selector(PermissionButtonTarget.openSettings(_:))
            objc_setAssociatedObject(statusBtn, "permTarget", target, .OBJC_ASSOCIATION_RETAIN)
        }
        card.addSubview(statusBtn)
    }

    @objc func closePanel(_ sender: NSButton) {
        sender.window?.close()
    }
}

class PermissionButtonTarget: NSObject {
    let settingsURL: String
    init(settingsURL: String) { self.settingsURL = settingsURL }

    @objc func openSettings(_ sender: Any?) {
        let urlStrings = [
            settingsURL,
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for urlString in urlStrings {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}
