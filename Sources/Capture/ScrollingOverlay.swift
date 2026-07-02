// ScrollingOverlay.swift — 手动滚动长图选择覆层
import AppKit
import CoreGraphics
import Carbon.HIToolbox

class ScrollingOverlayWindow: NSWindow {
    var onComplete: ((NSImage?) -> Void)?
    private let overlayView: ScrollingOverlayView

    init(initialImage: NSImage, windowRect: CGRect, callback: @escaping (NSImage?) -> Void) {
        self.onComplete = callback
        let screenFrame = NSScreen.main?.frame ?? windowRect
        self.overlayView = ScrollingOverlayView(frame: NSRect(origin: .zero, size: screenFrame.size), initialImage: initialImage, windowRect: windowRect)
        super.init(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: true)

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        overlayView.onComplete = { [weak self] img in
            self?.onComplete?(img)
            self?.orderOut(nil)
        }
        self.contentView = overlayView
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class ScrollingOverlayView: NSView {
    var onComplete: ((NSImage?) -> Void)?
    private var stitchedImage: NSImage
    private var windowRect: CGRect
    private var isCapturing = false
    private var captureCount = 0
    private let maxCaptures = 20

    init(frame: NSRect, initialImage: NSImage, windowRect: CGRect) {
        self.stitchedImage = initialImage
        self.windowRect = windowRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        let imgSize = stitchedImage.size
        let drawRect = CGRect(
            x: (bounds.width - imgSize.width) / 2,
            y: (bounds.height - imgSize.height) / 2,
            width: imgSize.width,
            height: imgSize.height
        )
        stitchedImage.draw(in: drawRect)

        let text = "滚动鼠标/触控板向下选取长图区域，↵ 完成，ESC 取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let bg = NSRect(
            x: (bounds.width - size.width - 24) / 2,
            y: bounds.height - 72,
            width: size.width + 24,
            height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: bg.minX + 12, y: bg.minY + 7), withAttributes: attrs)
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isCapturing, captureCount < maxCaptures else { return }
        let delta = event.scrollingDeltaY
        guard delta < -5 else { return } // 仅响应向下滚动
        isCapturing = true
        captureCount += 1

        let scrollAmount = min(abs(delta) * 2, windowRect.height * 0.8)
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -Int32(scrollAmount), wheel2: 0, wheel3: 0) {
            scrollEvent.location = CGPoint(x: windowRect.midX, y: windowRect.midY)
            scrollEvent.post(tap: .cgSessionEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureAndAppend(scrollAmount: scrollAmount)
        }
    }

    private func captureAndAppend(scrollAmount: CGFloat) {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else { isCapturing = false; return }
        let cropped = cropCGImage(cgImage, to: windowRect)
        if let newStitched = appendImage(cropped, overlap: scrollAmount * 0.15) {
            stitchedImage = newStitched
            needsDisplay = true
        }
        isCapturing = false
    }

    private func appendImage(_ newImage: CGImage, overlap: CGFloat) -> NSImage? {
        guard let baseCG = stitchedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let overlapPx = Int(overlap * (CGFloat(baseCG.width) / windowRect.width))
        let width = max(baseCG.width, newImage.width)
        let totalHeight = baseCG.height + newImage.height - overlapPx

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(baseCG, in: CGRect(x: 0, y: newImage.height - overlapPx, width: baseCG.width, height: baseCG.height))
        ctx.draw(newImage, in: CGRect(x: 0, y: 0, width: newImage.width, height: newImage.height))

        guard let result = ctx.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: width, height: totalHeight))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            onComplete?(nil)
            window?.orderOut(nil)
        } else if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
            onComplete?(stitchedImage)
            window?.orderOut(nil)
        }
    }
}

private func cropCGImage(_ image: CGImage, to rect: CGRect) -> CGImage {
    let scale = CGFloat(image.width) / CGFloat(NSScreen.main?.frame.width ?? 1)
    let scaledRect = CGRect(
        x: rect.origin.x * scale,
        y: (CGFloat(NSScreen.main?.frame.height ?? 1) - rect.origin.y - rect.height) * scale,
        width: rect.width * scale,
        height: rect.height * scale
    )
    return image.cropping(to: scaledRect) ?? image
}
