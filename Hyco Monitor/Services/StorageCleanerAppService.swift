import AppKit
import UniformTypeIdentifiers

struct StorageCleanerAppInfo {
    let url: URL
    let name: String
    let icon: NSImage
}

/// 用户自定义的存储清理 App（路径持久化于 UserDefaults）
enum StorageCleanerAppService {
    private static let pathKey = "storageCleanerAppPath"

    static func savedApp() -> StorageCleanerAppInfo? {
        guard let path = UserDefaults.standard.string(forKey: pathKey) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: path), url.pathExtension == "app" else {
            UserDefaults.standard.removeObject(forKey: pathKey)
            return nil
        }

        return StorageCleanerAppInfo(
            url: url,
            name: appDisplayName(for: url),
            icon: NSWorkspace.shared.icon(forFile: path)
        )
    }

    @MainActor
    @discardableResult
    static func pickApp() -> StorageCleanerAppInfo? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"
        panel.message = "选择用于清理存储空间的 App"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        UserDefaults.standard.set(url.path, forKey: pathKey)
        return savedApp()
    }

    @MainActor
    static func openApp() async -> Bool {
        guard let app = savedApp() else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            _ = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    static func clearApp() {
        UserDefaults.standard.removeObject(forKey: pathKey)
    }

    private static func appDisplayName(for url: URL) -> String {
        if let bundle = Bundle(url: url) {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !display.isEmpty {
                return display
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
