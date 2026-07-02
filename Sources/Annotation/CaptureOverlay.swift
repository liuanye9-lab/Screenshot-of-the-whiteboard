// CaptureOverlay.swift — 自定义区域截图覆层（放大镜 + 十字准线 + 尺寸标签）
import AppKit
import Carbon.HIToolbox

class CaptureOverlayWindow: NSWindow {
    private let overlayView: CaptureOverlayView
    var onCaptureComplete: ((NSImage?) -> Void)?

    init(screenImage: NSImage, cgImage: CGImage, screenFrame: CGRect, callback: @escaping (NSImage?) -> Void) {
        self.onCaptureComplete = callback
        let frame = screenFrame
        self.overlayView = CaptureOverlayView(frame: NSRect(origin: .zero, size: frame.size), screenImage: screenImage)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        overlayView.onSelectionComplete = { [weak self] rect in
            guard let self = self else { return }
            if let rect = rect {
                let scale = CGFloat(cgImage.width) / frame.size.width
                let cropRect = CGRect(
                    x: rect.origin.x * scale,
                    y: (frame.size.height - rect.origin.y - rect.height) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                )
                if let cropped = cgImage.cropping(to: cropRect) {
                    let result = NSImage(cgImage: cropped, size: NSSize(width: cropRect.width / scale, height: cropRect.height / scale))
                    self.onCaptureComplete?(result)
                } else {
                    self.onCaptureComplete?(nil)
                }
            } else {
                self.onCaptureComplete?(nil)
            }
            self.orderOut(nil)
        }
        self.contentView = overlayView
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class CaptureOverlayView: NSView {
    private let screenImage: NSImage
    private var startPoint: CGPoint?
    private var currentRect: CGRect?
    private var isDragging = false
    private var mouseLocation: CGPoint = .zero
    var onSelectionComplete: ((CGRect?) -> Void)?

    init(frame: NSRect, screenImage: NSImage) {
        self.screenImage = screenImage
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        let trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        mouseLocation = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 1. 先绘制原始屏幕截图作为背景，保持原尺寸
        screenImage.draw(in: bounds, from: NSRect(origin: .zero, size: screenImage.size), operation: .copy, fraction: 1.0)

        // 2. 全局半透明遮罩
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        if let rect = currentRect, rect.width > 2, rect.height > 2 {
            NSGraphicsContext.saveGraphicsState()

            // 3. 在选区中裁剪掉遮罩，露出下方原图
            let clip = NSBezierPath(rect: rect)
            clip.addClip()
            screenImage.draw(in: bounds, from: NSRect(origin: .zero, size: screenImage.size), operation: .copy, fraction: 1.0)

            NSGraphicsContext.restoreGraphicsState()

            let border = NSBezierPath(rect: rect)
            LeafStyle.primaryBlue.setStroke()
            border.lineWidth = 2
            border.stroke()

            let handleSize: CGFloat = 8
            LeafStyle.primaryBlue.setFill()
            for corner in [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ] {
                let handle = NSRect(x: corner.x - handleSize/2, y: corner.y - handleSize/2, width: handleSize, height: handleSize)
                NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
            }

            drawSizeLabel(rect)
        }

        drawCrosshair(at: mouseLocation)
        drawMagnifier(at: mouseLocation)
    }

    private func drawCrosshair(at point: CGPoint) {
        NSColor.white.withAlphaComponent(0.4).setStroke()
        let hLine = NSBezierPath()
        hLine.move(to: NSPoint(x: 0, y: point.y))
        hLine.line(to: NSPoint(x: bounds.width, y: point.y))
        hLine.lineWidth = 0.5
        hLine.stroke()
        let vLine = NSBezierPath()
        vLine.move(to: NSPoint(x: point.x, y: 0))
        vLine.line(to: NSPoint(x: point.x, y: bounds.height))
        vLine.stroke()
    }

    private func drawSizeLabel(_ rect: CGRect) {
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = sizeText.size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.minX, y: rect.minY - labelSize.height - 8,
            width: labelSize.width + 12, height: labelSize.height + 4
        )
        let bg = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        LeafStyle.primaryBlue.setFill()
        bg.fill()
        sizeText.draw(at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 2), withAttributes: attrs)
    }

    private func drawMagnifier(at point: CGPoint) {
        let size = LeafStyle.magnifierSize
        let zoom = LeafStyle.magnifierZoom

        var circleRect = NSRect(x: point.x + 16, y: point.y + 16, width: size, height: size)
        if circleRect.maxX > bounds.width { circleRect.origin.x = point.x - 16 - size }
        if circleRect.maxY > bounds.height { circleRect.origin.y = point.y - 16 - size }
        if circleRect.minX < 0 { circleRect.origin.x = 0 }
        if circleRect.minY < 0 { circleRect.origin.y = 0 }

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(ovalIn: circleRect)
        clip.addClip()

        let srcSize = size / zoom
        let srcRect = CGRect(x: point.x - srcSize / 2, y: point.y - srcSize / 2, width: srcSize, height: srcSize)
        screenImage.draw(in: circleRect, from: srcRect, operation: .copy, fraction: 1.0)

        NSColor.white.withAlphaComponent(0.6).setStroke()
        let cross = NSBezierPath()
        let center = circleRect.center
        cross.move(to: NSPoint(x: center.x, y: circleRect.minY))
        cross.line(to: NSPoint(x: center.x, y: circleRect.maxY))
        cross.move(to: NSPoint(x: circleRect.minX, y: center.y))
        cross.line(to: NSPoint(x: circleRect.maxX, y: center.y))
        cross.lineWidth = 1 / zoom
        cross.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(ovalIn: circleRect)
        border.lineWidth = 2
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        guard isDragging, let start = startPoint else { return }
        let current = mouseLocation
        currentRect = CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        mouseLocation = convert(event.locationInWindow, from: nil)
        if let rect = currentRect, rect.width > 5, rect.height > 5 {
            onSelectionComplete?(rect)
        } else {
            onSelectionComplete?(nil)
        }
        currentRect = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            onSelectionComplete?(nil)
            window?.orderOut(nil)
        }
    }
}
