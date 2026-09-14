import Darwin
import Foundation

/// 与活动监视器「内存压力」图一致的三档系统压力（`kern.memorystatus_vm_pressure_level`）。
enum MemoryPressureLevel: Equatable, Sendable {
    case normal
    case warn
    case critical

    /// 读取当前系统内存压力（`kern.memorystatus_vm_pressure_level`）。
    nonisolated static func current() -> MemoryPressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 2: return .warn
        case 4: return .critical
        default: return .normal
        }
    }
}

struct MemorySnapshot {
    let physicalDisplay: String
    let usedDisplay: String
    let cachedDisplay: String
    let swapDisplay: String
    let appDisplay: String
    let wiredDisplay: String
    let compressedDisplay: String
    let pressureLevel: MemoryPressureLevel
}

/// 内存监控：与「活动监视器 › 内存」标签页使用相同的系统数据源与计算公式。
enum MemoryMonitor {
    /// 页大小与物理内存在运行期不会变化，只取一次。
    nonisolated private static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        guard host_page_size(MachHost.port, &size) == KERN_SUCCESS, size > 0 else {
            return UInt64(vm_kernel_page_size)
        }
        return UInt64(size)
    }()

    nonisolated private static let physicalMemory = ProcessInfo.processInfo.physicalMemory

    nonisolated static func snapshot() -> MemorySnapshot {
        let stats = vmStatistics64()

        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let fileBacked = UInt64(stats.external_page_count) * pageSize
        let free = UInt64(stats.free_count)
        let speculative = UInt64(stats.speculative_count)

        // 已用细分：与活动监视器 breakdown 一致（单次 host_statistics64 快照，避免 sysctl 混读）
        let appMemory = UInt64(stats.internal_page_count) * pageSize - purgeable
        // 文件缓存 = File-backed + Purgeable
        let cached = fileBacked + purgeable
        // 已用 = 物理内存 − 可用内存 − 文件缓存；可用 = (free − speculative) × 页大小
        // 活动监视器底部「已使用内存」走此恒等式，而非简单相加 App+联动+压缩（两者约差 1GB 属正常分类口径差）
        let available = free > speculative ? (free - speculative) * pageSize : 0
        let used = physicalMemory > available + cached
            ? physicalMemory - available - cached
            : appMemory + wired + compressed

        return MemorySnapshot(
            physicalDisplay: ByteFormatting.formatBytes(physicalMemory, decimals: 0),
            usedDisplay: ByteFormatting.formatBytes(used, decimals: 1),
            cachedDisplay: ByteFormatting.formatBytes(cached, decimals: 1),
            swapDisplay: ByteFormatting.formatBytes(swapUsedBytes(), decimals: 0),
            appDisplay: ByteFormatting.formatBytes(appMemory, decimals: 1),
            wiredDisplay: ByteFormatting.formatBytes(wired, decimals: 1),
            compressedDisplay: ByteFormatting.formatBytes(compressed, decimals: 1),
            pressureLevel: MemoryPressureLevel.current()
        )
    }

    /// 读取失败时返回全零结构，各项指标随之显示为 0。
    nonisolated private static func vmStatistics64() -> vm_statistics64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(MachHost.port, HOST_VM_INFO64, intPointer, &count)
            }
        }

        return result == KERN_SUCCESS ? stats : vm_statistics64()
    }

    nonisolated private static func swapUsedBytes() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return 0 }
        return swap.xsu_used
    }
}
