import Foundation
import IOKit

/// SMC 读取服务（参考 macstate / iStat Menus 同类实现：AppleSMC + 数据类型解析）
final class SMCService: @unchecked Sendable {
    nonisolated static let shared = SMCService()

    /// Intel 与 Apple Silicon 的 CPU 温度键，按优先级依次探测
    nonisolated private static let temperatureKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "Tp09", "Tp0T", "Tp01", "Tp05"]

    private let lock = NSLock()
    private let kernelIndex: UInt32 = 2
    nonisolated(unsafe) private var connection: io_connect_t = 0
    nonisolated(unsafe) private var validTemperatureKey: String?
    nonisolated(unsafe) private var cachedFanCount: Int?

    private init() {
        openConnection()
    }

    deinit {
        closeConnection()
    }

    nonisolated func cpuTemperatureCelsius() -> Double? {
        if let key = validTemperatureKey, let value = plausibleTemperature(forKey: key) {
            return value
        }

        for key in Self.temperatureKeys {
            if let value = plausibleTemperature(forKey: key) {
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
            if let rpm = readNumericValue(forKey: "F\(index)Ac"), rpm > maxRPM {
                maxRPM = rpm
            }
        }
        return maxRPM > 0 ? Int(maxRPM.rounded()) : 0
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

    nonisolated private func plausibleTemperature(forKey key: String) -> Double? {
        guard let value = readNumericValue(forKey: key), value > 0, value < 150 else { return nil }
        return value
    }

    nonisolated private func fanCount() -> Int {
        if let cached = cachedFanCount { return cached }
        let count = Int(readNumericValue(forKey: "FNum") ?? 0)
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

        return withUnsafeBytes(of: output.bytes) { bytes in
            parseNumericValue(bytes: bytes, count: Int(keyInfo.dataSize), dataType: keyInfo.dataType)
        }
    }

    nonisolated private func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(connection, kernelIndex, &input, inputSize, &output, &outputSize) == KERN_SUCCESS
    }

    nonisolated private func parseNumericValue(
        bytes: UnsafeRawBufferPointer,
        count: Int,
        dataType: UInt32
    ) -> Double? {
        guard count > 0 else { return nil }

        func bigEndianUInt16() -> UInt16? {
            guard count >= 2 else { return nil }
            return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        }

        switch dataType {
        case SMCDataType.sp78:
            return bigEndianUInt16().map { Double(Int16(bitPattern: $0)) / 256.0 }
        case SMCDataType.fpe2:
            return bigEndianUInt16().map { Double($0) / 4.0 }
        case SMCDataType.flt:
            guard count >= 4 else { return nil }
            let value = bytes.loadUnaligned(fromByteOffset: 0, as: Float.self)
            return value.isFinite ? Double(value) : nil
        case SMCDataType.ui8:
            return Double(bytes[0])
        case SMCDataType.ui16:
            return bigEndianUInt16().map(Double.init)
        case SMCDataType.ui32:
            guard count >= 4 else { return nil }
            let raw = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(raw)
        case SMCDataType.si8:
            return Double(Int8(bitPattern: bytes[0]))
        case SMCDataType.si16:
            return bigEndianUInt16().map { Double(Int16(bitPattern: $0)) }
        default:
            // 未知类型按 sp78 猜测，仅在结果落在合理温度区间时采信
            guard let raw = bigEndianUInt16() else { return nil }
            let temperature = Double(raw) / 256.0
            return (temperature > 0 && temperature < 150) ? temperature : nil
        }
    }

    nonisolated private func encodeSMCKey(_ key: String) -> UInt32? {
        guard key.utf8.count == 4 else { return nil }
        return key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

/// SMC 数据类型的 FourCharCode；直接比对整数，避免每次读取都解码成字符串。
private enum SMCDataType {
    static let sp78: UInt32 = 0x7370_3738 // "sp78"
    static let fpe2: UInt32 = 0x6670_6532 // "fpe2"
    static let flt: UInt32 = 0x666C_7420  // "flt "
    static let ui8: UInt32 = 0x7569_3820  // "ui8 "
    static let ui16: UInt32 = 0x7569_3136 // "ui16"
    static let ui32: UInt32 = 0x7569_3332 // "ui32"
    static let si8: UInt32 = 0x7369_3820  // "si8 "
    static let si16: UInt32 = 0x7369_3136 // "si16"
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
}
