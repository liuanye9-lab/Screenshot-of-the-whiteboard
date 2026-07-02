// ScrollingOverlay.swift — 区域选择 + 自动滚动长图截图
// 流程：
//   1. 按 ⌘T → 弹出区域选择覆层（与局部截图相同，带放大镜 + 十字准线）
//   2. 用户框选要截图的范围 → 选区确定后关闭覆层
//   3. 屏幕顶部出现悬浮控制条，自动截取第一帧
//   4. 用户在选区范围内正常滚动页面
//   5. 滚动停下 0.5 秒后自动截取新帧，像素比对去重后拼接
//   6. 点「完成」或按 ↵ → 拼接结果直接进入标注白板
//   7. 按 Esc 取消
import AppKit
import CoreGraphics
import Carbon.HIToolbox

// MARK: - 滚动截图入口

class ScrollingCaptureManager {
    static let shared = ScrollingCaptureManager()
    private var currentOverlay: ScrollingOverlayWindow?

    func start(onComplete: @escaping (NSImage?) -> Void) {
        // 第一步：弹出区域选择覆层
        guard let screen = NSScreen.main else { onComplete(nil); return }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { onComplete(nil); return }
        guard let cgImage = CGDisplayCreateImage(displayID) else { onComplete(nil); return }

        let screenImage = NSImage(cgImage: cgImage, size: screen.frame.size)
        let screenFrame = screen.frame

        let captureOverlay = CaptureOverlayWindow(
            screenImage: screenImage,
            cgImage: cgImage,
            screenFrame: screenFrame
        ) { [weak self] selectedImage in
            // 区域选择完成或取消
            // 我们不需要 selectedImage，只需要选区的 CGRect
            // CaptureOverlayWindow 的回调返回的是 NSImage，我们需要修改获取选区的方式
            // 这里用一个变通方法：通过 captureOverlay 的 overlayView 获取选区
            onComplete(nil) // placeholder，实际逻辑在下面
        }

        // 重写回调：获取选区 rect 而非裁剪后的图片
        captureOverlay.overlayView.onSelectionComplete = { [weak self] rect in
            captureOverlay.orderOut(nil)

            guard let rect = rect, rect.width > 10, rect.height > 10 else {
                onComplete(nil)
                return
            }

            // 选区是 view 坐标（原点在左下），需要转换为全局 NSScreen 坐标
            let screenFrame = NSScreen.main?.frame ?? .zero
            let globalRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height
            )

            // 第二步：弹出滚动控制面板
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.currentOverlay?.orderOut(nil)
                self?.currentOverlay = ScrollingOverlayWindow(
                    windowRect: globalRect,
                    screenFrame: screenFrame
                ) { image in
                    self?.currentOverlay = nil
                    onComplete(image)
                }
            }
        }
    }
}

// MARK: - 滚动截图窗口

class ScrollingOverlayWindow: NSWindow {
    var onComplete: ((NSImage?) -> Void)?
    private let controlView: ScrollingControlView

