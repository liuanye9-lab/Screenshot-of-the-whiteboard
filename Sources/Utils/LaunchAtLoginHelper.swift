// LaunchAtLoginHelper.swift — 登录自启动 helper 管理
import Foundation
import ServiceManagement

enum LaunchAtLoginHelper {
    static func register() {
        let service = SMAppService.mainApp
        do {
            if service.status != .enabled {
                try service.register()
            }
        } catch {
            print("注册登录启动失败: \(error)")
        }
    }

    static func unregister() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            print("取消登录启动失败: \(error)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
