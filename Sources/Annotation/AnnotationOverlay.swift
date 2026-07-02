// AnnotationOverlay.swift — 标注覆层主窗口（支持缩放 / 平移 / 撤销重做 / 磁吸辅助线 / AI 导出）
import AppKit
import Carbon.HIToolbox

// MARK: - 主窗口

class AnnotationOverlayWindow: NSWindow {
    private let annotationView: AnnotationCanvas
    private let floatingToolbar: AnnotationToolbar

    init(image: NSImage, originalFrame: CGRect? = nil) {
        let screen = NSScreen.main!.frame
        self.annotationView = AnnotationCanvas(frame: screen, image: image, originalFrame: originalFrame)
        self.floatingToolbar = AnnotationToolbar(frame: NSRect(x: 0, y: 0, width: 0, height: LeafStyle.toolbarHeight))

        super.init(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        floatingToolbar.onToolSelect = { [weak self] tool in
            self?.handleToolAction(tool)
        }
        floatingToolbar.onColorSelect = { [weak self] color in
            self?.annotationView.currentColor = color
        }
        floatingToolbar.onStrokeWidthChange = { [weak self] width in
            self?.annotationView.currentStrokeWidth = width
        }
        floatingToolbar.onZoomReset = { [weak self] in
            self?.annotationView.resetZoom()
        }

        self.contentView = annotationView
        annotationView.addSubview(floatingToolbar)
        annotationView.toolbar = floatingToolbar

        layoutToolbar()
        floatingToolbar.selectTool(annotationView.currentTool)
        floatingToolbar.setColor(annotationView.currentColor)
        floatingToolbar.setStrokeWidth(annotationView.currentStrokeWidth)

        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func layoutToolbar() {
        let toolbarW = floatingToolbar.contentWidth
        let x = (frame.width - toolbarW) / 2
        let y: CGFloat = 32
        floatingToolbar.frame = NSRect(x: x, y: y, width: toolbarW, height: LeafStyle.toolbarHeight)
    }

    private func handleToolAction(_ tool: AnnotationTool) {
        switch tool {
        case .undo: annotationView.undo()
        case .redo: annotationView.redo()
        case .done: completeAnnotation()
        case .cancel: orderOut(nil)
        default: annotationView.currentTool = tool
        }
        floatingToolbar.selectTool(annotationView.currentTool)
    }

    private func completeAnnotation() {
        let result = annotationView.composeFinalImage()
        AnnotationOverlayWindow.copyToClipboard(result)
        close()
    }

    private func copyWithMetadata() {
        let (image, json) = annotationView.aiExportData()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pb.setString(json, forType: .string)
        if let screen = NSScreen.main {
            ToastWindow(message: "已复制图片 + JSON 元数据", screen: screen).show()
        }
    }

    private func saveWithMetadata() {
        let (image, json) = annotationView.aiExportData()
        let dir = SettingsManager.shared.settings.effectiveSaveDirectory
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let base = "snapleaf_\(timestamp)"
        let pngURL = dir.appendingPathComponent("\(base).png")
        let jsonURL = dir.appendingPathComponent("\(base).json")

        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: pngURL)
        }
        try? json.write(to: jsonURL, atomically: true, encoding: .utf8)
        if let screen = NSScreen.main {
            ToastWindow(message: "已保存 PNG + JSON", screen: screen).show()
        }
    }

