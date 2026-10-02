import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

struct NetworkSnapshot {
    let isWifiConnected: Bool
    let uploadDisplay: String
    let downloadDisplay: String
}

/// 只让成功读取的连续快照参与差分，读数失败或计数重置时重新建立基线。
nonisolated struct NetworkRateSampler {
    private var previous: (upload: UInt64, download: UInt64, timestamp: TimeInterval)?

    mutating func sample(
        totals: (upload: UInt64, download: UInt64)?,
        timestamp: TimeInterval
    ) -> (upload: Double, download: Double) {
        guard let totals else {
            previous = nil
            return (0, 0)
        }
        defer { previous = (totals.upload, totals.download, timestamp) }
        guard let previous, timestamp > previous.timestamp else { return (0, 0) }
        let elapsed = timestamp - previous.timestamp
        return (
            totals.upload >= previous.upload ? Double(totals.upload - previous.upload) / elapsed : 0,
            totals.download >= previous.download ? Double(totals.download - previous.download) / elapsed : 0
        )
    }
}

/// 网络吞吐监控（参考 macstate / 柠檬清理状态栏：sysctl NET_RT_IFLIST2）
enum NetworkMonitor {
    nonisolated(unsafe) private static var sampler = NetworkRateSampler()
    /// 复用的 sysctl 缓冲区，避免每秒重新分配接口列表内存
    nonisolated(unsafe) private static var sysctlBuffer: UnsafeMutablePointer<UInt8>?
    nonisolated(unsafe) private static var sysctlBufferCapacity: size_t = 0
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

        let rate = sampler.sample(totals: readTotalBytes(), timestamp: ProcessInfo.processInfo.systemUptime)

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

    nonisolated private static func readTotalBytes() -> (upload: UInt64, download: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: size_t = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        if sysctlBufferCapacity < length {
            sysctlBuffer?.deallocate()
            sysctlBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
            sysctlBufferCapacity = length
        }

        guard let buffer = sysctlBuffer,
              sysctl(&mib, UInt32(mib.count), buffer, &length, nil, 0) == 0 else {
            return nil
        }

        var totalUpload: UInt64 = 0
        var totalDownload: UInt64 = 0
        var cursor = buffer
        let end = buffer.advanced(by: length)
        let headerSize = MemoryLayout<if_msghdr>.stride
        let interfaceInfoSize = MemoryLayout<if_msghdr2>.stride + MemoryLayout<sockaddr_dl>.stride

        while end - cursor >= headerSize {
            let header = cursor.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            let messageLength = Int(header.ifm_msglen)
            guard messageLength >= headerSize, messageLength <= end - cursor else { break }

            if header.ifm_type == UInt8(RTM_IFINFO2), messageLength >= interfaceInfoSize {
                let interfaceInfo = cursor.withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                let socketAddress = cursor
                    .advanced(by: MemoryLayout<if_msghdr2>.stride)
                    .withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }

                if isEthernetInterfaceName(socketAddress) {
                    totalDownload &+= interfaceInfo.ifm_data.ifi_ibytes
                    totalUpload &+= interfaceInfo.ifm_data.ifi_obytes
                }
            }

            cursor = cursor.advanced(by: messageLength)
        }

        return (totalUpload, totalDownload)
    }

    /// 只统计 `en*` 物理网卡；直接比对首两个字节，避免每秒为每个接口构造 Data 与 String。
    nonisolated private static func isEthernetInterfaceName(_ socketAddress: sockaddr_dl) -> Bool {
        guard socketAddress.sdl_nlen >= 2 else { return false }
        var address = socketAddress
        return withUnsafeBytes(of: &address.sdl_data) { name in
            name[0] == UInt8(ascii: "e") && name[1] == UInt8(ascii: "n")
        }
    }
}
