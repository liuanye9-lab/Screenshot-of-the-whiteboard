// ScrollingOverlay.swift — 手动滚动长图控制面板
// 流程：
//   1. 按 ⌘T 触发长图截图
//   2. 屏幕顶部出现悬浮控制条（不遮挡目标页面）
//   3. 用户在目标页面正常滚动（鼠标滚轮/触控板）
//   4. 每滚动到新内容，按 Space 或点「截取当前段」捕获当前屏幕
//   5. 按 Enter 或点「完成」→ 拼接结果直接进入标注白板
//   6. 按 Esc 或点「取消」放弃
import AppKit
import CoreGraphics
import Carbon.HIToolbox

// MARK: - 滚动截图窗口

class ScrollingOverlayWindow: NSWindow {
    var onComplete: ((NSImage?) -> Void)?
    private let controlView: ScrollingControlView

    init(windowRect: CGRect, callback: @escaping (NSImage?) -> Void) {
        self.onComplete = callback

        let controlW: CGFloat = 400
        let controlH: CGFloat = 80
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - controlW / 2
        let y = screenFrame.maxY - controlH - 8

        self.controlView = ScrollingControlView(
            frame: NSRect(x: 0, y: 0, width: controlW, height: controlH),
            windowRect: windowRect
        )

        super.init(
            contentRect: NSRect(x: x, y: y, width: controlW, height: controlH),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = controlView

        controlView.onFinish = { [weak self] image in
            self?.onComplete?(image)
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

// MARK: - 控制视图

class ScrollingControlView: NSView {
    var onFinish: ((NSImage?) -> Void)?
    var onCancel: (() -> Void)?

    private let targetRect: CGRect
    private var stitchedImage: NSImage?
    private var captureCount = 0

    private lazy var captureButton: NSButton = makeButton(
        title: "截取当前段",
        subtitle: "Space",
        color: LeafStyle.primaryBlue,
        action: #selector(captureSection(_:))
    )
    private lazy var finishButton: NSButton = makeButton(
        title: "完成",
        subtitle: "↵",
        color: LeafStyle.systemGreen,
        action: #selector(finishCapture(_:))
    )
    private lazy var cancelButton: NSButton = makeButton(
        title: "取消",
        subtitle: "Esc",
        color: NSColor.systemGray,
        action: #selector(cancelCapture(_:))
    )
    private lazy var counterLabel: NSTextField = {
        let label = NSTextField(labelWithString: "已截取 0 段")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        return label
    }()
    private lazy var hintLabel: NSTextField = {
        let label = NSTextField(labelWithString: "滚动目标页面后点「截取当前段」")
        label.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.6)
        label.alignment = .center
        return label
    }()

    init(frame: NSRect, windowRect: CGRect) {
        self.targetRect = windowRect
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.80).cgColor
        layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .popover
        blur.state = .active
        blur.blendingMode = .withinWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.autoresizingMask = [.width, .height]
        addSubview(blur, positioned: .below, relativeTo: nil)

        hintLabel.frame = NSRect(x: 0, y: 58, width: bounds.width, height: 16)
        addSubview(hintLabel)

        counterLabel.frame = NSRect(x: 0, y: 38, width: bounds.width, height: 18)
        addSubview(counterLabel)

        let btnY: CGFloat = 6
        let btnH: CGFloat = 28
        let btnW: CGFloat = 110
        let spacing: CGFloat = 8
        let totalW = btnW * 3 + spacing * 2
        let startX = (bounds.width - totalW) / 2

        captureButton.frame = NSRect(x: startX, y: btnY, width: btnW, height: btnH)
        finishButton.frame = NSRect(x: startX + btnW + spacing, y: btnY, width: btnW, height: btnH)
        cancelButton.frame = NSRect(x: startX + (btnW + spacing) * 2, y: btnY, width: btnW, height: btnH)

        addSubview(captureButton)
        addSubview(finishButton)
        addSubview(cancelButton)
    }

    private func makeButton(title: String, subtitle: String, color: NSColor, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .rounded
        btn.title = "\(title) (\(subtitle))"
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.cgColor
        btn.layer?.cornerRadius = 8
        btn.contentTintColor = .white
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

    // MARK: - 截取当前段

    @objc private func captureSection(_ sender: Any?) {
        // 截取整个主屏幕
        guard let screen = NSScreen.main else { return }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
        guard let fullImage = CGDisplayCreateImage(displayID) else { return }

        // 计算物理像素与逻辑像素的比例
        let scale = CGFloat(fullImage.width) / screen.frame.width

        // targetRect 是全局坐标（NSScreen 坐标系，原点在左下）
        // CGImage 坐标原点在左上，需要 Y 翻转
        let cropRect = CGRect(
            x: targetRect.origin.x * scale,
            y: (screen.frame.height - targetRect.origin.y - targetRect.height) * scale,
            width: targetRect.width * scale,
            height: targetRect.height * scale
        )

        guard let cropped = fullImage.cropping(to: cropRect) else {
            // 如果裁剪失败，用整张图
            let fullNSImage = NSImage(cgImage: fullImage, size: screen.frame.size)
            appendSection(fullNSImage, cgImage: fullImage)
            return
        }

        let sectionImage = NSImage(cgImage: cropped, size: targetRect.size)
        appendSection(sectionImage, cgImage: cropped)
    }

    private func appendSection(_ image: NSImage, cgImage: CGImage) {
        if let existing = stitchedImage {
            stitchedImage = stitchVertical(existing, image)
        } else {
            stitchedImage = image
        }
        captureCount += 1
        counterLabel.stringValue = "已截取 \(captureCount) 段"
        flashFeedback()
    }

    private func flashFeedback() {
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.5).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.80).cgColor
        }
    }

    // MARK: - 完成 / 取消

    @objc private func finishCapture(_ sender: Any?) {
        guard let result = stitchedImage else {
            // 没截取任何内容，取消
            onCancel?()
            return
        }
        onFinish?(result)
    }

    @objc private func cancelCapture(_ sender: Any?) {
        onCancel?()
    }

    // MARK: - 垂直拼接

    private func stitchVertical(_ top: NSImage, _ bottom: NSImage) -> NSImage {
        guard let topCG = top.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bottomCG = bottom.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return top
        }

        let width = max(topCG.width, bottomCG.width)
        let totalHeight = topCG.height + bottomCG.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return top }

        // top 画在上半部分
        ctx.draw(topCG, in: CGRect(x: 0, y: bottomCG.height, width: topCG.width, height: topCG.height))
        // bottom 画在下半部分
        ctx.draw(bottomCG, in: CGRect(x: 0, y: 0, width: bottomCG.width, height: bottomCG.height))

        guard let result = ctx.makeImage() else { return top }
        return NSImage(cgImage: result, size: NSSize(width: width, height: totalHeight))
    }
}
