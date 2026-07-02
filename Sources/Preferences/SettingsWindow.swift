// SettingsWindow.swift — 基于 SwiftUI 的偏好设置窗口
import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "SnapLeaf 设置"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.center()

        let hosting = NSHostingController(rootView: SettingsView(onRelaunchHotkeys: {
            HotkeyManager.shared.uninstall()
            HotkeyManager.shared.install()
        }))
        w.contentView = hosting.view
        w.contentViewController = hosting

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    let onRelaunchHotkeys: () -> Void

    @State private var settings = SettingsManager.shared.settings
    @State private var hotkeys = HotkeySettings.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SnapLeaf 设置")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding([.top, .horizontal], 24)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    shortcutsSection
                    Divider()
                    generalSection
                    Divider()
                    aboutSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.system(size: 15, weight: .semibold))

            shortcutRow("局部截图", key: $hotkeys.regionKey, modifiers: $hotkeys.regionModifiers)
            shortcutRow("整页截图", key: $hotkeys.fullScreenKey, modifiers: $hotkeys.fullScreenModifiers)
            shortcutRow("窗口截图", key: $hotkeys.windowKey, modifiers: $hotkeys.windowModifiers)
            shortcutRow("长图截图", key: $hotkeys.scrollKey, modifiers: $hotkeys.scrollModifiers)
            shortcutRow("标注上次截图", key: $hotkeys.annotateKey, modifiers: $hotkeys.annotateModifiers)
            shortcutRow("退出应用", key: $hotkeys.quitKey, modifiers: $hotkeys.quitModifiers)

            HStack {
                Spacer()
                Button("恢复默认") {
                    hotkeys = .defaults
                    persistHotkeys()
                }
                .controlSize(.small)
                Button("保存") {
                    persistHotkeys()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func shortcutRow(_ label: String, key: Binding<UInt32>, modifiers: Binding<UInt64>) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
            HotkeyRecorderView(
                initialKey: key.wrappedValue,
                initialModifiers: modifiers.wrappedValue,
                onChange: { newKey, newModifiers in
                    key.wrappedValue = newKey
                    modifiers.wrappedValue = newModifiers
                    persistHotkeys()
                }
            )
            .frame(width: 140, height: 28)
            Spacer()
        }
    }

    private func persistHotkeys() {
        hotkeys.save()
        onRelaunchHotkeys()
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("通用")
                .font(.system(size: 15, weight: .semibold))

            Toggle("截图后自动标注", isOn: $settings.autoOpenAnnotation)
            Toggle("截图后自动复制到剪贴板", isOn: $settings.autoCopyToClipboard)
            Toggle("登录时启动 SnapLeaf", isOn: $settings.launchAtLogin)

            HStack {
                Text("贴图默认透明度")
                Slider(value: $settings.pinnedOpacity, in: 0.3...1.0)
                Text("\(Int(settings.pinnedOpacity * 100))%")
                    .monospacedDigit()
                    .frame(width: 40)
            }

            HStack {
                Text("默认画笔粗细")
                Slider(value: $settings.defaultStrokeWidth, in: 1.0...10.0)
                Text("\(Int(settings.defaultStrokeWidth))")
                    .monospacedDigit()
                    .frame(width: 30)
            }

            HStack {
                Text("保存目录")
                Text(settings.effectiveSaveDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(settings.effectiveSaveDirectory.path)
                Spacer()
                Button("更改...") {
                    chooseSaveDirectory()
                }
                .controlSize(.small)
            }
        }
        .onChange(of: settings) { _, newValue in
            SettingsManager.shared.update { $0 = newValue }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 32))
                    .foregroundColor(.leafAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SnapLeaf")
                        .font(.system(size: 16, weight: .semibold))
                    Text("版本 1.1.0 · 轻量截图 + 全局标注白板")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = settings.effectiveSaveDirectory

        panel.begin { result in
            if result == .OK, let url = panel.url {
                settings.saveDirectoryURL = url
                SettingsManager.shared.update { $0.saveDirectoryURL = url }
            }
        }
    }
}

extension Color {
    static var leafAccent: Color { Color(nsColor: LeafStyle.primaryBlue) }
}
