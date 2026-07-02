// CaptureService.swift — 截图引擎：局部 / 全屏 / 窗口 / 滚动长图 / 多显示器
import AppKit
import CoreGraphics
import Carbon

// MARK: - 截图服务

class CaptureService {

    private static var currentScrollingOverlay: ScrollingOverlayWindow?

    /// 局部截图（自定义覆层：放大镜 + 十字准线）
    static func captureRegion() async throws -> NSImage {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame
        guard let (image, cgImage) = captureScreenPair(screen) else {
            throw CaptureError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let overlay = CaptureOverlayWindow(screenImage: image, cgImage: cgImage, screenFrame: screenFrame) { result in
                    if let img = result {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: CaptureError.captureCancelled)
                    }
                }
                overlay.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 全屏截图（指定显示器）
    static func captureFullScreen() async throws -> NSImage {
        guard let screen = NSScreen.main, let image = captureScreen(screen) else {
            throw CaptureError.permissionDenied
        }
        return image
    }

    /// 窗口截图（系统交互式选择）
    static func captureWindow() async throws -> NSImage {
        let url = try await runScreencapture(["-iw", "-x"])
        return loadImage(from: url)
    }

    /// 截取前台窗口（CGWindowListCreateImage 原生方案，无需交互选择）
    static func captureFrontmostWindow() throws -> NSImage {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CaptureError.noWindowFound
        }
        let pid = frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureError.noWindowFound
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let windowID = window[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                .boundsIgnoreFraming
            ) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }

        throw CaptureError.noWindowFound
    }

    /// 滚动长图截图：捕获前台窗口可视区域，进入手动滚动覆层由用户选取长图范围
    static func captureScrolling(onComplete: @escaping (NSImage?) -> Void) {
        Task { @MainActor in
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                onComplete(nil); return
            }
            let pid = frontApp.processIdentifier

            let app = AXUIElementCreateApplication(pid)
            var windowRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowRef) == .success,
                  let windows = windowRef as? [AXUIElement],
                  let mainWindow = windows.first else {
                onComplete(nil); return
            }

            var posVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            AXUIElementCopyAttributeValue(mainWindow, kAXPositionAttribute as CFString, &posVal)
            AXUIElementCopyAttributeValue(mainWindow, kAXSizeAttribute as CFString, &sizeVal)

            guard let pos = posVal, let siz = sizeVal else { onComplete(nil); return }
            var posPoint = CGPoint.zero
            var sizeCGSize = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &posPoint)
            AXValueGetValue(siz as! AXValue, .cgSize, &sizeCGSize)
            let windowRect = CGRect(origin: posPoint, size: sizeCGSize)

            guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
                onComplete(nil); return
            }
            let initial = cropCGImage(cgImage, to: windowRect)
            let initialImage = NSImage(cgImage: initial, size: windowRect.size)

            currentScrollingOverlay?.orderOut(nil)
            currentScrollingOverlay = ScrollingOverlayWindow(initialImage: initialImage, windowRect: windowRect) { image in
                currentScrollingOverlay = nil
                onComplete(image)
            }
        }
    }

    // MARK: - 多显示器支持

    static func captureScreen(_ screen: NSScreen) -> NSImage? {
        captureScreenPair(screen)?.image
    }

    private static func captureScreenPair(_ screen: NSScreen) -> (image: NSImage, cgImage: CGImage)? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cgImage = CGDisplayCreateImage(displayID) else { return nil }
        return (NSImage(cgImage: cgImage, size: screen.frame.size), cgImage)
    }

    // MARK: - 滚动区域查找

    private static func findScrollArea(_ element: AXUIElement, result: inout AXUIElement?) {
        guard result == nil else { return }
        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        let role = (roleVal as? String) ?? ""
        if role == "AXScrollArea" {
            result = element
            return
        }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let kids = children as? [AXUIElement] {
            for child in kids {
                findScrollArea(child, result: &result)
                if result != nil { return }
            }
        }
    }

    // MARK: - 图片拼接

    private static func stitchImages(_ images: [CGImage]) -> NSImage? {
        guard let first = images.first else { return nil }
        let width = first.width
        let totalHeight = images.reduce(0) { $0 + $1.height }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var y = totalHeight
        for img in images {
            y -= img.height
            ctx.draw(img, in: CGRect(x: 0, y: y, width: width, height: img.height))
        }

        guard let result = ctx.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: width, height: totalHeight))
    }

    // MARK: - 工具方法

    private static func runScreencapture(_ args: [String]) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapleaf_\(UUID().uuidString).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = args + [tmp.path]
        try proc.run()
        proc.waitUntilExit()
        guard FileManager.default.fileExists(atPath: tmp.path) else {
            throw CaptureError.captureCancelled
        }
        return tmp
    }

    private static func loadImage(from url: URL) -> NSImage {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let img = NSImage(contentsOf: url) else {
            fatalError("无法加载截图")
        }
        return img
    }

    private static func cropCGImage(_ image: CGImage, to rect: CGRect) -> CGImage {
        let scale = CGFloat(image.width) / CGFloat(NSScreen.main?.frame.width ?? 1)
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: (CGFloat(NSScreen.main?.frame.height ?? 1) - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        return image.cropping(to: scaledRect) ?? image
    }
}

enum CaptureError: Error, LocalizedError {
    case captureCancelled
    case permissionDenied
    case noWindowFound

    var errorDescription: String? {
        switch self {
        case .captureCancelled: return "截图已取消"
        case .permissionDenied: return "需要屏幕录制权限"
        case .noWindowFound: return "未找到前台窗口"
        }
    }
}
