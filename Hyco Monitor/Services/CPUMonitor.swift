import Foundation

struct CPUSnapshot {
    let usagePercent: Double
}

enum CPUMonitor {
    nonisolated(unsafe) private static var previousTotal: UInt64?
    nonisolated(unsafe) private static var previousIdle: UInt64?
    nonisolated(unsafe) private static var lock = NSLock()

    nonisolated static func snapshot() -> CPUSnapshot {
        CPUSnapshot(usagePercent: currentUsagePercent())
    }

    nonisolated private static func currentUsagePercent() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let user = UInt64(cpuInfo.cpu_ticks.0)
        let system = UInt64(cpuInfo.cpu_ticks.1)
        let idle = UInt64(cpuInfo.cpu_ticks.2)
        let nice = UInt64(cpuInfo.cpu_ticks.3)
        let total = user + system + idle + nice

        lock.lock()
        defer {
            previousTotal = total
            previousIdle = idle
            lock.unlock()
        }

        guard let previousTotal, let previousIdle, total > previousTotal else {
            return 0
        }

        let totalDelta = total - previousTotal
        let idleDelta = idle - previousIdle
        guard totalDelta > 0 else { return 0 }

        let usage = (1.0 - Double(idleDelta) / Double(totalDelta)) * 100.0
        return min(max(usage, 0), 100)
    }
}
