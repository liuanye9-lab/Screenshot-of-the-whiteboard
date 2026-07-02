// HotkeyManager.swift — 全局快捷键管理（CGEvent Tap + NSEvent）
import AppKit
import Carbon.HIToolbox

class HotkeyManager {

    var onRegionCapture: (() -> Void)?
    var onFullScreenCapture: (() -> Void)?
    var onWindowCapture: (() -> Void)?
    var onScrollCapture: (() -> Void)?
    var onAnnotateLastCapture: (() -> Void)?
    var onQuit: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installed = false

    static let shared = HotkeyManager()

    struct KeyCombo: Equatable, Hashable {
        let keyCode: Int
        let modifiers: CGEventFlags

        init(keyCode: Int, modifiers: CGEventFlags) {
            self.keyCode = keyCode
            self.modifiers = modifiers.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers.rawValue)
        }

        static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
            lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
        }
    }

    private var hotkeys: [KeyCombo: () -> Void] = [:]

    func install() {
        guard !installed else { return }
        installed = true

        let settings = HotkeySettings.load()

        hotkeys[KeyCombo(keyCode: Int(settings.regionKey), modifiers: CGEventFlags(rawValue: settings.regionCGModifiers))] = { [weak self] in self?.onRegionCapture?() }
        hotkeys[KeyCombo(keyCode: Int(settings.fullScreenKey), modifiers: CGEventFlags(rawValue: settings.fullScreenCGModifiers))] = { [weak self] in self?.onFullScreenCapture?() }
        hotkeys[KeyCombo(keyCode: Int(settings.windowKey), modifiers: CGEventFlags(rawValue: settings.windowCGModifiers))] = { [weak self] in self?.onWindowCapture?() }
        hotkeys[KeyCombo(keyCode: Int(settings.scrollKey), modifiers: CGEventFlags(rawValue: settings.scrollCGModifiers))] = { [weak self] in self?.onScrollCapture?() }
        hotkeys[KeyCombo(keyCode: Int(settings.annotateKey), modifiers: CGEventFlags(rawValue: settings.annotateCGModifiers))] = { [weak self] in self?.onAnnotateLastCapture?() }
        hotkeys[KeyCombo(keyCode: Int(settings.quitKey), modifiers: CGEventFlags(rawValue: settings.quitCGModifiers))] = { [weak self] in self?.onQuit?() }

        // 额外别名：⌘R 也作为整页/全屏截图
        hotkeys[KeyCombo(keyCode: Int(kVK_ANSI_R), modifiers: .maskCommand)] = { [weak self] in self?.onFullScreenCapture?() }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard type == .keyDown, let manager = HotkeyManager.shared.installed ? HotkeyManager.shared : nil else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
                let combo = KeyCombo(keyCode: Int(keyCode), modifiers: flags)

                if let action = manager.hotkeys[combo] {
                    DispatchQueue.main.async { action() }
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            installNSEventFallback(settings: settings)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func uninstall() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        hotkeys.removeAll()
        installed = false
    }

    // MARK: - NSEvent 回退方案

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private func installNSEventFallback(settings: HotkeySettings) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleNSEvent(event) == true { return nil }
            return event
        }
    }

    @discardableResult
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        let flags: CGEventFlags
        if event.modifierFlags.contains(.command) { flags = .maskCommand }
        else if event.modifierFlags.contains(.option) { flags = .maskAlternate }
        else if event.modifierFlags.contains(.control) { flags = .maskControl }
        else if event.modifierFlags.contains(.shift) { flags = .maskShift }
        else { flags = [] }

        let combo = KeyCombo(keyCode: Int(event.keyCode), modifiers: flags)
        if let action = hotkeys[combo] {
            action()
            return true
        }
        return false
    }
}
