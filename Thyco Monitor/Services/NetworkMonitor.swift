import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

struct NetworkSnapshot {
    let isWifiConnected: Bool
    let uploadDisplay: String
    let downloadDisplay: String
}

typealias NetworkInterfaceCounters = [UInt32: (upload: UInt64, download: UInt64)]

/// 逐接口计算差值；读取失败或计数器重置时重新建立基线。
nonisolated struct NetworkRateSampler {
    private var previous: (interfaces: NetworkInterfaceCounters, timestamp: TimeInterval)?

    mutating func sample(
        interfaces: NetworkInterfaceCounters?,
        timestamp: TimeInterval
    ) -> (upload: Double, download: Double) {
        guard let interfaces else {
            previous = nil
            return (0, 0)
        }

        defer { previous = (interfaces, timestamp) }
        guard let previous, timestamp > previous.timestamp else {
            return (0, 0)
        }

        let elapsed = timestamp - previous.timestamp
        var uploadBytes: Double = 0
        var downloadBytes: Double = 0
        for (index, current) in interfaces {
            guard let old = previous.interfaces[index] else { continue }
            if current.upload >= old.upload {
                uploadBytes += Double(current.upload - old.upload)
            }
            if current.download >= old.download {
                downloadBytes += Double(current.download - old.download)
            }
        }

        return (uploadBytes / elapsed, downloadBytes / elapsed)
    }
}

/// 网络吞吐监控：读取接口累计字节数并按采样间隔计算速率。
enum NetworkMonitor {
    nonisolated(unsafe) private static var sampler = NetworkRateSampler()
    /// 由 lock 保护，复用内核接口列表的存储空间。
    nonisolated(unsafe) private static var interfaceBuffer: [UInt8] = []
    nonisolated private static let lock = NSLock()
    /// Wi-Fi 未关联时每秒都会走到动态存储回退路径，会话只建一次。
    nonisolated(unsafe) private static let dynamicStore = SCDynamicStoreCreate(
        nil, "com.thyco.monitor.network" as CFString, nil, nil
    )

    nonisolated static func resetBaseline() {
        lock.lock()
        defer { lock.unlock() }
        sampler = NetworkRateSampler()
    }

    nonisolated static func snapshot() -> NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let rate = sampler.sample(
            interfaces: readInterfaceBytes(),
            timestamp: ProcessInfo.processInfo.systemUptime
        )

        return NetworkSnapshot(
            isWifiConnected: isWiFiConnected(),
            uploadDisplay: ByteFormatting.formatBytesPerSecond(rate.upload),
            downloadDisplay: ByteFormatting.formatBytesPerSecond(rate.download)
        )
    }

    nonisolated private static func isWiFiConnected() -> Bool {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return false
        }

        // 以 wlanChannel / 动态 store 的 CHANNEL 为准；不用 serviceActive() 或 activePHYMode()。
        if interface.wlanChannel() != nil {
            return true
        }

        if let ssid = interface.ssid(), !ssid.isEmpty {
            return true
        }

        return wifiAssociatedViaDynamicStore(interfaceName: interface.interfaceName ?? "en0")
    }

    /// 通过 SystemConfiguration 读取 AirPort 状态；不依赖定位权限，CHANNEL 仅在已关联时出现。
    nonisolated private static func wifiAssociatedViaDynamicStore(interfaceName: String) -> Bool {
        guard let store = dynamicStore else { return false }

        let key = "State:/Network/Interface/\(interfaceName)/AirPort" as CFString
        guard let info = SCDynamicStoreCopyValue(store, key) as? [String: Any] else {
            return false
        }

        if info["CHANNEL"] != nil {
            return true
        }

        if let ssid = info["SSID_STR"] as? String, !ssid.isEmpty {
            return true
        }

        if let ssidData = info["SSID"] as? Data, !ssidData.isEmpty {
            return true
        }

        return false
    }

    nonisolated private static func readInterfaceBytes() -> NetworkInterfaceCounters? {
        // getifaddrs 的 if_data 只有 32 位字节计数，必须使用 NET_RT_IFLIST2 的 if_data64。
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        if interfaceBuffer.count < length {
            interfaceBuffer = [UInt8](repeating: 0, count: length)
        }
        return interfaceBuffer.withUnsafeMutableBytes { buffer in
            var received = buffer.count
            guard sysctl(&mib, UInt32(mib.count), buffer.baseAddress, &received, nil, 0) == 0 else { return nil }
            return NetworkInterfaceReader.decode(UnsafeRawBufferPointer(rebasing: buffer[..<received]))
        }
    }
}

/// 解析内核变长路由消息，保留接口索引和完整的 64 位计数。
nonisolated enum NetworkInterfaceReader {
    static func decode(_ buffer: UnsafeRawBufferPointer) -> NetworkInterfaceCounters? {
        var counters: NetworkInterfaceCounters = [:]
        var offset = 0
        // 路由消息共享长度 UInt16、版本 UInt8、类型 UInt8 前缀；地址消息比 if_msghdr 短。
        let headerSize = 4
        let infoSize = MemoryLayout<if_msghdr2>.stride
        while offset < buffer.count {
            guard buffer.count - offset >= headerSize else { return nil }
            let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            guard length >= headerSize, length <= buffer.count - offset else { return nil }
            if buffer[offset + 3] == UInt8(RTM_IFINFO2) {
                guard length >= infoSize + MemoryLayout<sockaddr_dl>.size else { return nil }
                let info = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var address = buffer.loadUnaligned(fromByteOffset: offset + infoSize, as: sockaddr_dl.self)
                let isEthernet = address.sdl_family == UInt8(AF_LINK) && address.sdl_nlen >= 2
                    && withUnsafeBytes(of: &address.sdl_data) { $0[0] == UInt8(ascii: "e") && $0[1] == UInt8(ascii: "n") }
                if isEthernet {
                    counters[UInt32(info.ifm_index)] = (info.ifm_data.ifi_obytes, info.ifm_data.ifi_ibytes)
                }
            }
            offset += length
        }
        return counters
    }
}
