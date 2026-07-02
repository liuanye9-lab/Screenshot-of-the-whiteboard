// PermissionsPanel.swift — 权限引导面板（一键申请 + 自动检测）
import AppKit

class PermissionsPanel {

    private weak var panel: NSWindow?
    private var refreshTimer: Timer?
    private var statusIconView: NSImageView?
    private var titleLabel: NSTextField?
    private var actionButton: NSButton?
    private var openSettingsButton: NSButton?
    private var hintLabel: NSTextField?

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
        self.panel = panel

        let root = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        root.wantsLayer = true

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        blur.material = .sidebar
        blur.state = .active
        blur.blendingMode = .withinWindow
        blur.wantsLayer = true
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)

        let iconImg = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        let iconView = NSImageView(image: iconImg ?? NSImage())
        iconView.contentTintColor = LeafStyle.primaryBlue
        iconView.frame = NSRect(x: (panelW - 56) / 2, y: panelH - 90, width: 56, height: 56)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(iconView)
        self.statusIconView = iconView

        let titleLabel = NSTextField(labelWithString: "需要两项权限")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 28, y: panelH - 130, width: panelW - 56, height: 30)
        root.addSubview(titleLabel)
        self.titleLabel = titleLabel

        let subtitle = NSTextField(labelWithString: "点击一键申请后，在系统提示中允许即可")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 28, y: panelH - 156, width: panelW - 56, height: 18)
        root.addSubview(subtitle)

        addPermissionRow(
            to: root, y: panelH - 210,
            icon: "rectangle.on.rectangle",
            title: "屏幕录制",
            description: "截取屏幕内容"
        )

        addPermissionRow(
            to: root, y: panelH - 270,
            icon: "hand.tap",
            title: "辅助功能",
            description: "全局快捷键 / 窗口控制"
        )

        let hintLabel = NSTextField(labelWithString: "")
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.frame = NSRect(x: 28, y: 58, width: panelW - 56, height: 14)
        root.addSubview(hintLabel)
        self.hintLabel = hintLabel

        let actionBtn = NSButton(frame: NSRect(x: (panelW - 240) / 2, y: 16, width: 240, height: 36))
        actionBtn.bezelStyle = .rounded
        actionBtn.title = "一键申请权限"
        actionBtn.wantsLayer = true
        actionBtn.layer?.backgroundColor = LeafStyle.primaryBlue.cgColor
        actionBtn.contentTintColor = .white
        actionBtn.layer?.cornerRadius = 10
        actionBtn.target = self
        actionBtn.action = #selector(requestPermissions(_:))
        root.addSubview(actionBtn)
        self.actionButton = actionBtn

        let settingsBtn = NSButton(frame: NSRect(x: (panelW - 240) / 2, y: 16, width: 240, height: 36))
        settingsBtn.bezelStyle = .rounded
        settingsBtn.title = "打开系统设置"
        settingsBtn.wantsLayer = true
        settingsBtn.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        settingsBtn.contentTintColor = .labelColor
        settingsBtn.layer?.cornerRadius = 10
        settingsBtn.target = self
        settingsBtn.action = #selector(openSettings(_:))
        settingsBtn.isHidden = true
        root.addSubview(settingsBtn)
        self.openSettingsButton = settingsBtn

        panel.contentView = root
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        updateUI()
        startPolling()
    }

    private func addPermissionRow(to parent: NSView, y: CGFloat, icon: String, title: String, description: String) {
        let card = NSView(frame: NSRect(x: 24, y: y, width: 372, height: 50))
        card.wantsLayer = true
        card.layer?.cornerRadius = LeafStyle.smallRadius
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        parent.addSubview(card)

        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            let iconView = NSImageView(image: img.withSymbolConfiguration(config)!)
            iconView.contentTintColor = LeafStyle.primaryBlue
            iconView.frame = NSRect(x: 16, y: (50 - 20) / 2, width: 20, height: 20)
            card.addSubview(iconView)
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.frame = NSRect(x: 48, y: 24, width: 180, height: 18)
        card.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 48, y: 6, width: 220, height: 16)
        card.addSubview(descLabel)

        let status = NSTextField(labelWithString: "待授权")
        status.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        status.frame = NSRect(x: 270, y: 14, width: 86, height: 18)
        status.tag = title == "屏幕录制" ? 100 : 101
        card.addSubview(status)
    }

    private func updateUI() {
        let screenGranted = PermissionManager.checkScreenRecording()
        let accessibilityGranted = PermissionManager.checkAccessibility()

        updateStatus(tag: 100, granted: screenGranted)
        updateStatus(tag: 101, granted: accessibilityGranted)

        if screenGranted && accessibilityGranted {
            titleLabel?.stringValue = "权限已就绪"
            titleLabel?.textColor = LeafStyle.systemGreen
            actionButton?.isHidden = true
            openSettingsButton?.isHidden = true
            hintLabel?.stringValue = "SnapLeaf 将在 2 秒后启动"
            statusIconView?.contentTintColor = LeafStyle.systemGreen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.panel?.close()
            }
        } else {
            titleLabel?.stringValue = "需要两项权限"
            titleLabel?.textColor = .labelColor
            actionButton?.isHidden = false
            openSettingsButton?.isHidden = true
            hintLabel?.stringValue = "点击按钮后，按系统提示允许权限"
            statusIconView?.contentTintColor = LeafStyle.primaryBlue
        }
    }

    private func updateStatus(tag: Int, granted: Bool) {
        guard let status = panel?.contentView?.viewWithTag(tag) as? NSTextField else { return }
        status.stringValue = granted ? "已授权" : "待授权"
        status.textColor = granted ? LeafStyle.systemGreen : .secondaryLabelColor
    }

    private func startPolling() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc func requestPermissions(_ sender: Any?) {
        PermissionManager.requestAll()
        actionButton?.isHidden = true
        openSettingsButton?.isHidden = false
        hintLabel?.stringValue = "如系统未自动打开，请点击「打开系统设置」手动勾选 SnapLeaf"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openSettingsIfNeeded()
        }
    }

    @objc func openSettings(_ sender: Any?) {
        openSettingsIfNeeded()
    }

    private func openSettingsIfNeeded() {
        if !PermissionManager.checkAccessibility() {
            PermissionManager.openAccessibilitySettings()
        } else if !PermissionManager.checkScreenRecording() {
            PermissionManager.openScreenRecordingSettings()
        }
    }

    deinit {
        stopPolling()
    }
}
