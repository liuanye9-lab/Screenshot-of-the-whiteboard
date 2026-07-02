// PermissionManager.swift — 权限状态检查与申请
import AppKit
import CoreGraphics

enum PermissionManager {
    static func checkScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    static var allGranted: Bool {
        checkScreenRecording() && checkAccessibility()
    }
}
