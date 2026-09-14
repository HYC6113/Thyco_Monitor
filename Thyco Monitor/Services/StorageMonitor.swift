import Foundation

struct StorageSnapshot {
    let usageFraction: Double
    let availableDisplay: String
    let usedDisplay: String
    let totalDisplay: String

    nonisolated static let unavailable = StorageSnapshot(
        usageFraction: 0,
        availableDisplay: "—",
        usedDisplay: "—",
        totalDisplay: "—"
    )
}

/// 存储监控（参考腾讯柠檬清理）：
/// 主磁盘可用空间使用 APFS `volumeAvailableCapacityForImportantUsage`，
/// 已用 = 总容量 − 可用，与系统设置 / 柠檬清理展示逻辑一致。
enum StorageMonitor {
    nonisolated static func snapshot() -> StorageSnapshot {
        autoreleasepool {
            let volumeURL = URL(fileURLWithPath: NSHomeDirectory())
            let resourceValues = try? volumeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey
            ])

            let total = UInt64(max(resourceValues?.volumeTotalCapacity ?? 0, 0))
            let availableImportant = UInt64(max(resourceValues?.volumeAvailableCapacityForImportantUsage ?? 0, 0))
            let availableRegular = UInt64(max(resourceValues?.volumeAvailableCapacity ?? 0, 0))
            let available = availableImportant > 0 ? availableImportant : availableRegular

            guard total > 0 else { return .unavailable }

            let used = total > available ? total - available : 0

            return StorageSnapshot(
                usageFraction: min(max(Double(used) / Double(total), 0), 1),
                availableDisplay: ByteFormatting.formatDecimalGB(available),
                usedDisplay: ByteFormatting.formatDecimalGB(used),
                totalDisplay: ByteFormatting.formatDecimalGB(total)
            )
        }
    }
}