    static func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        if let screen = NSScreen.main {
            ToastWindow(message: "已复制到剪贴板", screen: screen).show()
        }
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags
        switch UInt32(event.keyCode) {
        case UInt32(kVK_Escape):
            close()
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter):
            completeAnnotation()
        case UInt32(kVK_ANSI_C):
            if mods.contains(.command) && mods.contains(.shift) {
                copyWithMetadata()
            }
        case UInt32(kVK_ANSI_S):
            if mods.contains(.command) { saveWithMetadata() }
        case UInt32(kVK_Delete):
            annotationView.deleteSelected()
        case UInt32(kVK_ANSI_Z):
            if mods.contains(.command) {
                if mods.contains(.shift) { annotationView.redo() } else { annotationView.undo() }
            }
        case UInt32(kVK_ANSI_1): handleToolAction(.rect)
        case UInt32(kVK_ANSI_2): handleToolAction(.arrow)
        case UInt32(kVK_ANSI_3): handleToolAction(.text)
        case UInt32(kVK_ANSI_4): handleToolAction(.brush)
        case UInt32(kVK_ANSI_5): handleToolAction(.mosaic)
        case UInt32(kVK_ANSI_6): handleToolAction(.highlight)
        case UInt32(kVK_ANSI_7): handleToolAction(.sequence)
        case UInt32(kVK_ANSI_0):
            if mods.contains(.command) { annotationView.resetZoom() }
        case UInt32(kVK_Space):
            annotationView.setSpacePressed(true)
        default:
            super.keyDown(with: event)
        }
        floatingToolbar.selectTool(annotationView.currentTool)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == kVK_Space {
            annotationView.setSpacePressed(false)
        }
        super.keyUp(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - 标注画布

class AnnotationCanvas: NSView {
    private let sourceImage: NSImage
    private let sourceCGImage: CGImage?
    private let imageFrame: CGRect

    private var elements: [AnnotationElement] = []
    private var undoStack: [[AnnotationElement]] = []
    private var redoStack: [[AnnotationElement]] = []

    var currentTool: AnnotationTool = .rect {
        didSet { needsDisplay = true }
    }
    var currentColor: NSColor = LeafStyle.systemRed
    var currentStrokeWidth: CGFloat = LeafStyle.strokeWidth
    weak var toolbar: AnnotationToolbar?

    private var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var spacePressed: Bool = false

    private var selectedID: UUID?
    private var dragMode: DragMode = .none
    private var dragStart: CGPoint = .zero
    private var dragStartImage: CGPoint = .zero
    private var selectedElementAtStart: AnnotationElement?
    private var currentBrushPoints: [CGPoint]?
    private var currentDragImagePoint: CGPoint?
    private var guideLines: [GuideLine] = []

    private var editingTextField: NSTextField?
    private var editingExistingID: UUID?
    private var editingTextAnchor: CGPoint?

    private enum DragMode {
        case none, create, move, pan, resize
    }

    private struct GuideLine {
        let start: CGPoint
        let end: CGPoint
        var isVertical: Bool { abs(start.x - end.x) < 0.1 }
        var isHorizontal: Bool { abs(start.y - end.y) < 0.1 }
    }

    init(frame: NSRect, image: NSImage, originalFrame: CGRect?) {
        self.sourceImage = image
        self.sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let of = originalFrame {
            self.imageFrame = of
        } else {
            let imgSize = image.size
            let screen = NSScreen.main!.frame
            let scale = min(screen.width * 0.8 / imgSize.width, screen.height * 0.8 / imgSize.height, 1.0)
            let w = imgSize.width * scale
            let h = imgSize.height * scale
            self.imageFrame = CGRect(x: (screen.width - w) / 2, y: (screen.height - h) / 2, width: w, height: h)
        }
        super.init(frame: frame)
        self.currentStrokeWidth = SettingsManager.shared.settings.defaultStrokeWidth
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - 坐标转换
    private var viewOrigin: CGPoint {
        CGPoint(x: imageFrame.origin.x + panOffset.x, y: imageFrame.origin.y + panOffset.y)
    }

    private func viewToImage(_ point: CGPoint) -> CGPoint {
        let o = viewOrigin
        return CGPoint(x: (point.x - o.x) / zoomScale, y: (point.y - o.y) / zoomScale)
    }

    private func imageToView(_ point: CGPoint) -> CGPoint {
        let o = viewOrigin
        return CGPoint(x: point.x * zoomScale + o.x, y: point.y * zoomScale + o.y)
    }

    private func imageRectToView(_ rect: CGRect) -> CGRect {
        let o = viewOrigin
        return CGRect(x: rect.origin.x * zoomScale + o.x,
                      y: rect.origin.y * zoomScale + o.y,
                      width: rect.width * zoomScale,
                      height: rect.height * zoomScale)
    }

    // MARK: - 缩放 / 平移
    func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
        needsDisplay = true
    }

    func setSpacePressed(_ pressed: Bool) {
        spacePressed = pressed
        if pressed { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
    }

    private func zoom(at viewPoint: CGPoint, delta: CGFloat) {
        let oldScale = zoomScale
        let newScale = max(0.2, min(5.0, zoomScale + delta))
        if newScale == oldScale { return }
        let p = viewToImage(viewPoint)
        panOffset.x += p.x * (oldScale - newScale)
        panOffset.y += p.y * (oldScale - newScale)
        zoomScale = newScale
        needsDisplay = true
    }

    // MARK: - 绘制
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.set()

        let t = NSAffineTransform()
        let o = viewOrigin
        t.translateX(by: o.x, yBy: o.y)
        t.scale(by: zoomScale)
        t.concat()

        sourceImage.draw(in: CGRect(origin: .zero, size: imageFrame.size),
                         from: NSRect(origin: .zero, size: sourceImage.size),
                         operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        t.concat()
        for element in elements {
            drawElement(element)
        }
        if dragMode == .create, let current = currentDragImagePoint {
            drawPreview(from: dragStartImage, to: current)
        }
        drawSelectionBox()
        drawGuideLines()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawElement(_ element: AnnotationElement) {
        switch element.kind {
        case .rect:
            guard element.frame != .zero else { return }
            element.color.setStroke()
            let path = NSBezierPath(rect: element.frame)
            path.lineWidth = element.strokeWidth
            path.stroke()
            element.color.withAlphaComponent(0.08).setFill()
            path.fill()
        case .arrow:
            guard element.points.count == 2 else { return }
            drawArrow(from: element.points[0], to: element.points[1], color: element.color, strokeWidth: element.strokeWidth)
        case .text:
            guard element.frame != .zero else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: element.fontSize, weight: .semibold),
                .foregroundColor: element.color
            ]
            element.text.draw(in: element.frame, withAttributes: attrs)
        case .brush:
            guard element.points.count > 1 else { return }
            element.color.setStroke()
            let path = NSBezierPath()
            path.move(to: element.points[0])
            for p in element.points.dropFirst() { path.line(to: p) }
            path.lineWidth = element.strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .mosaic:
            guard element.frame != .zero, let cgImg = sourceCGImage else { return }
            let scaleToSource = CGFloat(cgImg.width) / imageFrame.width
            drawMosaic(in: element.frame, sourceImage: cgImg, scaleToSource: scaleToSource)
        case .highlight:
            guard element.frame != .zero else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .multiply
            element.color.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: element.frame, xRadius: 4, yRadius: 4).fill()
            NSGraphicsContext.restoreGraphicsState()
        case .sequence:
            guard let point = element.points.first else { return }
            let size: CGFloat = 28
            let circle = NSRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
            let path = NSBezierPath(ovalIn: circle)
            element.color.setFill()
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let text = "\(element.sequenceIndex)"
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: point.x - textSize.width/2, y: point.y - textSize.height/2 - 1), withAttributes: attrs)
        }
    }

    private func drawPreview(from: CGPoint, to: CGPoint) {
        currentColor.withAlphaComponent(0.5).setStroke()
        switch currentTool {
        case .rect:
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
            NSBezierPath(rect: rect).stroke()
        case .arrow:
            drawArrow(from: from, to: to, color: currentColor.withAlphaComponent(0.5), strokeWidth: currentStrokeWidth)
        case .highlight:
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .multiply
            currentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            NSGraphicsContext.restoreGraphicsState()
        case .brush:
            guard let pts = currentBrushPoints, pts.count > 1 else { return }
            currentColor.setStroke()
            let path = NSBezierPath()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.line(to: p) }
            path.lineWidth = currentStrokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        default:
            break
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, color: NSColor, strokeWidth: CGFloat) {
        color.setStroke()
        let line = NSBezierPath()
        line.move(to: from)
        line.line(to: to)
        line.lineWidth = strokeWidth
        line.lineCapStyle = .round
        line.stroke()
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLen = max(6, LeafStyle.arrowSize * (strokeWidth / 2.5))
        let head1 = CGPoint(x: to.x - headLen * cos(angle - .pi / 6), y: to.y - headLen * sin(angle - .pi / 6))
        let head2 = CGPoint(x: to.x - headLen * cos(angle + .pi / 6), y: to.y - headLen * sin(angle + .pi / 6))
        let head = NSBezierPath()
        head.move(to: to); head.line(to: head1); head.line(to: head2); head.close()
        color.setFill()
        head.fill()
    }

    private func drawMosaic(in rect: CGRect, sourceImage cgImg: CGImage, scaleToSource: CGFloat) {
        let blockSize: CGFloat = max(2, 8 * scaleToSource)
        let cols = max(1, Int(rect.width / blockSize))
        let rows = max(1, Int(rect.height / blockSize))
        NSGraphicsContext.saveGraphicsState()
        for row in 0..<rows {
            for col in 0..<cols {
                let px = Int(rect.origin.x * scaleToSource + CGFloat(col) * blockSize + blockSize/2)
                let py = Int(rect.origin.y * scaleToSource + CGFloat(row) * blockSize + blockSize/2)
                if px >= 0 && px < cgImg.width && py >= 0 && py < cgImg.height {
                    if let pixel = cgImg.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)) {
                        let nsImg = NSImage(cgImage: pixel, size: NSSize(width: 1, height: 1))
                        nsImg.draw(in: NSRect(x: rect.origin.x + CGFloat(col) * blockSize, y: rect.origin.y + CGFloat(row) * blockSize, width: blockSize, height: blockSize))
                    }
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectionBox() {
        guard let id = selectedID, let el = element(id: id), dragMode != .create else { return }
        let rect = el.boundingRect
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.lineWidth = 1 / zoomScale
        path.stroke()
    }

    private func drawGuideLines() {
        guard !guideLines.isEmpty else { return }
        NSColor.white.setStroke()
        let path = NSBezierPath()
        for line in guideLines {
            path.move(to: line.start)
            path.line(to: line.end)
        }
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.lineWidth = 0.5 / zoomScale
        path.stroke()
    }

    // MARK: - 鼠标事件
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = viewToImage(point)

        if spacePressed {
            dragMode = .pan
            dragStart = point
            NSCursor.closedHand.set()
            return
        }

        switch currentTool {
        case .select:
            if event.clickCount == 2, let id = elementAt(imagePoint), let el = element(id: id), el.kind == .text {
                editTextElement(el)
                return
            }
            if let id = elementAt(imagePoint) {
                selectedID = id
                selectedElementAtStart = element(id: id)
                saveState()
                dragMode = .move
                dragStart = point
                dragStartImage = imagePoint
            } else {
                selectedID = nil
                dragMode = .pan
                dragStart = point
            }
        case .text:
            selectedID = nil
            startTextInput(at: imagePoint)
        case .sequence:
            selectedID = nil
            addElement(AnnotationElement(id: UUID(), kind: .sequence, points: [imagePoint], color: currentColor, sequenceIndex: nextSequenceIndex()))
        case .brush:
            selectedID = nil
            currentBrushPoints = [imagePoint]
            dragMode = .create
            dragStart = point
            dragStartImage = imagePoint
        case .rect, .arrow, .mosaic, .highlight:
            selectedID = nil
            dragMode = .create
            dragStart = point
            dragStartImage = imagePoint
        default:
            break
        }
        currentDragImagePoint = imagePoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = viewToImage(point)
        currentDragImagePoint = imagePoint

        switch dragMode {
        case .pan:
            let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
            panOffset.x += delta.x
            panOffset.y += delta.y
            dragStart = point
            needsDisplay = true
        case .move:
            guard let id = selectedID, let startEl = selectedElementAtStart else { return }
            let delta = CGSize(width: imagePoint.x - dragStartImage.x, height: imagePoint.y - dragStartImage.y)
            let moved = startEl.translated(by: delta)
            let (snapped, guides) = snap(moved, selectedID: id)
            guideLines = guides
            updateElement(snapped)
            needsDisplay = true
        case .create:
            if currentTool == .brush {
                currentBrushPoints?.append(imagePoint)
            }
            needsDisplay = true
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = viewToImage(point)
        currentDragImagePoint = imagePoint

        switch dragMode {
        case .create:
            if currentTool == .brush {
                if let pts = currentBrushPoints, pts.count > 1 {
                    addElement(AnnotationElement(id: UUID(), kind: .brush, points: pts, color: currentColor, strokeWidth: currentStrokeWidth))
                }
                currentBrushPoints = nil
            } else if currentTool == .rect || currentTool == .highlight {
                let rect = CGRect(x: min(dragStartImage.x, imagePoint.x), y: min(dragStartImage.y, imagePoint.y),
                                  width: abs(imagePoint.x - dragStartImage.x), height: abs(imagePoint.y - dragStartImage.y))
                if rect.width > 3 && rect.height > 3 {
                    addElement(AnnotationElement(id: UUID(), kind: currentTool == .highlight ? .highlight : .rect, frame: rect, color: currentColor, strokeWidth: currentStrokeWidth))
                }
            } else if currentTool == .mosaic {
                let rect = CGRect(x: min(dragStartImage.x, imagePoint.x), y: min(dragStartImage.y, imagePoint.y),
                                  width: abs(imagePoint.x - dragStartImage.x), height: abs(imagePoint.y - dragStartImage.y))
                if rect.width > 3 && rect.height > 3, sourceCGImage != nil {
                    addElement(AnnotationElement(id: UUID(), kind: .mosaic, frame: rect, color: currentColor, image: sourceCGImage))
                }
            } else if currentTool == .arrow {
                if hypot(imagePoint.x - dragStartImage.x, imagePoint.y - dragStartImage.y) > 5 {
                    addElement(AnnotationElement(id: UUID(), kind: .arrow, points: [dragStartImage, imagePoint], color: currentColor, strokeWidth: currentStrokeWidth))
                }
            }
        case .move:
            guideLines = []
            selectedElementAtStart = nil
        case .pan:
            if spacePressed { NSCursor.openHand.set() }
        default:
            break
        }
        dragMode = .none
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY / 100.0
            zoom(at: convert(event.locationInWindow, from: nil), delta: delta)
        } else {
            super.scrollWheel(with: event)
        }
    }

    // MARK: - 元素管理
    private func addElement(_ element: AnnotationElement) {
        saveState()
        elements.append(element)
        selectedID = element.kind == .text ? nil : element.id
        needsDisplay = true
    }

    private func updateElement(_ element: AnnotationElement) {
        if let idx = elements.firstIndex(where: { $0.id == element.id }) {
            elements[idx] = element
        }
    }

    private func element(id: UUID) -> AnnotationElement? {
        elements.first { $0.id == id }
    }

    private func elementAt(_ point: CGPoint) -> UUID? {
        for element in elements.reversed() {
            if hitTest(element, point: point) { return element.id }
        }
        return nil
    }

    private func hitTest(_ element: AnnotationElement, point: CGPoint) -> Bool {
        switch element.kind {
        case .rect, .highlight, .mosaic, .text:
            return element.boundingRect.insetBy(dx: -4, dy: -4).contains(point)
        case .arrow:
            guard element.points.count == 2 else { return false }
            return point.distance(toSegment: element.points[0], element.points[1]) < 10
        case .brush:
            return element.points.distance(from: point) < 8
        case .sequence:
            guard let p = element.points.first else { return false }
            return p.distance(to: point) < 16
        }
    }

    private func nextSequenceIndex() -> Int {
        (elements.filter { $0.kind == .sequence }.map { $0.sequenceIndex }.max() ?? 0) + 1
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        saveState()
        elements.removeAll { $0.id == id }
        selectedID = nil
        needsDisplay = true
    }

    // MARK: - 撤销 / 重做
    private func saveState() {
        undoStack.append(elements)
        redoStack.removeAll()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = last
        selectedID = nil
        guideLines = []
        needsDisplay = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = next
        selectedID = nil
        guideLines = []
        needsDisplay = true
    }

    // MARK: - 磁吸辅助线
    private func snap(_ element: AnnotationElement, selectedID: UUID) -> (AnnotationElement, [GuideLine]) {
        var candidate = element
        let threshold: CGFloat = 6 / zoomScale
        var xSnap: CGFloat?
        var ySnap: CGFloat?
        var guides: [GuideLine] = []

        let imageXs: [CGFloat] = [0, imageFrame.width / 2, imageFrame.width]
        let imageYs: [CGFloat] = [0, imageFrame.height / 2, imageFrame.height]

        var refXs = imageXs
        var refYs = imageYs
        for el in elements where el.id != selectedID {
            let r = el.boundingRect
            refXs.append(contentsOf: [r.minX, r.midX, r.maxX])
            refYs.append(contentsOf: [r.minY, r.midY, r.maxY])
            for p in el.points {
                refXs.append(p.x)
                refYs.append(p.y)
            }
        }

        let cRect = candidate.boundingRect
        let cXs = [cRect.minX, cRect.midX, cRect.maxX]
        let cYs = [cRect.minY, cRect.midY, cRect.maxY]

        for cx in cXs {
            for rx in refXs {
                if abs(cx - rx) < threshold {
                    let offset = rx - cx
                    if xSnap == nil || abs(offset) < abs(xSnap!) {
                        xSnap = offset
                        guides.removeAll { !$0.isVertical }
                        guides.append(GuideLine(start: CGPoint(x: rx, y: 0), end: CGPoint(x: rx, y: imageFrame.height)))
                    }
                }
            }
        }

        for cy in cYs {
            for ry in refYs {
                if abs(cy - ry) < threshold {
                    let offset = ry - cy
                    if ySnap == nil || abs(offset) < abs(ySnap!) {
                        ySnap = offset
                        guides.removeAll { !$0.isHorizontal }
                        guides.append(GuideLine(start: CGPoint(x: 0, y: ry), end: CGPoint(x: imageFrame.width, y: ry)))
                    }
                }
            }
        }

        if let dx = xSnap { candidate.translate(by: CGSize(width: dx, height: 0)) }
        if let dy = ySnap { candidate.translate(by: CGSize(width: 0, height: dy)) }
        return (candidate, guides)
    }

    // MARK: - AI 导出
    func aiExportData() -> (image: NSImage, json: String) {
        let image = composeFinalImage()
        var elementsJSON: [[String: Any]] = []
        for element in elements {
            var dict: [String: Any] = [
                "id": element.id.uuidString,
                "kind": "\(element.kind)",
                "color": element.color.hexString,
                "strokeWidth": element.strokeWidth
            ]
            switch element.kind {
            case .rect, .highlight, .mosaic, .text:
                dict["rect"] = [
                    "x": element.frame.origin.x,
                    "y": element.frame.origin.y,
                    "width": element.frame.width,
                    "height": element.frame.height
                ]
            case .arrow, .brush:
                dict["points"] = element.points.map { ["x": $0.x, "y": $0.y] }
            case .sequence:
                if let p = element.points.first {
                    dict["point"] = ["x": p.x, "y": p.y]
                }
                dict["index"] = element.sequenceIndex
            }
            if element.kind == .text {
                dict["text"] = element.text
                dict["fontSize"] = element.fontSize
            }
            elementsJSON.append(dict)
        }
        let payload: [String: Any] = [
            "version": "1.1.0",
            "imageSize": ["width": sourceImage.size.width, "height": sourceImage.size.height],
            "canvasSize": ["width": imageFrame.width, "height": imageFrame.height],
            "elements": elementsJSON
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return (image, json)
    }

    // MARK: - 文字输入
    private func startTextInput(at imagePoint: CGPoint) {
        guard editingTextField == nil else { return }
        editingExistingID = nil
        editingTextAnchor = imagePoint
        let viewRect = imageRectToView(CGRect(x: imagePoint.x, y: imagePoint.y - 14, width: 200, height: 28))
        let field = CommitOnEnterTextField(frame: viewRect)
        field.font = NSFont.systemFont(ofSize: 16 * zoomScale, weight: .semibold)
        field.textColor = currentColor
        field.backgroundColor = .clear
        field.isBordered = false
        field.isEditable = true
        field.placeholderString = "输入文字..."
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        editingTextField = field
        field.onCommit = { [weak self] text in
            self?.commitTextEditing(text: text, existingID: nil)
        }
        field.onCancel = { [weak self] in
            self?.cancelTextEditing()
        }
    }

    private func editTextElement(_ element: AnnotationElement) {
        guard element.kind == .text, element.frame != .zero else { return }
        cancelTextEditing()
        editingExistingID = element.id
        editingTextAnchor = element.frame.origin
        let viewRect = imageRectToView(element.frame)
        let field = CommitOnEnterTextField(frame: viewRect)
        field.font = NSFont.systemFont(ofSize: element.fontSize * zoomScale, weight: .semibold)
        field.textColor = element.color
        field.backgroundColor = .clear
        field.isBordered = false
        field.isEditable = true
        field.stringValue = element.text
        field.placeholderString = "输入文字..."
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        editingTextField = field
        field.onCommit = { [weak self] text in
            self?.commitTextEditing(text: text, existingID: element.id)
        }
        field.onCancel = { [weak self] in
            self?.cancelTextEditing()
        }
    }

    private func commitTextEditing(text: String, existingID: UUID?) {
        guard !text.isEmpty else { cancelTextEditing(); return }
        if let id = existingID, let idx = elements.firstIndex(where: { $0.id == id }) {
            var el = elements[idx]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: el.fontSize, weight: .semibold),
                .foregroundColor: el.color
            ]
            let size = text.size(withAttributes: attrs)
            el.frame = CGRect(x: el.frame.origin.x, y: el.frame.origin.y, width: max(size.width + 4, 60), height: max(size.height + 4, 24))
            el.text = text
            saveState()
            elements[idx] = el
        } else if let anchor = editingTextAnchor {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: currentColor
            ]
            let size = text.size(withAttributes: attrs)
            let frame = CGRect(x: anchor.x, y: anchor.y - size.height / 2, width: max(size.width + 4, 60), height: max(size.height + 4, 24))
            addElement(AnnotationElement(id: UUID(), kind: .text, frame: frame, color: currentColor, text: text, fontSize: 16))
        }
        cancelTextEditing()
    }

    private func cancelTextEditing() {
        editingTextField?.removeFromSuperview()
        editingTextField = nil
        editingExistingID = nil
        editingTextAnchor = nil
        needsDisplay = true
    }

    // MARK: - 合成导出
    func composeFinalImage() -> NSImage {
        let size = sourceImage.size
        let img = NSImage(size: size)
        img.lockFocus()

        sourceImage.draw(in: NSRect(origin: .zero, size: size))

        let sx = size.width / imageFrame.width
        let sy = size.height / imageFrame.height

        for element in elements {
            switch element.kind {
            case .rect:
                guard element.frame != .zero else { continue }
                let r = CGRect(x: element.frame.minX * sx, y: element.frame.minY * sy, width: element.frame.width * sx, height: element.frame.height * sy)
                element.color.setStroke()
                let path = NSBezierPath(rect: r)
                path.lineWidth = element.strokeWidth * sx
                path.stroke()
                element.color.withAlphaComponent(0.08).setFill()
                path.fill()
            case .arrow:
                guard element.points.count == 2 else { continue }
                let f = CGPoint(x: element.points[0].x * sx, y: element.points[0].y * sy)
                let t = CGPoint(x: element.points[1].x * sx, y: element.points[1].y * sy)
                drawArrow(from: f, to: t, color: element.color, strokeWidth: element.strokeWidth * sx)
            case .text:
                guard element.frame != .zero else { continue }
                let r = CGRect(x: element.frame.minX * sx, y: element.frame.minY * sy, width: element.frame.width * sx, height: element.frame.height * sy)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: element.fontSize * sy, weight: .semibold),
                    .foregroundColor: element.color
                ]
                element.text.draw(in: r, withAttributes: attrs)
            case .brush:
                guard element.points.count > 1 else { continue }
                element.color.setStroke()
                let path = NSBezierPath()
                path.move(to: CGPoint(x: element.points[0].x * sx, y: element.points[0].y * sy))
                for p in element.points.dropFirst() { path.line(to: CGPoint(x: p.x * sx, y: p.y * sy)) }
                path.lineWidth = element.strokeWidth * sx
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            case .mosaic:
                guard element.frame != .zero, let cgImg = sourceCGImage else { continue }
                let r = CGRect(x: element.frame.minX * sx, y: element.frame.minY * sy, width: element.frame.width * sx, height: element.frame.height * sy)
                let scaleToSource = CGFloat(cgImg.width) / size.width
                drawMosaic(in: r, sourceImage: cgImg, scaleToSource: scaleToSource)
            case .highlight:
                guard element.frame != .zero else { continue }
                let r = CGRect(x: element.frame.minX * sx, y: element.frame.minY * sy, width: element.frame.width * sx, height: element.frame.height * sy)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .multiply
                element.color.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: r, xRadius: 4 * sx, yRadius: 4 * sy).fill()
                NSGraphicsContext.restoreGraphicsState()
            case .sequence:
                guard let point = element.points.first else { continue }
                let p = CGPoint(x: point.x * sx, y: point.y * sy)
                let cSize: CGFloat = 28 * sx
                let circle = NSRect(x: p.x - cSize/2, y: p.y - cSize/2, width: cSize, height: cSize)
                let path = NSBezierPath(ovalIn: circle)
                element.color.setFill()
                path.fill()
                NSColor.white.setStroke()
                path.lineWidth = 2 * sx
                path.stroke()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14 * sy, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let text = "\(element.sequenceIndex)"
                let textSize = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: p.x - textSize.width/2, y: p.y - textSize.height/2 - 1 * sy), withAttributes: attrs)
            }
        }

        img.unlockFocus()
        return img
    }
}

// MARK: - 文字输入控件

final class CommitOnEnterTextField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            onCancel?()
        } else if event.keyCode == kVK_Return {
            onCommit?(stringValue)
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - 委托

extension AnnotationCanvas: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field == editingTextField else { return }
        commitTextEditing(text: field.stringValue, existingID: editingExistingID)
    }
}
