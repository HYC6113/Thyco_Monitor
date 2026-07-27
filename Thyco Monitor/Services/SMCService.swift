import Foundation
import IOKit

/// SMC 读取服务（参考 macstate / iStat Menus 同类实现：AppleSMC + 数据类型解析）
final class SMCService: @unchecked Sendable {
    nonisolated(unsafe) static var shared = SMCService()

    private let lock = NSLock()
    nonisolated(unsafe) private var connection: io_connect_t = 0
    private let kernelIndex: UInt32 = 2

    private let intelTemperatureKeys = ["TC0P", "TC0D", "TC0E", "TC0F"]
    private let appleSiliconTemperatureKeys = ["Tp09", "Tp0T", "Tp01", "Tp05"]
    nonisolated(unsafe) private var validTemperatureKey: String?

    private init() {
        openConnection()
    }

    deinit {
        closeConnection()
    }

    nonisolated func cpuTemperatureCelsius() -> Double? {
        if let key = validTemperatureKey {
            if let value = readNumericValue(forKey: key), value > 0, value < 150 {
                return value
            }
        }
        
        for key in intelTemperatureKeys + appleSiliconTemperatureKeys {
            if let value = readNumericValue(forKey: key), value > 0, value < 150 {
                validTemperatureKey = key
                return value
            }
        }
        return nil
    }

    nonisolated func primaryFanRPM() -> Int? {
        let count = fanCount()
        guard count > 0 else { return nil }

        var maxRPM: Double = 0
        for index in 0..<count {
            if let rpm = readNumericValue(forKey: String(format: "F%dAc", index)), rpm > maxRPM {
                maxRPM = rpm
            }
        }
        return maxRPM > 0 ? Int(maxRPM.rounded()) : 0
    }

    nonisolated func allFanSpeeds() -> [(current: Double, min: Double, max: Double)] {
        let count = fanCount()
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            (
                current: readNumericValue(forKey: String(format: "F%dAc", index)) ?? 0,
                min: readNumericValue(forKey: String(format: "F%dMn", index)) ?? 0,
                max: readNumericValue(forKey: String(format: "F%dMx", index)) ?? 0
            )
        }
    }

    nonisolated func dcInPower() -> Double? {
        if let pdtr = readNumericValue(forKey: "PDTR"), pdtr > 0 {
            return pdtr
        }
        if let v = readNumericValue(forKey: "VD0R"), let i = readNumericValue(forKey: "ID0R"), v > 0, i > 0 {
            return v * i
        }
        return nil
    }

    nonisolated(unsafe) private var cachedFanCount: Int?

    nonisolated private func fanCount() -> Int {
        if let cached = cachedFanCount { return cached }
        guard let result = readValue(forKey: "FNum") else { return 0 }

        let count: Int
        switch result.dataType {
        case "ui8 ":
            count = Int(result.bytes[0])
        case "ui16":
            guard result.bytes.count >= 2 else { return 0 }
            let raw = (UInt16(result.bytes[0]) << 8) | UInt16(result.bytes[1])
            count = Int(raw)
        default:
            count = Int(parseNumericValue(bytes: result.bytes, dataType: result.dataType) ?? 0)
        }
        
        cachedFanCount = count
        return count
    }

    nonisolated private func openConnection() {
        lock.lock()
        defer { lock.unlock() }

        guard connection == 0 else { return }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &openedConnection) == KERN_SUCCESS else { return }
        connection = openedConnection
    }

    nonisolated private func closeConnection() {
        lock.lock()
        defer { lock.unlock() }

        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    nonisolated private func readNumericValue(forKey key: String) -> Double? {
        guard let value = readValue(forKey: key) else { return nil }
        return parseNumericValue(bytes: value.bytes, dataType: value.dataType)
    }

    nonisolated private func readValue(forKey key: String) -> SMCReadResult? {
        lock.lock()
        defer { lock.unlock() }

        guard connection != 0, let encodedKey = encodeSMCKey(key) else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = encodedKey
        input.data8 = SMCCommand.readKeyInfo.rawValue
        guard callSMC(input: &input, output: &output) else { return nil }

        let keyInfo = output.keyInfo
        guard keyInfo.dataSize > 0, keyInfo.dataSize <= 32 else { return nil }

        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue
        guard callSMC(input: &input, output: &output) else { return nil }

        let count = Int(keyInfo.dataSize)
        return SMCReadResult(
            dataType: decodeSMCType(keyInfo.dataType),
            bytes: Array(output.bytesArray.prefix(count))
        )
    }

    nonisolated private func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(connection, kernelIndex, &input, inputSize, &output, &outputSize) == KERN_SUCCESS
    }

    nonisolated private func parseNumericValue(bytes: [UInt8], dataType: String) -> Double? {
        guard !bytes.isEmpty else { return nil }

        switch dataType {
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            var value: Float = 0
            var bytesCopy = Array(bytes.prefix(4))
            memcpy(&value, &bytesCopy, 4)
            return value.isFinite ? Double(value) : nil
        case "ui8 ":
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw)
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(raw)
        case "si8 ":
            return Double(Int8(bitPattern: bytes[0]))
        case "si16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw))
        default:
            if bytes.count >= 2 {
                let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                let temp = Double(raw) / 256.0
                if temp > 0, temp < 150 { return temp }
            }
            return nil
        }
    }

    nonisolated private func encodeSMCKey(_ key: String) -> UInt32? {
        guard key.utf8.count == 4 else { return nil }
        return key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    nonisolated private func decodeSMCType(_ raw: UInt32) -> String {
        let chars = [
            Character(UnicodeScalar((raw >> 24) & 0xFF) ?? " "),
            Character(UnicodeScalar((raw >> 16) & 0xFF) ?? " "),
            Character(UnicodeScalar((raw >> 8) & 0xFF) ?? " "),
            Character(UnicodeScalar(raw & 0xFF) ?? " ")
        ]
        return String(chars)
    }
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCReadResult {
    let dataType: String
    let bytes: [UInt8]
}

private struct SMCKeyDataVers: Sendable {
    nonisolated init() {}
    var major: CUnsignedChar = 0
    var minor: CUnsignedChar = 0
    var build: CUnsignedChar = 0
    var reserved: CUnsignedChar = 0
    var release: CUnsignedShort = 0
}

private struct SMCKeyDataPLimitData: Sendable {
    nonisolated init() {}
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyDataKeyInfo: Sendable {
    nonisolated init() {}
    var dataSize: IOByteCount32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData: Sendable {
    nonisolated init() {}
    var key: UInt32 = 0
    var vers: SMCKeyDataVers = SMCKeyDataVers()
    var pLimitData: SMCKeyDataPLimitData = SMCKeyDataPLimitData()
    var keyInfo: SMCKeyDataKeyInfo = SMCKeyDataKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    nonisolated var bytesArray: [UInt8] {
        [
            bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15,
            bytes.16, bytes.17, bytes.18, bytes.19, bytes.20, bytes.21, bytes.22, bytes.23,
            bytes.24, bytes.25, bytes.26, bytes.27, bytes.28, bytes.29, bytes.30, bytes.31
        ]
    }
}
