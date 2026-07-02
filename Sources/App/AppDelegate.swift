// AppDelegate.swift — 菜单栏应用主控制器
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var lastCapture: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for window in NSApp.windows {
            window.orderOut(nil)
        }

        ScreenshotHistory.shared.load()
        SettingsManager.shared.update { _ in }
        setupMenuBar()
        setupHotkeys()

        if !PermissionManager.allGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPermissionsGuide()
            }
        }

        if SettingsManager.shared.settings.launchAtLogin {
            LaunchAtLoginHelper.register()
        }
    }

    // MARK: - 菜单栏

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapLeaf") {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                button.image = icon.withSymbolConfiguration(config)
            } else {
                button.title = "SL"
            }
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let s = HotkeySettings.load()

        menu.addItem(withTitle: "局部截图  \(HotkeySettings.describe(key: s.regionKey, modifiers: s.regionModifiers))",
                      action: #selector(captureRegion), keyEquivalent: "")
        menu.addItem(withTitle: "整页截图  \(HotkeySettings.describe(key: s.fullScreenKey, modifiers: s.fullScreenModifiers))",
                      action: #selector(captureFullScreen), keyEquivalent: "")
        menu.addItem(withTitle: "窗口截图  \(HotkeySettings.describe(key: s.windowKey, modifiers: s.windowModifiers))",
                      action: #selector(captureWindow), keyEquivalent: "")

        // 选择显示器
        let displaysItem = NSMenuItem(title: "选择显示器", action: nil, keyEquivalent: "")
        let displaysMenu = NSMenu()
        for (idx, screen) in NSScreen.screens.enumerated() {
            let size = screen.frame.size
            let item = NSMenuItem(title: "显示器 \(idx + 1)  \(Int(size.width))×\(Int(size.height))",
                                  action: #selector(captureScreenItemSelected(_:)), keyEquivalent: "")
            item.tag = idx
            item.target = self
            displaysMenu.addItem(item)
        }
        displaysItem.submenu = displaysMenu
        menu.addItem(displaysItem)

        menu.addItem(withTitle: "长图截图  \(HotkeySettings.describe(key: s.scrollKey, modifiers: s.scrollModifiers))",
                      action: #selector(captureScrolling), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "标注上次截图  \(HotkeySettings.describe(key: s.annotateKey, modifiers: s.annotateModifiers))",
                      action: #selector(annotateLastCapture), keyEquivalent: "")
        menu.addItem(withTitle: "置顶上次截图",
                      action: #selector(pinLastCapture), keyEquivalent: "")
        menu.addItem(withTitle: "OCR 识别上次截图",
                      action: #selector(ocrLastCapture), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        // 截图历史
        let historyItem = NSMenuItem(title: "截图历史", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        historyMenu.addItem(withTitle: "历史管理器...", action: #selector(showHistoryWindow), keyEquivalent: "")
        historyMenu.addItem(NSMenuItem.separator())
        let entries = ScreenshotHistory.shared.allEntries()
        if entries.isEmpty {
            historyMenu.addItem(withTitle: "暂无截图", action: nil, keyEquivalent: "")
        } else {
            for entry in entries.prefix(10) {
                let item = NSMenuItem(title: "\(entry.dateText)  \(entry.fileName)", action: #selector(historyItemSelected(_:)), keyEquivalent: "")
                item.representedObject = entry.id.uuidString
                item.target = self
                historyMenu.addItem(item)
            }
            historyMenu.addItem(NSMenuItem.separator())
            historyMenu.addItem(withTitle: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关闭所有贴图", action: #selector(closeAllPins), keyEquivalent: "")
        menu.addItem(withTitle: "设置...", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "权限设置...", action: #selector(showPermissionsGuide), keyEquivalent: "")
        menu.addItem(withTitle: "关于 SnapLeaf", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 SnapLeaf  \(HotkeySettings.describe(key: s.quitKey, modifiers: s.quitModifiers))",
                      action: #selector(quitApp), keyEquivalent: "")

        for item in menu.items {
            if item.target == nil { item.target = self }
        }

        statusItem.menu = menu
    }

    @objc private func statusItemClicked(_ sender: NSButton) {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    // MARK: - 快捷键

    private func setupHotkeys() {
        let manager = HotkeyManager.shared
        manager.onRegionCapture = { [weak self] in self?.captureRegion() }
        manager.onFullScreenCapture = { [weak self] in self?.captureFullScreen() }
        manager.onWindowCapture = { [weak self] in self?.captureWindow() }
        manager.onScrollCapture = { [weak self] in self?.captureScrolling() }
        manager.onAnnotateLastCapture = { [weak self] in self?.annotateLastCapture() }
        manager.onQuit = { [weak self] in self?.quitApp() }
        manager.install()
    }

    // MARK: - 截图动作

    @objc func captureRegion() {
        guard PermissionManager.checkScreenRecording() else { showPermissionsGuide(); return }
        Task { @MainActor in
            do {
                let image = try await CaptureService.captureRegion()
                self.handleNewCapture(image)
            } catch CaptureError.captureCancelled {
                // 用户取消
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc func captureFullScreen() {
        guard PermissionManager.checkScreenRecording() else { showPermissionsGuide(); return }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                let image = try await CaptureService.captureFullScreen()
                self.handleNewCapture(image)
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc func captureFrontmostWindow() {
        guard PermissionManager.checkScreenRecording() else { showPermissionsGuide(); return }
        do {
            let image = try CaptureService.captureFrontmostWindow()
            handleNewCapture(image)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func captureWindow() {
        guard PermissionManager.checkScreenRecording() else { showPermissionsGuide(); return }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                let image = try await CaptureService.captureWindow()
                self.handleNewCapture(image)
            } catch CaptureError.captureCancelled {
                // 用户取消
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc func captureScreenItemSelected(_ sender: NSMenuItem) {
        guard PermissionManager.checkScreenRecording() else { showPermissionsGuide(); return }
        let idx = sender.tag
        guard idx >= 0, idx < NSScreen.screens.count else { return }
        let screen = NSScreen.screens[idx]
        guard let image = CaptureService.captureScreen(screen) else {
            showError("无法截取该显示器")
            return
        }
        handleNewCapture(image)
    }

    @objc func captureScrolling() {
        guard PermissionManager.checkScreenRecording() else { showPermissionsGuide(); return }
        guard PermissionManager.checkAccessibility() else { showPermissionsGuide(); return }

        let alert = NSAlert()
        alert.messageText = "长图截图"
        alert.informativeText = "点击「开始」后将自动截取前台窗口的可视内容并逐屏滚动拼接。\n\n按 ESC 可随时取消。"
        alert.addButton(withTitle: "开始截取")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            CaptureService.captureScrolling { [weak self] image in
                guard let self = self, let image = image else { return }
                self.handleNewCapture(image)
            }
        }
    }

    /// 统一处理新截图：保存历史 → 根据设置进入标注或复制
    private func handleNewCapture(_ image: NSImage) {
        lastCapture = image
        _ = ScreenshotHistory.shared.save(image)

        if SettingsManager.shared.settings.autoCopyToClipboard {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }

        if SettingsManager.shared.settings.autoOpenAnnotation {
            showAnnotation(image: image)
        } else if let screen = NSScreen.main {
            ToastWindow(message: "截图已保存", screen: screen).show()
        }
    }

    @objc func annotateLastCapture() {
        guard let image = lastCapture else {
            showError("还没有截图，先截一张吧")
            return
        }
        showAnnotation(image: image)
    }

    @objc func pinLastCapture() {
        guard let image = lastCapture else {
            showError("还没有截图，先截一张吧")
            return
        }
        PinToScreenManager.shared.pin(image: image, opacity: SettingsManager.shared.settings.pinnedOpacity)
    }

    @objc func ocrLastCapture() {
        guard let image = lastCapture else {
            showError("还没有截图，先截一张吧")
            return
        }
        Task { @MainActor in
            do {
                let text = try await OCRService.recognizeAndCopy(in: image)
                if text.isEmpty {
                    self.showError("未识别到文字内容")
                } else {
                    // 显示 OCR 结果
                    self.showOCRResult(text)
                }
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc func closeAllPins() {
        PinToScreenManager.shared.closeAll()
    }

    // MARK: - 历史菜单

    @objc private func historyItemSelected(_ sender: NSMenuItem) {
        guard let uuidStr = sender.representedObject as? String,
              let uuid = UUID(uuidString: uuidStr),
              let entry = ScreenshotHistory.shared.entry(id: uuid),
              let image = ScreenshotHistory.shared.loadImage(for: entry) else { return }
        lastCapture = image
        showAnnotation(image: image)
    }

    @objc func showHistoryWindow() {
        let controller = HistoryWindowController.shared
        controller.onAnnotate = { [weak self] image in
            self?.lastCapture = image
            self?.showAnnotation(image: image)
        }
        controller.onPin = { [weak self] image in
            self?.lastCapture = image
            PinToScreenManager.shared.pin(image: image, opacity: SettingsManager.shared.settings.pinnedOpacity)
        }
        controller.show()
    }

    @objc private func clearHistory() {
        let entries = ScreenshotHistory.shared.allEntries()
        for entry in entries {
            ScreenshotHistory.shared.delete(id: entry.id)
        }
        rebuildMenu()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func showAnnotation(image: NSImage, originalFrame: CGRect? = nil) {
        let overlay = AnnotationOverlayWindow(image: image, originalFrame: originalFrame)
        overlay.makeKeyAndOrderFront(nil)
    }

    private func showOCRResult(_ text: String) {
        OCRResultWindowController.show(text: text)
    }

    // MARK: - 权限引导

    @objc func showPermissionsGuide() {
        let panel = PermissionsPanel()
        panel.showGuide()
    }

    @objc func showAbout() {
        let s = HotkeySettings.load()
        let alert = NSAlert()
        alert.messageText = "SnapLeaf v1.1.0"
        alert.informativeText = """
        轻量截图 + 全局标注白板 + AI 元数据导出

        快捷键：
          局部截图    \(HotkeySettings.describe(key: s.regionKey, modifiers: s.regionModifiers))
          全屏截图    \(HotkeySettings.describe(key: s.fullScreenKey, modifiers: s.fullScreenModifiers))
          窗口截图    \(HotkeySettings.describe(key: s.windowKey, modifiers: s.windowModifiers))
          长图截图    \(HotkeySettings.describe(key: s.scrollKey, modifiers: s.scrollModifiers))
          标注上次    \(HotkeySettings.describe(key: s.annotateKey, modifiers: s.annotateModifiers))
          退出        \(HotkeySettings.describe(key: s.quitKey, modifiers: s.quitModifiers))

        标注工具 (⌘1-7)：
          矩形框 · 箭头 · 文字 · 画笔 · 马赛克 · 高亮 · 序号

        标注层操作：
          滚轮缩放 · 空格拖拽 · 多步撤销重做 · 磁吸辅助线 · 双击编辑文字
          ⌘⇧C 复制图片 + JSON 元数据    ⌘S 保存 PNG + JSON

        额外功能：
          多显示器选屏 · 置顶贴图 · OCR 文字识别 · 历史管理器 · 快捷键自定义
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SnapLeaf"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
