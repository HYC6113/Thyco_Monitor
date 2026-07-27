import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot {
    let percentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let isActivelyCharging: Bool
    let chargingPowerWatts: Int?
    let displayValue: String

    var chargingPowerDisplay: String? {
        guard isCharging, let chargingPowerWatts else { return nil }
        return "\(chargingPowerWatts)"
    }
}

enum BatteryMonitor {
    nonisolated static func snapshot() -> BatterySnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatterySnapshot(
                percentage: nil,
                isPresent: false,
                isCharging: false,
                isActivelyCharging: false,
                chargingPowerWatts: nil,
                displayValue: "—"
            )
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let isPresent = info[kIOPSIsPresentKey] as? Bool ?? false
            let isInternal = info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            guard isPresent, isInternal else { continue }

            if let current = info[kIOPSCurrentCapacityKey] as? Int {
                let powerSourceState = info[kIOPSPowerSourceStateKey] as? String
                let isOnACPower = powerSourceState == kIOPSACPowerValue
                let isActivelyCharging = info[kIOPSIsChargingKey] as? Bool ?? false
                let isPluggedIn = isOnACPower || isActivelyCharging
                let chargingPowerWatts: Int? = isPluggedIn ? readChargingPowerWatts() : nil
                return BatterySnapshot(
                    percentage: current,
                    isPresent: true,
                    isCharging: isActivelyCharging || isOnACPower,
                    isActivelyCharging: isActivelyCharging,
                    chargingPowerWatts: chargingPowerWatts,
                    displayValue: "\(current)"
                )
            }
        }

        return BatterySnapshot(
            percentage: nil,
            isPresent: false,
            isCharging: false,
            isActivelyCharging: false,
            chargingPowerWatts: nil,
            displayValue: "—"
        )
    }

    nonisolated private static func readChargingPowerWatts() -> Int {
        if let smcPower = SMCService.shared.dcInPower(), smcPower > 0 {
            return Int(smcPower.rounded())
        }

        if let watts = readSystemPowerInMilliwatts().flatMap(wattsFromMilliwatts) {
            return watts
        }

        if let watts = readSystemPowerFromCurrentVoltageMilliwatts().flatMap(wattsFromMilliwatts) {
            return watts
        }

        if let watts = readChargerPowerMilliwatts().flatMap(wattsFromMilliwatts) {
            return watts
        }

        // telemetry 短暂异常时显示 0W，避免用适配器额定功率造成“虚高后骤降”的错觉
        return 0
    }

    nonisolated private static func wattsFromMilliwatts(_ milliwatts: Int) -> Int? {
        guard milliwatts > 0 else { return nil }
        let watts = (milliwatts + 500) / 1000
        return watts > 0 ? watts : nil
    }

    nonisolated private static func readSystemPowerInMilliwatts() -> Int? {
        guard let service = matchingBatteryService() else { return nil }
        defer { IOObjectRelease(service) }

        guard let telemetry = IORegistryEntryCreateCFProperty(
            service,
            "PowerTelemetryData" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return positiveInt(from: telemetry["SystemPowerIn"], maxValue: 500_000)
    }

    nonisolated private static func readSystemPowerFromCurrentVoltageMilliwatts() -> Int? {
        guard let service = matchingBatteryService() else { return nil }
        defer { IOObjectRelease(service) }

        guard let telemetry = IORegistryEntryCreateCFProperty(
            service,
            "PowerTelemetryData" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any],
              let currentMilliAmps = positiveInt(from: telemetry["SystemCurrentIn"]),
              let voltageMilliVolts = positiveInt(from: telemetry["SystemVoltageIn"])
        else {
            return nil
        }

        return (currentMilliAmps * voltageMilliVolts) / 1000
    }

    nonisolated private static func readChargerPowerMilliwatts() -> Int? {
        guard let service = matchingBatteryService() else { return nil }
        defer { IOObjectRelease(service) }

        guard let chargerData = IORegistryEntryCreateCFProperty(
            service,
            "ChargerData" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any],
              let currentMilliAmps = positiveInt(from: chargerData["ChargingCurrent"]),
              let voltageMilliVolts = positiveInt(from: chargerData["ChargingVoltage"])
        else {
            return nil
        }

        return (currentMilliAmps * voltageMilliVolts) / 1000
    }

    nonisolated private static func matchingBatteryService() -> io_registry_entry_t? {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        return service == 0 ? nil : service
    }

    nonisolated private static func positiveInt(from value: Any?, maxValue: Int = Int.max) -> Int? {
        let rawValue: Int?
        if let intValue = value as? Int {
            rawValue = intValue
        } else if let number = value as? NSNumber {
            rawValue = number.intValue
        } else {
            rawValue = nil
        }

        guard let rawValue, rawValue > 0, rawValue <= maxValue else { return nil }
        return rawValue
    }
}

final class BatteryPowerSourceObserver {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (() -> Void)?

    func start(onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanagedSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let observer = Unmanaged<BatteryPowerSourceObserver>.fromOpaque(context).takeUnretainedValue()
            observer.onChange?()
        }, context) else {
            return
        }

        let source = unmanagedSource.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.runLoopSource = nil
        onChange = nil
    }

    deinit {
        stop()
    }
}
