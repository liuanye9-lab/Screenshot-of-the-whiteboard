// AnnotationToolbar.swift — 标注白板浮动工具栏
import AppKit

class AnnotationToolbar: NSView {
    var onToolSelect: ((AnnotationTool) -> Void)?
    var onColorSelect: ((NSColor) -> Void)?
    var onStrokeWidthChange: ((CGFloat) -> Void)?
    var onZoomReset: (() -> Void)?

    private var toolButtons: [NSButton] = []
    private var colorDots: [NSView] = []
    private var colorDotIndexMap: [ObjectIdentifier: Int] = [:]
    private var selectedTool: AnnotationTool = .rect

    private let colors: [NSColor] = [
        LeafStyle.systemRed,
        LeafStyle.primaryBlue,
        LeafStyle.systemYellow,
        LeafStyle.systemGreen,
        LeafStyle.systemPurple,
        NSColor.white
    ]

    private var strokeWidthSlider: NSSlider!
    private var widthLabel: NSTextField!

    private var currentColorIndex: Int = 0
    private var currentStrokeWidth: CGFloat = LeafStyle.strokeWidth

    private(set) var contentWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        autoresizingMask = [.width]

        let blur = LeafStyle.makeToolbarBackground(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        let buttonSize: CGFloat = 34
        let spacing: CGFloat = 3
        var x: CGFloat = 10

        // 工具按钮
        for tool in AnnotationTool.allCases {
            let btn = NSButton(frame: NSRect(x: x, y: (frame.height - buttonSize) / 2, width: buttonSize, height: buttonSize))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = buttonSize / 2

            if let img = NSImage(systemSymbolName: tool.icon, accessibilityDescription: tool.tooltip) {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
                btn.image = img.withSymbolConfiguration(config)
                btn.contentTintColor = NSColor.labelColor
            }
            btn.toolTip = tool.tooltip
            btn.tag = tool.rawValue
            btn.target = self
            btn.action = #selector(toolClicked(_:))
            addSubview(btn)
            toolButtons.append(btn)

            if tool == .rect {
                highlightButton(btn, active: true)
            }

            x += buttonSize + spacing

            if tool == .sequence || tool == .redo {
                let sep = NSView(frame: NSRect(x: x, y: 10, width: 1, height: frame.height - 20))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
                addSubview(sep)
                x += 8
            }
        }

        // 颜色选择
        x += 4
        for (i, color) in colors.enumerated() {
            let dotSize: CGFloat = 20
            let dot = NSView(frame: NSRect(x: x, y: (frame.height - dotSize) / 2, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.borderWidth = i == 0 ? 2.5 : 1
            dot.layer?.borderColor = (i == 0 ? NSColor.white : NSColor.separatorColor).cgColor

            let click = NSClickGestureRecognizer(target: self, action: #selector(colorClicked(_:)))
            dot.addGestureRecognizer(click)
            colorDotIndexMap[ObjectIdentifier(dot)] = i
            addSubview(dot)
            colorDots.append(dot)
            x += dotSize + 6
        }

        // 画笔粗细滑条
        x += 6
        widthLabel = NSTextField(labelWithString: "\(Int(currentStrokeWidth))")
        widthLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        widthLabel.textColor = NSColor.secondaryLabelColor
        widthLabel.alignment = .center
        widthLabel.frame = NSRect(x: x, y: (frame.height - 14) / 2, width: 20, height: 14)
        addSubview(widthLabel)
        x += 24

        strokeWidthSlider = NSSlider(value: Double(currentStrokeWidth), minValue: 1, maxValue: 10, target: self, action: #selector(strokeSliderChanged(_:)))
        strokeWidthSlider.isContinuous = true
        strokeWidthSlider.frame = NSRect(x: x, y: (frame.height - 16) / 2, width: 80, height: 16)
        strokeWidthSlider.isEnabled = true
        addSubview(strokeWidthSlider)
        x += 86

        // 缩放重置
        let resetBtn = NSButton(frame: NSRect(x: x, y: (frame.height - buttonSize) / 2, width: buttonSize, height: buttonSize))
        resetBtn.bezelStyle = .inline
        resetBtn.isBordered = false
        if let img = NSImage(systemSymbolName: "1.magnifyingglass", accessibilityDescription: "重置缩放") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            resetBtn.image = img.withSymbolConfiguration(config)
            resetBtn.contentTintColor = NSColor.secondaryLabelColor
        }
        resetBtn.toolTip = "重置缩放 (⌘0)"
        resetBtn.target = self
        resetBtn.action = #selector(zoomResetClicked(_:))
        addSubview(resetBtn)

        contentWidth = x + buttonSize + 10
    }

    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        for btn in toolButtons {
            if let t = AnnotationTool(rawValue: btn.tag), t.isColorable {
                highlightButton(btn, active: t == tool)
            }
        }
        strokeWidthSlider.isEnabled = tool.supportsStrokeWidth
    }

    func setColor(_ color: NSColor) {
        if let idx = colors.firstIndex(where: { $0.isEqual(color) }) {
            currentColorIndex = idx
            updateColorDots()
        }
    }

    func setStrokeWidth(_ width: CGFloat) {
        currentStrokeWidth = width
        strokeWidthSlider.doubleValue = Double(width)
        widthLabel.stringValue = "\(Int(width))"
    }

    @objc private func toolClicked(_ sender: NSButton) {
        guard let tool = AnnotationTool(rawValue: sender.tag) else { return }
        if tool.isColorable {
            selectedTool = tool
            for btn in toolButtons {
                if let t = AnnotationTool(rawValue: btn.tag), t.isColorable {
                    highlightButton(btn, active: btn.tag == sender.tag)
                }
            }
        }
        strokeWidthSlider.isEnabled = selectedTool.supportsStrokeWidth
        onToolSelect?(tool)
    }

    @objc private func colorClicked(_ gesture: NSClickGestureRecognizer) {
        guard let dot = gesture.view, let idx = colorDotIndexMap[ObjectIdentifier(dot)] else { return }
        currentColorIndex = idx
        updateColorDots()
        onColorSelect?(colors[idx])
    }

    @objc private func strokeSliderChanged(_ sender: NSSlider) {
        let width = CGFloat(sender.doubleValue)
        currentStrokeWidth = width
        widthLabel.stringValue = "\(Int(width))"
        onStrokeWidthChange?(width)
    }

    @objc private func zoomResetClicked(_ sender: NSButton) {
        onZoomReset?()
    }

    private func updateColorDots() {
        for (i, dot) in colorDots.enumerated() {
            dot.layer?.borderWidth = i == currentColorIndex ? 2.5 : 1
            dot.layer?.borderColor = (i == currentColorIndex ? NSColor.white : NSColor.separatorColor).cgColor
        }
    }

    private func highlightButton(_ btn: NSButton, active: Bool) {
        btn.layer?.backgroundColor = active ? LeafStyle.primaryBlue.withAlphaComponent(0.2).cgColor : nil
        btn.contentTintColor = active ? LeafStyle.primaryBlue : NSColor.labelColor
    }
}
