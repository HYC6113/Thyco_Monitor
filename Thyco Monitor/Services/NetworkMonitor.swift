import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

struct NetworkSnapshot {
    let isWifiConnected: Bool
    let uploadDisplay: String
    let downloadDisplay: String
}

/// 网络吞吐监控（参考 macstate / 柠檬清理状态栏：sysctl NET_RT_IFLIST2）
enum NetworkMonitor {
    nonisolated(unsafe) private static var previousUpload: UInt64 = 0
    nonisolated(unsafe) private static var previousDownload: UInt64 = 0
    nonisolated(unsafe) private static var previousTimestamp: TimeInterval = 0
    nonisolated(unsafe) private static var hasBaseline = false
    /// 复用的 sysctl 缓冲区，避免每秒重新分配接口列表内存
    nonisolated(unsafe) private static var sysctlBuffer: UnsafeMutablePointer<UInt8>?
    nonisolated(unsafe) private static var sysctlBufferCapacity: size_t = 0
    nonisolated private static let lock = NSLock()

    nonisolated static func snapshot() -> NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let (totalUp, totalDown) = readTotalBytes()
        let now = ProcessInfo.processInfo.systemUptime

        var upload: Double = 0
        var download: Double = 0

        if hasBaseline {
            let elapsed = now - previousTimestamp
            if elapsed > 0 {
                if totalUp >= previousUpload {
                    upload = Double(totalUp - previousUpload) / elapsed
                }
                if totalDown >= previousDownload {
                    download = Double(totalDown - previousDownload) / elapsed
                }
            }
        } else {
            hasBaseline = true
        }

        previousUpload = totalUp
        previousDownload = totalDown
        previousTimestamp = now

        return NetworkSnapshot(
            isWifiConnected: isWiFiConnected(),
            uploadDisplay: ByteFormatting.formatBytesPerSecond(upload),
            downloadDisplay: ByteFormatting.formatBytesPerSecond(download)
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
        guard let store = SCDynamicStoreCreate(nil, "com.thyco.monitor.network" as CFString, nil, nil) else {
            return false
        }

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

    nonisolated private static func readTotalBytes() -> (upload: UInt64, download: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: size_t = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return (0, 0)
        }

        if sysctlBufferCapacity < length {
            sysctlBuffer?.deallocate()
            sysctlBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
            sysctlBufferCapacity = length
        }

        guard let buffer = sysctlBuffer,
              sysctl(&mib, UInt32(mib.count), buffer, &length, nil, 0) == 0 else {
            return (0, 0)
        }

        var totalUpload: UInt64 = 0
        var totalDownload: UInt64 = 0
        var cursor = buffer
        let end = buffer.advanced(by: length)

        while cursor < end {
            let header = cursor.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0 else { break }

            if header.ifm_type == UInt8(RTM_IFINFO2) {
                let interfaceInfo = cursor.withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                let socketAddress = cursor
                    .advanced(by: MemoryLayout<if_msghdr2>.size)
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
