import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot {
    let percentage: Int?
    let isCharging: Bool
    let chargingPowerWatts: Int?
    let displayValue: String

    nonisolated static let unavailable = BatterySnapshot(
        percentage: nil,
        isCharging: false,
        chargingPowerWatts: nil,
        displayValue: "—"
    )

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
            return .unavailable
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSIsPresentKey] as? Bool == true,
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int
            else { continue }

            let isOnACPower = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let isActivelyCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = isOnACPower || isActivelyCharging

            return BatterySnapshot(
                percentage: current,
                isCharging: isPluggedIn,
                chargingPowerWatts: isPluggedIn ? readChargingPowerWatts() : nil,
                displayValue: "\(current)"
            )
        }

        return .unavailable
    }

    /// 优先取 SMC 的 DC-IN 功率，其次退到电池服务的遥测数据；
    /// telemetry 短暂异常时返回 0W，避免用适配器额定功率造成「虚高后骤降」的错觉。
    nonisolated private static func readChargingPowerWatts() -> Int {
        if let smcPower = SMCService.shared.dcInPower(), smcPower > 0 {
            return Int(smcPower.rounded())
        }

        guard let service = matchingBatteryService() else { return 0 }
        defer { IOObjectRelease(service) }

        if let telemetry = registryDictionary(service, key: "PowerTelemetryData") {
            if let watts = positiveInt(telemetry["SystemPowerIn"], maxValue: 500_000).flatMap(wattsFromMilliwatts) {
                return watts
            }
            if let watts = milliwatts(current: telemetry["SystemCurrentIn"], voltage: telemetry["SystemVoltageIn"])
                .flatMap(wattsFromMilliwatts) {
                return watts
            }
        }

        if let charger = registryDictionary(service, key: "ChargerData"),
           let watts = milliwatts(current: charger["ChargingCurrent"], voltage: charger["ChargingVoltage"])
            .flatMap(wattsFromMilliwatts) {
            return watts
        }

        return 0
    }

    nonisolated private static func registryDictionary(
        _ service: io_registry_entry_t,
        key: String
    ) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    nonisolated private static func milliwatts(current: Any?, voltage: Any?) -> Int? {
        guard let currentMilliAmps = positiveInt(current), let voltageMilliVolts = positiveInt(voltage) else {
            return nil
        }
        return (currentMilliAmps * voltageMilliVolts) / 1000
    }

    nonisolated private static func wattsFromMilliwatts(_ milliwatts: Int) -> Int? {
        guard milliwatts > 0 else { return nil }
        let watts = (milliwatts + 500) / 1000
        return watts > 0 ? watts : nil
    }

    nonisolated private static func matchingBatteryService() -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        return service == 0 ? nil : service
    }

    nonisolated private static func positiveInt(_ value: Any?, maxValue: Int = Int.max) -> Int? {
        guard let rawValue = (value as? NSNumber)?.intValue, rawValue > 0, rawValue <= maxValue else {
            return nil
        }
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
