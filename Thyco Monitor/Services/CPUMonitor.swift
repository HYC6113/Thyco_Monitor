import Foundation

struct CPUSnapshot {
    let usagePercent: Double
}

/// 内核累计计数是 UInt32；先逐项计算回绕差值，再扩展并求和。
nonisolated struct CPUUsageSampler {
    private var previous: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    mutating func sample(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) -> Double {
        defer { previous = (user, system, idle, nice) }
        guard let previous else { return 0 }

        let idleDelta = UInt64(idle &- previous.idle)
        let totalDelta = UInt64(user &- previous.user)
            + UInt64(system &- previous.system)
            + idleDelta
            + UInt64(nice &- previous.nice)
        guard totalDelta > 0 else { return 0 }
        return (1 - Double(idleDelta) / Double(totalDelta)) * 100
    }
}

enum CPUMonitor {
    nonisolated(unsafe) private static var sampler = CPUUsageSampler()
    nonisolated private static let lock = NSLock()

    nonisolated static func resetBaseline() {
        lock.lock()
        defer { lock.unlock() }
        sampler = CPUUsageSampler()
    }

    nonisolated static func snapshot() -> CPUSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics(MachHost.port, HOST_CPU_LOAD_INFO, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            sampler = CPUUsageSampler()
            return CPUSnapshot(usagePercent: 0)
        }

        return CPUSnapshot(usagePercent: sampler.sample(
            user: cpuInfo.cpu_ticks.0,
            system: cpuInfo.cpu_ticks.1,
            idle: cpuInfo.cpu_ticks.2,
            nice: cpuInfo.cpu_ticks.3
        ))
    }
}
