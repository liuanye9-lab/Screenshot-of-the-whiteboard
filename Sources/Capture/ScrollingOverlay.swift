// ScrollingOverlay.swift — 手动滚动长图控制面板
// 流程：显示一个可交互的悬浮面板，用户滚动目标页面后按「截取当前段」逐步拼接，最后按「完成」进入标注。
import AppKit
import CoreGraphics
import Carbon.HIToolbox

class ScrollingOverlayWindow: NSWindow {
    var onComplete: ((NSImage?) -> Void)?
    private var controlView: ScrollingControlView

    init(windowRect: CGRect, callback: @escaping (NSImage?) -> Void) {
        self.onComplete = callback

        let controlW: CGFloat = 360
        let controlH: CGFloat = 72
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
        let x = screenFrame.midX - controlW / 2
        let y = screenFrame.maxY - controlH - 8

        self.controlView = ScrollingControlView(frame: NSRect(x: 0, y: 0, width: controlW, height: controlH), windowRect: windowRect)
        super.init(contentRect: NSRect(x: x, y: y, width: controlW, height: controlH),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = controlView

        controlView.onCapture = { [weak self] image in
            if let img = image {
                self?.onComplete?(img)
            }
            self?.orderOut(nil)
        }
        controlView.onCancel = { [weak self] in
            self?.onComplete?(nil)
            self?.orderOut(nil)
        }

        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class ScrollingControlView: NSView {
    var onCapture: ((NSImage?) -> Void)?
    var onCancel: (() -> Void)?

    private let windowRect: CGRect
    private var stitchedImage: NSImage?
    private var captureCount = 0

    private lazy var captureButton: NSButton = makeButton(title: "截取当前段 (Space)", color: LeafStyle.primaryBlue, action: #selector(captureSection(_:)))
    private lazy var finishButton: NSButton = makeButton(title: "完成 (↵)", color: LeafStyle.systemGreen, action: #selector(finishCapture(_:)))
    private lazy var cancelButton: NSButton = makeButton(title: "取消 (Esc)", color: NSColor.systemGray, action: #selector(cancelCapture(_:)))
    private lazy var counterLabel: NSTextField = {
        let label = NSTextField(labelWithString: "已捕获: 0 段")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        return label
    }()

    init(frame: NSRect, windowRect: CGRect) {
        self.windowRect = windowRect
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .popover
        blur.state = .active
        blur.blendingMode = .withinWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        counterLabel.frame = NSRect(x: 16, y: 24, width: 90, height: 24)
        addSubview(counterLabel)

        captureButton.frame = NSRect(x: 110, y: 18, width: 110, height: 36)
        addSubview(captureButton)

        finishButton.frame = NSRect(x: 226, y: 18, width: 62, height: 36)
        addSubview(finishButton)

        cancelButton.frame = NSRect(x: 294, y: 18, width: 62, height: 36)
        addSubview(cancelButton)
    }

    private func makeButton(title: String, color: NSColor, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .rounded
        btn.title = title
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.cgColor
        btn.contentTintColor = .white
        btn.layer?.cornerRadius = 8
        btn.target = self
        btn.action = action
        return btn
    }

    override func keyDown(with event: NSEvent) {
        switch UInt32(event.keyCode) {
        case UInt32(kVK_Space):
            captureSection(nil)
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter):
            finishCapture(nil)
        case UInt32(kVK_Escape):
            cancelCapture(nil)
        default:
            super.keyDown(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    @objc private func captureSection(_ sender: Any?) {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else { return }
        let cropped = cropCGImage(cgImage, to: windowRect)
        let section = NSImage(cgImage: cropped, size: windowRect.size)

        if let stitched = stitchedImage {
            stitchedImage = appendImage(stitched, section)
        } else {
            stitchedImage = section
        }
        captureCount += 1
        counterLabel.stringValue = "已捕获: \(captureCount) 段"
        flashCaptureFeedback()
    }

    @objc private func finishCapture(_ sender: Any?) {
        onCapture?(stitchedImage)
    }

    @objc private func cancelCapture(_ sender: Any?) {
        onCancel?()
    }

    private func flashCaptureFeedback() {
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.6).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        }
    }

    private func appendImage(_ base: NSImage, _ new: NSImage) -> NSImage? {
        guard let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let newCG = new.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return base }

        let width = max(baseCG.width, newCG.width)
        let totalHeight = baseCG.height + newCG.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: baseCG.width, height: baseCG.height))
        ctx.draw(newCG, in: CGRect(x: 0, y: baseCG.height, width: newCG.width, height: newCG.height))

        guard let result = ctx.makeImage() else { return base }
        return NSImage(cgImage: result, size: NSSize(width: width, height: totalHeight))
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
