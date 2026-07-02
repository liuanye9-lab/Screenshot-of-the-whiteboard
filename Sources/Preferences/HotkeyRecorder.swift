// HotkeyRecorder.swift — 快捷键录制控件（AppKit + SwiftUI 桥接）
import AppKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    var initialKey: UInt32
    var initialModifiers: UInt64
    var onChange: (UInt32, UInt64) -> Void

    func makeNSView(context: Context) -> HotkeyRecorder {
        let recorder = HotkeyRecorder()
        recorder.set(key: initialKey, modifiers: initialModifiers)
        recorder.onChange = onChange
        return recorder
    }

    func updateNSView(_ nsView: HotkeyRecorder, context: Context) {
        nsView.set(key: initialKey, modifiers: initialModifiers)
        nsView.onChange = onChange
    }
}

final class HotkeyRecorder: NSView {
    private var button: NSButton!
    private var keyCode: UInt32 = 0
    private var modifiers: UInt64 = 0
    var onChange: ((UInt32, UInt64) -> Void)?

    private var isListening = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        button = NSButton(frame: bounds)
        button.bezelStyle = .rounded
        button.title = "点击设置"
        button.target = self
        button.action = #selector(startListening)
        button.autoresizingMask = [.width, .height]
        addSubview(button)
    }

    func set(key: UInt32, modifiers: UInt64) {
        self.keyCode = key
        self.modifiers = modifiers
        button.title = HotkeySettings.describe(key: key, modifiers: modifiers)
    }

    @objc private func startListening() {
        isListening = true
        button.title = "请按下快捷键..."
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isListening else { return }

        let flags = event.modifierFlags
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) || flags.contains(.shift) else {
            NSSound.beep()
            return
        }

        var cgModifiers: UInt64 = 0
        if flags.contains(.command) { cgModifiers |= HotkeySettings.cgCommand }
        if flags.contains(.option) { cgModifiers |= HotkeySettings.cgOption }
        if flags.contains(.control) { cgModifiers |= HotkeySettings.cgControl }
        if flags.contains(.shift) { cgModifiers |= HotkeySettings.cgShift }

        let code = UInt32(event.keyCode)
        set(key: code, modifiers: cgModifiers)
        isListening = false
        onChange?(code, cgModifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        // 忽略单独修饰键
    }

    override func keyUp(with event: NSEvent) {
        // 监听 keyDown 完成即可
    }
}
