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

    static func openScreenRecordingSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        ]
        for url in urls {
            if let url = url, NSWorkspace.shared.open(url) { return }
        }
    }

    static func openAccessibilitySettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        ]
        for url in urls {
            if let url = url, NSWorkspace.shared.open(url) { return }
        }
    }

    static func requestAll() {
        requestScreenRecording()
        requestAccessibility()
    }
}
