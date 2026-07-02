// ScreenshotHistory.swift — 截图历史管理 + OCR 文字识别
import AppKit
import Vision

// MARK: - 截图历史

class ScreenshotHistory {
    static let shared = ScreenshotHistory()

    private var entries: [HistoryEntry] = []
    private let maxEntries = 50

    struct HistoryEntry: Identifiable {
        let id = UUID()
        let date: Date
        let imageURL: URL
        var thumbnail: NSImage?

        var fileName: String { imageURL.lastPathComponent }
        var dateText: String {
            let fmt = DateFormatter()
            fmt.dateFormat = "MM-dd HH:mm"
            return fmt.string(from: date)
        }
    }

    private var historyDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SnapLeaf/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存截图到历史
    func save(_ image: NSImage) -> URL? {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "snap_\(timestamp).png"
        let url = historyDir.appendingPathComponent(filename)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        do {
            try pngData.write(to: url)
            let entry = HistoryEntry(date: Date(), imageURL: url, thumbnail: makeThumbnail(image))
            entries.insert(entry, at: 0)

            // 超出上限时删除最旧的
            if entries.count > maxEntries {
                let removed = entries.removeLast()
                try? FileManager.default.removeItem(at: removed.imageURL)
            }
            return url
        } catch {
            return nil
        }
    }

    /// 加载历史
    func load() {
        entries.removeAll()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        let pngFiles = files.filter { $0.pathExtension == "png" }
            .sorted(by: { (a, b) -> Bool in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            })

        for file in pngFiles.prefix(maxEntries) {
            if let img = NSImage(contentsOf: file) {
                let fileDate = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let entry = HistoryEntry(
                    date: fileDate,
                    imageURL: file,
                    thumbnail: makeThumbnail(img)
                )
                entries.append(entry)
            }
        }
    }

    /// 获取所有历史条目
    func allEntries() -> [HistoryEntry] { entries }

    /// 按 ID 获取条目
    func entry(id: UUID) -> HistoryEntry? { entries.first { $0.id == id } }

    /// 加载图片
    func loadImage(for entry: HistoryEntry) -> NSImage? {
        NSImage(contentsOf: entry.imageURL)
    }

    /// 删除条目
    func delete(id: UUID) {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[idx]
            try? FileManager.default.removeItem(at: entry.imageURL)
            entries.remove(at: idx)
        }
    }

    private func makeThumbnail(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 120, height: 80)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        let ratio = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * ratio
        let h = image.size.height * ratio
        image.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        thumb.unlockFocus()
        return thumb
    }
}