    init(windowRect: CGRect, screenFrame: CGRect, callback: @escaping (NSImage?) -> Void) {
        self.onComplete = callback

        let controlW: CGFloat = 440
        let controlH: CGFloat = 92
        let x = screenFrame.midX - controlW / 2
        let y = screenFrame.maxY - controlH - 8

        self.controlView = ScrollingControlView(
            frame: NSRect(x: 0, y: 0, width: controlW, height: controlH),
            windowRect: windowRect,
            screenFrame: screenFrame
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
    private let screenFrame: CGRect
    private var stitchedImage: CGImage?
    private var lastFrame: CGImage?
    private var captureCount = 0
    private var isCapturing = false
    private var eventTap: CFMachPort?
    private var scrollSettleTimer: DispatchSourceTimer?
    private var scrollMonitorQueue = DispatchQueue(label: "snapleaf.scroll-monitor")

    // UI
    private lazy var statusLabel: NSTextField = {
        let l = NSTextField(labelWithString: "准备就绪 — 点击「开始」后滚动目标页面")
        l.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .white
        l.alignment = .center
        return l
    }()
    private lazy var hintLabel: NSTextField = {
        let l = NSTextField(labelWithString: "自动捕获滚动内容，智能去重拼接")
        l.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        l.textColor = NSColor.white.withAlphaComponent(0.6)
        l.alignment = .center
        return l
    }()
    private lazy var startButton: NSButton = makeButton(
        title: "开始", color: LeafStyle.primaryBlue, action: #selector(startCapture(_:)))
    private lazy var finishButton: NSButton = makeButton(
        title: "完成 (↵)", color: LeafStyle.systemGreen, action: #selector(finishCapture(_:)))
    private lazy var cancelButton: NSButton = makeButton(
        title: "取消 (Esc)", color: NSColor.systemGray, action: #selector(cancelCapture(_:)))

    init(frame: NSRect, windowRect: CGRect, screenFrame: CGRect) {
        self.targetRect = windowRect
        self.screenFrame = screenFrame
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - UI

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

        hintLabel.frame = NSRect(x: 0, y: 68, width: bounds.width, height: 16)
        addSubview(hintLabel)

        statusLabel.frame = NSRect(x: 0, y: 46, width: bounds.width, height: 20)
        addSubview(statusLabel)

        let btnY: CGFloat = 8
        let btnH: CGFloat = 30
        let btnW: CGFloat = 120
        let spacing: CGFloat = 12
        let totalW = btnW * 3 + spacing * 2
        let startX = (bounds.width - totalW) / 2

        startButton.frame = NSRect(x: startX, y: btnY, width: btnW, height: btnH)
        finishButton.frame = NSRect(x: startX + btnW + spacing, y: btnY, width: btnW, height: btnH)
        cancelButton.frame = NSRect(x: startX + (btnW + spacing) * 2, y: btnY, width: btnW, height: btnH)

        addSubview(startButton)
        addSubview(finishButton)
        addSubview(cancelButton)

        finishButton.isEnabled = false
    }

    private func makeButton(title: String, color: NSColor, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .rounded
        btn.title = title
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
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter):
            if isCapturing { finishCapture(nil) }
        case UInt32(kVK_Escape):
            cancelCapture(nil)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 截图核心：截取选区范围

    private func captureTargetArea() -> CGImage? {
        guard let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        guard let fullImage = CGDisplayCreateImage(displayID) else { return nil }

        let scale = CGFloat(fullImage.width) / screenFrame.width

        // targetRect 是 NSScreen 坐标（原点在左下），CGImage 坐标原点在左上
        let cropRect = CGRect(
            x: targetRect.origin.x * scale,
            y: (screenFrame.height - targetRect.origin.y - targetRect.height) * scale,
            width: targetRect.width * scale,
            height: targetRect.height * scale
        )
        return fullImage.cropping(to: cropRect) ?? fullImage
    }

    // MARK: - 开始自动捕获

    @objc private func startCapture(_ sender: Any?) {
        guard !isCapturing else { return }

        // 截取第一帧
        guard let firstFrame = captureTargetArea() else { return }
        stitchedImage = firstFrame
        lastFrame = firstFrame
        captureCount = 1
        isCapturing = true

        statusLabel.stringValue = "正在监听滚动… 滚动目标页面即可自动截取"
        hintLabel.stringValue = "已捕获 \(captureCount) 帧"
        startButton.isEnabled = false
        finishButton.isEnabled = true

        installScrollMonitor()
        flashFeedback()
    }

    // MARK: - 滚动事件监听

    private func installScrollMonitor() {
        let eventMask = (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
                if let refcon = refcon {
                    let view = Unmanaged<ScrollingControlView>.fromOpaque(refcon).takeUnretainedValue()
                    view.onScrollDetected()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // 权限不足，降级为手动模式
            statusLabel.stringValue = "无法监听滚动，请用 Space 手动截取每帧"
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func onScrollDetected() {
        scrollSettleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: scrollMonitorQueue)
        timer.schedule(deadline: .now() + 0.5)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.autoCaptureFrame()
            }
        }
        timer.resume()
        scrollSettleTimer = timer
    }

    private func autoCaptureFrame() {
        guard isCapturing else { return }

        guard let newFrame = captureTargetArea() else { return }
        guard let lastFrame = lastFrame else {
            appendFrame(newFrame)
            return
        }

        // 检测重叠区域
        let overlap = findOverlap(lastImage: lastFrame, newImage: newFrame)

        if overlap > 0 && overlap < newFrame.height {
            let newPartHeight = newFrame.height - overlap
            if newPartHeight > 5 {
                let cropRect = CGRect(x: 0, y: overlap, width: newFrame.width, height: newPartHeight)
                if let newPart = newFrame.cropping(to: cropRect) {
                    appendFrame(newPart)
                }
            }
        } else if overlap == 0 {
            appendFrame(newFrame)
        }
    }

    private func appendFrame(_ frame: CGImage) {
        if let existing = stitchedImage {
            stitchedImage = stitchCGImagesVertical(existing, frame)
        } else {
            stitchedImage = frame
        }
        lastFrame = captureTargetArea()
        captureCount += 1
        hintLabel.stringValue = "已捕获 \(captureCount) 帧"
        flashFeedback()
    }

    private func flashFeedback() {
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.4).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.80).cgColor
        }
    }

    // MARK: - 像素重叠检测

    private func findOverlap(lastImage: CGImage, newImage: CGImage) -> Int {
        let lastW = lastImage.width
        let lastH = lastImage.height
        let newW = newImage.width
        let newH = newImage.height

        guard lastW > 0 && lastH > 0 && newW > 0 && newH > 0 else { return -1 }
        if lastW != newW { return 0 }

        let sampleRowCount = min(20, lastH / 4)
        let sampleStep = max(1, lastW / 100)

        guard let lastData = getPixelData(lastImage),
              let newData = getPixelData(newImage) else { return -1 }

        var lastFingerprints: [[UInt32]] = []
        for row in 0..<sampleRowCount {
            let y = lastH - 1 - row
            var rowFP: [UInt32] = []
            for x in stride(from: 0, to: lastW, by: sampleStep) {
                let idx = (y * lastW + x)
                if idx < lastData.count {
                    rowFP.append(lastData[idx])
                }
            }
            lastFingerprints.append(rowFP)
        }

        let maxSearch = min(newH, lastH)
        let minMatchRows = 3

        for startY in 0..<maxSearch {
            var matchedRows = 0
            for row in 0..<sampleRowCount {
                let newY = startY + row
                if newY >= newH { break }

                var match = true
                var colIdx = 0
                for x in stride(from: 0, to: newW, by: sampleStep) {
                    let newIdx = (newY * newW + x)
                    if newIdx >= newData.count || colIdx >= lastFingerprints[row].count { break }
                    if newData[newIdx] != lastFingerprints[row][colIdx] {
                        match = false
                        break
                    }
                    colIdx += 1
                }
                if match { matchedRows += 1 }
            }

            if matchedRows >= minMatchRows {
                let overlap = newH - startY
                return max(0, overlap)
            }
        }

        return 0
    }

    private func getPixelData(_ image: CGImage) -> [UInt32]? {
        let w = image.width
        let h = image.height
        let bytesPerRow = w * 4
        var pixelData = [UInt32](repeating: 0, count: w * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixelData
    }

    // MARK: - CGImage 垂直拼接

    private func stitchCGImagesVertical(_ top: CGImage, _ bottom: CGImage) -> CGImage? {
        let width = max(top.width, bottom.width)
        let totalHeight = top.height + bottom.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return top }

        ctx.draw(top, in: CGRect(x: 0, y: bottom.height, width: top.width, height: top.height))
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height))

        return ctx.makeImage()
    }

    // MARK: - 完成 / 取消

    @objc private func finishCapture(_ sender: Any?) {
        stopScrollMonitor()
        isCapturing = false

        guard let result = stitchedImage else {
            onCancel?()
            return
        }
        let nsImage = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
        onFinish?(nsImage)
    }

    @objc private func cancelCapture(_ sender: Any?) {
        stopScrollMonitor()
        isCapturing = false
        onCancel?()
    }

    private func stopScrollMonitor() {
        scrollSettleTimer?.cancel()
        scrollSettleTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }
}
