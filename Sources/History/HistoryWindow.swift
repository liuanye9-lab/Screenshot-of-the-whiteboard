// HistoryWindow.swift — 截图历史浏览器（缩略图网格 + 双击重新标注）
import AppKit
import SwiftUI

final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    var onAnnotate: ((NSImage) -> Void)?
    var onPin: ((NSImage) -> Void)?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "SnapLeaf 截图历史"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.center()

        let view = HistoryView(
            onAnnotate: { [weak self] image in self?.onAnnotate?(image) },
            onPin: { [weak self] image in self?.onPin?(image) }
        )
        let hosting = NSHostingController(rootView: view)
        w.contentView = hosting.view
        w.contentViewController = hosting

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct HistoryView: View {
    let onAnnotate: (NSImage) -> Void
    let onPin: (NSImage) -> Void

    @State private var entries: [ScreenshotHistory.HistoryEntry] = []
    @State private var selectedID: UUID? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("截图历史")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("清空全部") {
                    clearAll()
                }
                .controlSize(.small)
            }
            .padding(20)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(entries) { entry in
                        HistoryThumbnail(entry: entry,
                                         isSelected: selectedID == entry.id,
                                         onAnnotate: { annotate(entry) },
                                         onPin: { pin(entry) },
                                         onDelete: { delete(entry) })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            HStack {
                Text("\(entries.count) 张截图")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("打开选中") {
                    if let id = selectedID, let entry = entries.first(where: { $0.id == id }) {
                        annotate(entry)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedID == nil)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refresh() }
    }

    private func refresh() {
        entries = ScreenshotHistory.shared.allEntries()
    }

    private func annotate(_ entry: ScreenshotHistory.HistoryEntry) {
        guard let image = ScreenshotHistory.shared.loadImage(for: entry) else { return }
        onAnnotate(image)
    }

    private func pin(_ entry: ScreenshotHistory.HistoryEntry) {
        guard let image = ScreenshotHistory.shared.loadImage(for: entry) else { return }
        onPin(image)
    }

    private func delete(_ entry: ScreenshotHistory.HistoryEntry) {
        ScreenshotHistory.shared.delete(id: entry.id)
        if selectedID == entry.id { selectedID = nil }
        refresh()
    }

    private func clearAll() {
        for entry in entries {
            ScreenshotHistory.shared.delete(id: entry.id)
        }
        selectedID = nil
        refresh()
    }
}

struct HistoryThumbnail: View {
    let entry: ScreenshotHistory.HistoryEntry
    let isSelected: Bool
    let onAnnotate: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: NSColor.controlBackgroundColor))
                if let thumb = entry.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color(nsColor: LeafStyle.primaryBlue) : Color.clear, lineWidth: 2)
            )
            .onTapGesture(count: 2) { onAnnotate() }
            .onTapGesture(count: 1) { /* selection handled by parent */ }
            .contextMenu {
                Button("重新标注") { onAnnotate() }
                Button("置顶贴图") { onPin() }
                Divider()
                Button("删除") { onDelete() }
            }

            Text(entry.dateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
            Text(entry.fileName)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
