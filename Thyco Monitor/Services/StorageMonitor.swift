import Foundation

struct StorageSnapshot {
    let availableBytes: UInt64
    let usedBytes: UInt64
    let totalBytes: UInt64
    let usageFraction: Double
    let availableDisplay: String
    let usedDisplay: String
    let totalDisplay: String
}

/// 存储监控（参考腾讯柠檬清理）：
/// 主磁盘可用空间使用 APFS `volumeAvailableCapacityForImportantUsage`，
/// 已用 = 总容量 − 可用，与系统设置 / 柠檬清理展示逻辑一致。
enum StorageMonitor {
    nonisolated static func snapshot() -> StorageSnapshot {
        autoreleasepool {
            snapshotUnpooled()
        }
    }

    nonisolated private static func snapshotUnpooled() -> StorageSnapshot {
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

        guard total > 0 else {
            return emptySnapshot()
        }

        let used = total > available ? total - available : 0
        let fraction = min(max(Double(used) / Double(total), 0), 1)

        return StorageSnapshot(
            availableBytes: available,
            usedBytes: used,
            totalBytes: total,
            usageFraction: fraction,
            availableDisplay: ByteFormatting.formatDecimalGB(available),
            usedDisplay: ByteFormatting.formatDecimalGB(used),
            totalDisplay: ByteFormatting.formatDecimalGB(total)
        )
    }

    nonisolated private static func emptySnapshot() -> StorageSnapshot {
        StorageSnapshot(
            availableBytes: 0,
            usedBytes: 0,
            totalBytes: 0,
            usageFraction: 0,
            availableDisplay: "—",
            usedDisplay: "—",
            totalDisplay: "—"
        )
    }
}
