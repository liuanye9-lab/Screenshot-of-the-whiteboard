// HotkeySettings.swift — 全局快捷键配置持久化
import AppKit
import Carbon.HIToolbox

struct HotkeySettings: Codable {
    var regionKey: UInt32
    var regionModifiers: UInt64
    var fullScreenKey: UInt32
    var fullScreenModifiers: UInt64
    var scrollKey: UInt32
    var scrollModifiers: UInt64
    var annotateKey: UInt32
    var annotateModifiers: UInt64
    var quitKey: UInt32
    var quitModifiers: UInt64

    var regionCGModifiers: UInt64 { regionModifiers }
    var fullScreenCGModifiers: UInt64 { fullScreenModifiers }
    var scrollCGModifiers: UInt64 { scrollModifiers }
    var annotateCGModifiers: UInt64 { annotateModifiers }
    var quitCGModifiers: UInt64 { quitModifiers }

    static let cgCommand: UInt64  = 0x00100000
    static let cgShift: UInt64    = 0x00020000
    static let cgOption: UInt64   = 0x00080000
    static let cgControl: UInt64  = 0x00040000

    static let defaults = HotkeySettings(
        regionKey: UInt32(kVK_ANSI_E),
        regionModifiers: cgOption,
        fullScreenKey: UInt32(kVK_ANSI_Q),
        fullScreenModifiers: cgOption,
        scrollKey: UInt32(kVK_ANSI_W),
        scrollModifiers: cgOption,
        annotateKey: UInt32(kVK_ANSI_A),
        annotateModifiers: cgOption,
        quitKey: UInt32(kVK_ANSI_Q),
        quitModifiers: cgCommand
    )

    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapLeaf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hotkeys.json")
    }

    static func load() -> HotkeySettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(HotkeySettings.self, from: data) else {
            return defaults
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: HotkeySettings.settingsURL)
    }

    static func describe(key: UInt32, modifiers: UInt64) -> String {
        var parts: [String] = []
        if modifiers & cgControl != 0 { parts.append("⌃") }
        if modifiers & cgOption != 0 { parts.append("⌥") }
        if modifiers & cgShift != 0 { parts.append("⇧") }
        if modifiers & cgCommand != 0 { parts.append("⌘") }

        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        ]
        parts.append(keyMap[key] ?? "?")
        return parts.joined()
    }

    static func nsEventModifiers(_ modifiers: UInt64) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & cgCommand != 0 { flags.insert(.command) }
        if modifiers & cgShift != 0 { flags.insert(.shift) }
        if modifiers & cgOption != 0 { flags.insert(.option) }
        if modifiers & cgControl != 0 { flags.insert(.control) }
        return flags
    }
}
