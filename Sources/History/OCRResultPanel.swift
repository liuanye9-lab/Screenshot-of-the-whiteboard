// OCRResultPanel.swift — OCR 识别结果面板
import AppKit
import SwiftUI

final class OCRResultWindowController {
    static func show(text: String) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "OCR 识别结果"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.center()

        let view = OCRResultView(text: text) {
            w.close()
        }
        let hosting = NSHostingController(rootView: view)
        w.contentView = hosting.view
        w.contentViewController = hosting

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OCRResultView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OCR 识别结果")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("复制全部") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
                .controlSize(.small)
                Button("关闭") {
                    onClose()
                }
                .controlSize(.small)
            }
            .padding(20)

            TextEditor(text: .constant(text))
                .font(.system(size: 14, design: .monospaced))
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }
}
