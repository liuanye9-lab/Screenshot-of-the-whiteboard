// SettingsManager.swift — 应用全局偏好设置持久化
import Foundation

struct AppSettings: Codable, Equatable {
    var saveDirectoryURL: URL?
    var autoCopyToClipboard: Bool
    var autoOpenAnnotation: Bool
    var pinnedOpacity: Double
    var launchAtLogin: Bool
    var defaultStrokeWidth: Double

    static let `default` = AppSettings(
        saveDirectoryURL: nil,
        autoCopyToClipboard: true,
        autoOpenAnnotation: true,
        pinnedOpacity: 1.0,
        launchAtLogin: false,
        defaultStrokeWidth: 2.5
    )

    var effectiveSaveDirectory: URL {
        if let url = saveDirectoryURL { return url }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let dir = pictures.appendingPathComponent("SnapLeaf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

final class SettingsManager {
    static let shared = SettingsManager()

    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapLeaf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private(set) var settings: AppSettings {
        didSet { save() }
    }

    private init() {
        if let data = try? Data(contentsOf: Self.settingsURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    func update(_ mutation: (inout AppSettings) -> Void) {
        var copy = settings
        mutation(&copy)
        settings = copy
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: Self.settingsURL)
    }
}
