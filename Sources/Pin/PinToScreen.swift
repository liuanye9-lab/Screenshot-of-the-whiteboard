// PinToScreen.swift — 截图置顶贴图：浮动窗口 + 拖拽/缩放/透明度/保存
import AppKit
import Carbon.HIToolbox

class PinToScreenManager {
    static let shared = PinToScreenManager()
    private var pinnedWindows: [PinnedScreenshotWindow] = []

    /// 将截图钉到屏幕最上层
    func pin(image: NSImage, at position: CGPoint? = nil, opacity: Double = 1.0) {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let imgSize = image.size
        let maxW = screen.width * 0.4
        let maxH = screen.height * 0.4
        let scale = min(maxW / imgSize.width, maxH / imgSize.height, 1.0)
        let w = imgSize.width * scale
        let h = imgSize.height * scale

        let x = position?.x ?? (screen.midX - w / 2)
        let y = position?.y ?? (screen.midY - h / 2)
        let frame = NSRect(x: x, y: y, width: w + 8, height: h + 8)

        let win = PinnedScreenshotWindow(contentRect: frame, image: image, opacity: opacity)
        win.onClose = { [weak self, weak win] in
            guard let self = self, let win = win else { return }
            self.pinnedWindows.removeAll { $0 === win }
        }
        win.makeKeyAndOrderFront(nil)
        pinnedWindows.append(win)
    }

    /// 关闭所有置顶贴图
    func closeAll() {
        pinnedWindows.forEach { $0.close() }
        pinnedWindows.removeAll()
    }
}

// MARK: - 置顶截图窗口

class PinnedScreenshotWindow: NSPanel {
    private let imageView: PinnedImageView
    private let image: NSImage
    private let naturalSize: NSSize
    private let fitScale: CGFloat
    private var currentScale: CGFloat = 1.0
    var onClose: (() -> Void)?

    init(contentRect: NSRect, image: NSImage, opacity: Double = 1.0) {
        self.image = image
        self.naturalSize = image.size
        self.fitScale = min((contentRect.width - 8) / max(1, image.size.width),
                            (contentRect.height - 8) / max(1, image.size.height))
        self.currentScale = self.fitScale
        self.imageView = PinnedImageView(frame: NSRect(origin: .zero, size: contentRect.size), image: image)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.alphaValue = opacity

        let container = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.alphaValue = opacity
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        imageView.frame = NSRect(x: 4, y: 4, width: container.bounds.width - 8, height: container.bounds.height - 8)
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        let controlBar = PinnedControlBar(frame: NSRect(x: container.bounds.width - 130, y: container.bounds.height - 34, width: 120, height: 28))
        controlBar.autoresizingMask = [.minXMargin, .maxYMargin]
        controlBar.initialOpacity = opacity
        controlBar.onClose = { [weak self] in
            self?.close()
            self?.onClose?()
        }
        controlBar.onOpacityChange = { [weak self, weak blur] opacity in
            blur?.alphaValue = opacity
            self?.alphaValue = opacity
        }
        container.addSubview(controlBar)

        self.contentView = container
        self.minSize = NSSize(width: 80, height: 80)

        setupImageViewCallbacks()
    }

    private func setupImageViewCallbacks() {
        imageView.onScaleChange = { [weak self] scale in
            self?.resizeTo(scale: scale)
        }
        imageView.onToggleOriginalSize = { [weak self] in
            self?.toggleOriginalOrFit()
        }
        imageView.onSave = { [weak self] in
            self?.saveImage()
        }
        imageView.onClose = { [weak self] in
            self?.close()
            self?.onClose?()
        }
    }

    private func toggleOriginalOrFit() {
        let target: CGFloat = (currentScale < 0.95) ? 1.0 : fitScale
        resizeTo(scale: target)
    }

    private func resizeTo(scale: CGFloat) {
        currentScale = max(0.1, min(5.0, scale))
        let targetSize = NSSize(width: naturalSize.width * currentScale + 8,
                                height: naturalSize.height * currentScale + 8)
        guard let screen = self.screen?.frame ?? NSScreen.main?.frame else { return }
        let newSize = NSSize(width: min(targetSize.width, screen.width * 0.95),
                             height: min(targetSize.height, screen.height * 0.95))
        let currentCenter = CGPoint(x: frame.midX, y: frame.midY)
        var newFrame = NSRect(x: currentCenter.x - newSize.width / 2,
                              y: currentCenter.y - newSize.height / 2,
                              width: newSize.width, height: newSize.height)
        newFrame = keepWithinScreen(newFrame, screen: screen)
        setFrame(newFrame, display: true, animate: true)
    }

    private func keepWithinScreen(_ rect: NSRect, screen: NSRect) -> NSRect {
        var r = rect
        if r.maxX > screen.maxX { r.origin.x = screen.maxX - r.width }
        if r.minX < screen.minX { r.origin.x = screen.minX }
        if r.maxY > screen.maxY { r.origin.y = screen.maxY - r.height }
        if r.minY < screen.minY { r.origin.y = screen.minY }
        return r
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "snapleaf_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).png"
        panel.directoryURL = SettingsManager.shared.settings.effectiveSaveDirectory
        panel.begin { [weak self] result in
            guard let self = self, result == .OK, let url = panel.url else { return }
            guard let tiff = self.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
            if let s = NSScreen.main { ToastWindow(message: "已保存", screen: s).show() }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 图片视图

class PinnedImageView: NSView {
    private let image: NSImage
    private var currentScale: CGFloat = 1.0

    var onScaleChange: ((CGFloat) -> Void)?
    var onToggleOriginalSize: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let imgRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        image.draw(in: imgRect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onToggleOriginalSize?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "保存...", action: #selector(saveImage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "复制", action: #selector(copyImage(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "关闭", action: #selector(closeWindow(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY / 100.0
        currentScale = max(0.1, min(5.0, currentScale + delta))
        onScaleChange?(currentScale)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_ANSI_W && event.modifierFlags.contains(.command) {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc private func saveImage(_ sender: Any?) { onSave?() }
    @objc private func copyImage(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
    @objc private func closeWindow(_ sender: Any?) { onClose?() }
}

// MARK: - 控制栏（透明度滑条 + 关闭）

class PinnedControlBar: NSView {
    var onClose: (() -> Void)?
    var onOpacityChange: ((CGFloat) -> Void)?
    var initialOpacity: Double = 1.0

    private var slider: NSSlider!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor

        slider = NSSlider(value: initialOpacity, minValue: 0.3, maxValue: 1.0, target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 8, y: 6, width: 72, height: 16)
        addSubview(slider)

        let closeBtn = NSButton(frame: NSRect(x: 86, y: 2, width: 28, height: 24))
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        if let xIcon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            closeBtn.image = xIcon.withSymbolConfiguration(config)
        }
        closeBtn.contentTintColor = .white
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        addSubview(closeBtn)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        slider.doubleValue = initialOpacity
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onOpacityChange?(CGFloat(sender.doubleValue))
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
