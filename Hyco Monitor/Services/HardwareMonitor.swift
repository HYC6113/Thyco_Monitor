import Foundation

struct HardwareSnapshot {
    let cpuTemperatureCelsius: Double?
    let fanRPM: Int?
}

enum HardwareMonitor {
    nonisolated static func snapshot() -> HardwareSnapshot {
        let smc = SMCService.shared
        return HardwareSnapshot(
            cpuTemperatureCelsius: smc.cpuTemperatureCelsius(),
            fanRPM: smc.primaryFanRPM()
        )
    }
}
