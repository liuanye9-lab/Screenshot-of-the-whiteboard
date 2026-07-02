// AnnotationModels.swift — 标注数据模型与几何工具
import AppKit

// MARK: - 工具类型

enum AnnotationTool: Int, CaseIterable {
    case select, rect, arrow, text, brush, mosaic, highlight, sequence, undo, redo, done, cancel

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .rect: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .brush: return "pencil"
        case .mosaic: return "square.grid.3x3.fill"
        case .highlight: return "highlighter"
        case .sequence: return "number.circle"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .done: return "checkmark.circle.fill"
        case .cancel: return "xmark.circle.fill"
        }
    }

    var tooltip: String {
        switch self {
        case .select: return "选择 / 移动"
        case .rect: return "矩形框 ⌘1"
        case .arrow: return "箭头 ⌘2"
        case .text: return "文字 ⌘3"
        case .brush: return "画笔 ⌘4"
        case .mosaic: return "马赛克 ⌘5"
        case .highlight: return "高亮 ⌘6"
        case .sequence: return "序号 ⌘7"
        case .undo: return "撤销 ⌘Z"
        case .redo: return "重做 ⌘⇧Z"
        case .done: return "完成 ↵"
        case .cancel: return "取消 ⎋"
        }
    }

    var isColorable: Bool {
        switch self {
        case .rect, .arrow, .text, .brush, .highlight, .sequence: return true
        default: return false
        }
    }

    var supportsStrokeWidth: Bool {
        switch self {
        case .rect, .arrow, .brush, .highlight: return true
        default: return false
        }
    }

    var isDrawingTool: Bool {
        switch self {
        case .select, .undo, .redo, .done, .cancel: return false
        default: return true
        }
    }
}

// MARK: - 标注元素

enum AnnotationKind {
    case rect, arrow, text, brush, mosaic, highlight, sequence
}

struct AnnotationElement: Identifiable {
    let id: UUID
    var kind: AnnotationKind
    var frame: CGRect = .zero
    var points: [CGPoint] = []
    var color: NSColor = LeafStyle.systemRed
    var strokeWidth: CGFloat = LeafStyle.strokeWidth
    var text: String = ""
    var sequenceIndex: Int = 0
    var image: CGImage? // 马赛克源图
    var fontSize: CGFloat = 16

    var boundingRect: CGRect {
        switch kind {
        case .rect, .highlight, .mosaic, .text:
            return frame
        case .arrow:
            return points.count == 2 ? CGRect(through: points) : .zero
        case .brush:
            return points.boundingRect
        case .sequence:
            guard let p = points.first else { return .zero }
            return CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
        }
    }

    mutating func translate(by offset: CGSize) {
        switch kind {
        case .rect, .highlight, .mosaic, .text:
            frame = frame.offsetBy(dx: offset.width, dy: offset.height)
        case .arrow, .brush:
            points = points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        case .sequence:
            if let p = points.first {
                points = [CGPoint(x: p.x + offset.width, y: p.y + offset.height)]
            }
        }
    }

    func translated(by offset: CGSize) -> AnnotationElement {
        var copy = self
        copy.translate(by: offset)
        return copy
    }
}

// MARK: - 几何辅助

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distance(toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: x - a.x, y: y - a.y)
        let ab2 = ab.x * ab.x + ab.y * ab.y
        if ab2 == 0 { return ap.distance(to: .zero) }
        let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / ab2))
        let proj = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
        return self.distance(to: proj)
    }
}

extension CGRect {
    init(through points: [CGPoint]) {
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        self.init(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension Array where Element == CGPoint {
    var boundingRect: CGRect { CGRect(through: self) }

    func distance(from point: CGPoint) -> CGFloat {
        guard count > 1 else { return first?.distance(to: point) ?? .infinity }
        var minDist: CGFloat = .infinity
        for i in 0..<(count - 1) {
            minDist = Swift.min(minDist, point.distance(toSegment: self[i], self[i + 1]))
        }
        return minDist
    }
}
