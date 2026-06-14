import Foundation
import IOKit.ps

struct BatterySnapshot {
    let percentage: Int?
    let isPresent: Bool
    let isCharging: Bool
    let displayValue: String
}

enum BatteryMonitor {
    nonisolated static func snapshot() -> BatterySnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatterySnapshot(percentage: nil, isPresent: false, isCharging: false, displayValue: "—")
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
                let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
                return BatterySnapshot(
                    percentage: current,
                    isPresent: true,
                    isCharging: isCharging || isOnACPower,
                    displayValue: "\(current)"
                )
            }
        }

        return BatterySnapshot(percentage: nil, isPresent: false, isCharging: false, displayValue: "—")
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
