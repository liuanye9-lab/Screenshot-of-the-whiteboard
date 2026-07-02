// AXUIElement+WindowID.swift — 辅助功能元素获取 CGWindowID 的私有 API 桥接
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
