import AppKit
import Foundation

/// 隐藏/显示桌面图标，实现方式与 One Switch、OnlySwitch 一致：
/// 修改 Finder 的 `CreateDesktop` 偏好并重启 Finder，桌面只保留壁纸，文件仍位于 ~/Desktop。
enum SystemToolsService {

    nonisolated static func isDesktopHidden() -> Bool {
        guard let output = readDefaults(domain: "com.apple.finder", key: "CreateDesktop") else {
            // 未设置该键时 Finder 默认显示桌面图标
            return false
        }
        return output == "0"
    }

    /// 打开系统设置中的网络（优先跳转 Wi-Fi 页面）。
    nonisolated static func openNetworkSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Network-Settings.extension?Wi-Fi",
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.network"
        ]

        DispatchQueue.main.async {
            for candidate in candidates {
                guard let url = URL(string: candidate) else { continue }
                if NSWorkspace.shared.open(url) { return }
            }
        }
    }

    /// 打开系统设置中的存储空间。
    nonisolated static func openStorageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.Storage",
            "x-apple.systempreferences:com.apple.StorageManagement-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.storage"
        ]

        DispatchQueue.main.async {
            for candidate in candidates {
                guard let url = URL(string: candidate) else { continue }
                if NSWorkspace.shared.open(url) { return }
            }
        }
    }

    @discardableResult
    nonisolated static func setDesktopHidden(_ hidden: Bool) -> Bool {
        let value = hidden ? "0" : "1"
        guard runCommand(
            executable: "/usr/bin/defaults",
            arguments: ["write", "com.apple.finder", "CreateDesktop", value]
        ) else {
            return false
        }
        // One Switch / OnlySwitch 均通过重启 Finder 使设置立即生效
        return runCommand(executable: "/usr/bin/killall", arguments: ["Finder"])
    }

    nonisolated private static func readDefaults(domain: String, key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    @discardableResult
    nonisolated private static func runCommand(executable: String, arguments: [String] = []) -> Bool {
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
