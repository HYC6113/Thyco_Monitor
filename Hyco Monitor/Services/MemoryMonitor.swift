import Darwin
import Foundation

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
}

/// 内存监控：与「活动监视器 › 内存」标签页使用相同的系统数据源与计算公式。
enum MemoryMonitor {
    nonisolated static func snapshot() -> MemorySnapshot {
        let pageSize = hostPageSize()
        let physical = physicalMemoryBytes()
        let stats = vmStatistics64()
        let pageableInternal = pagePageableInternalCount()

        let wired = stats.wireCount * pageSize
        let compressed = stats.compressorPageCount * pageSize
        let purgeable = stats.purgeableCount * pageSize
        let inactive = stats.inactiveCount * pageSize

        // 活动监视器：App 内存 = page_pageable_internal_count × 页大小 − 可清除页
        let appMemory = pageableInternal * pageSize - purgeable
        // 已用 = App + 联动 + 压缩
        let used = appMemory + wired + compressed
        // 缓存 = 非活跃 + 可清除
        let cached = inactive + purgeable
        let swap = swapUsedBytes()

        return MemorySnapshot(
            physicalMemory: physical,
            usedMemory: min(used, physical),
            cachedFiles: cached,
            swapUsed: swap,
            appMemory: appMemory,
            wiredMemory: wired,
            compressedMemory: compressed,
            physicalDisplay: ByteFormatting.formatBytes(physical, decimals: 0),
            usedDisplay: ByteFormatting.formatBytes(min(used, physical), decimals: 1),
            cachedDisplay: ByteFormatting.formatBytes(cached, decimals: 1),
            swapDisplay: ByteFormatting.formatBytes(swap, decimals: 0),
            appDisplay: ByteFormatting.formatBytes(appMemory, decimals: 1),
            wiredDisplay: ByteFormatting.formatBytes(wired, decimals: 1),
            compressedDisplay: ByteFormatting.formatBytes(compressed, decimals: 1)
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

    nonisolated private static func pagePageableInternalCount() -> UInt64 {
        var count: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("vm.page_pageable_internal_count", &count, &size, nil, 0) == 0 else {
            return 0
        }
        return count
    }

    nonisolated private static func vmStatistics64() -> (
        wireCount: UInt64,
        inactiveCount: UInt64,
        purgeableCount: UInt64,
        compressorPageCount: UInt64
    ) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0, 0, 0)
        }

        return (
            wireCount: UInt64(stats.wire_count),
            inactiveCount: UInt64(stats.inactive_count),
            purgeableCount: UInt64(stats.purgeable_count),
            compressorPageCount: UInt64(stats.compressor_page_count)
        )
    }

    nonisolated private static func swapUsedBytes() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return 0 }
        return swap.xsu_used
    }
}
