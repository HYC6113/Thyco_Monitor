import Foundation
import IOKit

enum SystemInfoProvider {
    /// 面板标题栏摘要：设备名 · 芯片 · 系统版本（运行期不会变化，只解析一次）
    static let headerSummary: String = {
        let deviceName = Host.current().localizedName ?? "Mac"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return "\(deviceName) · \(readChipName()) · \(systemVersion)"
    }()

    nonisolated private static func readChipName() -> String {
        if let chip = ioPlatformString(forKey: "chip-model"), !chip.isEmpty {
            return chip
        }
        if let brand = sysctlString(forName: "machdep.cpu.brand_string"), !brand.isEmpty {
            return brand.trimmingCharacters(in: .whitespaces)
        }
        if let model = sysctlString(forName: "hw.model") {
            return model
        }
        return sysctlString(forName: "hw.machine") ?? "Mac"
    }

    nonisolated private static func ioPlatformString(forKey key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        guard service != 0 else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    nonisolated private static func sysctlString(forName name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
