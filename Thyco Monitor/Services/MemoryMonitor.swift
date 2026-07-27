import Darwin
import Foundation

/// 与活动监视器「内存压力」图一致的三档系统压力（`kern.memorystatus_vm_pressure_level`）。
enum MemoryPressureLevel: Equatable, Sendable {
    case normal
    case warn
    case critical

    nonisolated static func fromSysctlValue(_ value: Int32) -> MemoryPressureLevel {
        switch value {
        case 1: .normal
        case 2: .warn
        case 4: .critical
        default: .normal
        }
    }

    /// 读取当前系统内存压力（`kern.memorystatus_vm_pressure_level`）。
    nonisolated static func current() -> MemoryPressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return fromSysctlValue(level)
    }
}

struct MemorySnapshot {
    let physicalMemory: UInt64
    let usedMemory: UInt64
    let cachedFiles: UInt64
    let swapUsed: UInt64
    let appMemory: UInt64
    let wiredMemory: UInt64
    let compressedMemory: UInt64

    let physicalDisplay: String
    let usedDisplay: String
    let cachedDisplay: String
    let swapDisplay: String
    let appDisplay: String
    let wiredDisplay: String
    let compressedDisplay: String
    let pressureLevel: MemoryPressureLevel
}

private struct VMStatisticsSnapshot {
    let wireCount: UInt64
    let externalPageCount: UInt64
    let purgeableCount: UInt64
    let compressorPageCount: UInt64
    let internalPageCount: UInt64
    let freeCount: UInt64
    let speculativeCount: UInt64
}

/// 内存监控：与「活动监视器 › 内存」标签页使用相同的系统数据源与计算公式。
enum MemoryMonitor {
    nonisolated static func snapshot() -> MemorySnapshot {
        let pageSize = hostPageSize()
        let physical = physicalMemoryBytes()
        let stats = vmStatistics64()

        let wired = stats.wireCount * pageSize
        let compressed = stats.compressorPageCount * pageSize
        let purgeable = stats.purgeableCount * pageSize
        let fileBacked = stats.externalPageCount * pageSize

        // 已用细分：与活动监视器 breakdown 一致（单次 host_statistics64 快照，避免 sysctl 混读）
        let appMemory = stats.internalPageCount * pageSize - purgeable
        // 文件缓存 = File-backed + Purgeable
        let cached = fileBacked + purgeable
        // 已用 = 物理内存 − 可用内存 − 文件缓存；可用 = (free − speculative) × 页大小
        // 活动监视器底部「已使用内存」走此恒等式，而非简单相加 App+联动+压缩（两者约差 1GB 属正常分类口径差）
        let available = stats.freeCount > stats.speculativeCount
            ? (stats.freeCount - stats.speculativeCount) * pageSize
            : 0
        let used = physical > available + cached
            ? physical - available - cached
            : appMemory + wired + compressed
        let swap = swapUsedBytes()

        return MemorySnapshot(
            physicalMemory: physical,
            usedMemory: used,
            cachedFiles: cached,
            swapUsed: swap,
            appMemory: appMemory,
            wiredMemory: wired,
            compressedMemory: compressed,
            physicalDisplay: ByteFormatting.formatBytes(physical, decimals: 0),
            usedDisplay: ByteFormatting.formatBytes(used, decimals: 1),
            cachedDisplay: ByteFormatting.formatBytes(cached, decimals: 1),
            swapDisplay: ByteFormatting.formatBytes(swap, decimals: 0),
            appDisplay: ByteFormatting.formatBytes(appMemory, decimals: 1),
            wiredDisplay: ByteFormatting.formatBytes(wired, decimals: 1),
            compressedDisplay: ByteFormatting.formatBytes(compressed, decimals: 1),
            pressureLevel: MemoryPressureLevel.current()
        )
    }

    nonisolated private static func hostPageSize() -> UInt64 {
        var size: vm_size_t = 0
        if host_page_size(mach_host_self(), &size) == KERN_SUCCESS, size > 0 {
            return UInt64(size)
        }
        return UInt64(vm_kernel_page_size)
    }

    nonisolated private static func physicalMemoryBytes() -> UInt64 {
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &length, nil, 0)
        return size
    }

    nonisolated private static func vmStatistics64() -> VMStatisticsSnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return VMStatisticsSnapshot(
                wireCount: 0,
                externalPageCount: 0,
                purgeableCount: 0,
                compressorPageCount: 0,
                internalPageCount: 0,
                freeCount: 0,
                speculativeCount: 0
            )
        }

        return VMStatisticsSnapshot(
            wireCount: UInt64(stats.wire_count),
            externalPageCount: UInt64(stats.external_page_count),
            purgeableCount: UInt64(stats.purgeable_count),
            compressorPageCount: UInt64(stats.compressor_page_count),
            internalPageCount: UInt64(stats.internal_page_count),
            freeCount: UInt64(stats.free_count),
            speculativeCount: UInt64(stats.speculative_count)
        )
    }

    nonisolated private static func swapUsedBytes() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return 0 }
        return swap.xsu_used
    }
}
