import AppKit
import Foundation

/// 隐藏/显示桌面图标，实现方式与 One Switch、OnlySwitch 一致：
/// 修改 Finder 的 `CreateDesktop` 偏好并重启 Finder，桌面只保留壁纸，文件仍位于 ~/Desktop。
enum SystemToolsService {
    /// 进程内读取 Finder 偏好；该值由外部 `defaults write` 改写，读取前先丢弃本进程缓存。
    /// `defaults write … 0/1` 存的是字符串，One Switch 等工具用 `-bool` 存布尔，两种都要认。
    nonisolated static func isDesktopHidden() -> Bool {
        let domain = "com.apple.finder" as CFString
        CFPreferencesAppSynchronize(domain)

        switch CFPreferencesCopyAppValue("CreateDesktop" as CFString, domain) {
        case let text as String: return text == "0" || text == "false"
        case let number as NSNumber: return !number.boolValue
        // 未设置该键时 Finder 默认显示桌面图标
        default: return false
        }
    }

    @discardableResult
    nonisolated static func setDesktopHidden(_ hidden: Bool) -> Bool {
        guard runCommand(
            executable: "/usr/bin/defaults",
            arguments: ["write", "com.apple.finder", "CreateDesktop", hidden ? "0" : "1"]
        ) else {
            return false
        }
        // One Switch / OnlySwitch 均通过重启 Finder 使设置立即生效
        return runCommand(executable: "/usr/bin/killall", arguments: ["Finder"])
    }

    /// 打开系统设置中的网络（优先跳转 Wi-Fi 页面）。
    nonisolated static func openNetworkSettings() {
        openSettings([
            "x-apple.systempreferences:com.apple.Network-Settings.extension?Wi-Fi",
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.network"
        ])
    }

    /// 打开系统设置中的存储空间。
    nonisolated static func openStorageSettings() {
        openSettings([
            "x-apple.systempreferences:com.apple.settings.Storage",
            "x-apple.systempreferences:com.apple.StorageManagement-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.storage"
        ])
    }

    /// 依次尝试候选 URL，命中第一个可打开的设置面板。
    nonisolated private static func openSettings(_ candidates: [String]) {
        DispatchQueue.main.async {
            for candidate in candidates {
                guard let url = URL(string: candidate) else { continue }
                if NSWorkspace.shared.open(url) { return }
            }
        }
    }

    @discardableResult
    nonisolated private static func runCommand(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
