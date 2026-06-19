import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

struct NetworkSnapshot {
    let isWifiConnected: Bool
    let uploadSpeed: Double
    let downloadSpeed: Double
    let uploadDisplay: String
    let downloadDisplay: String
}

/// 网络吞吐监控（参考 macstate / 柠檬清理状态栏：sysctl NET_RT_IFLIST2）
enum NetworkMonitor {
    nonisolated(unsafe) private static var previousUpload: UInt64 = 0
    nonisolated(unsafe) private static var previousDownload: UInt64 = 0
    nonisolated(unsafe) private static var previousTimestamp: TimeInterval = 0
    nonisolated(unsafe) private static var hasBaseline = false
    nonisolated(unsafe) private static var lock = NSLock()
    nonisolated(unsafe) private static var sysctlBuffer: UnsafeMutablePointer<UInt8>?
    nonisolated(unsafe) private static var sysctlBufferCapacity: size_t = 0
    nonisolated(unsafe) private static var bufferLock = NSLock()

    nonisolated static func snapshot() -> NetworkSnapshot {
        let (totalUp, totalDown) = readTotalBytes()
        let now = ProcessInfo.processInfo.systemUptime

        lock.lock()
        defer { lock.unlock() }

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
            uploadSpeed: upload,
            downloadSpeed: download,
            uploadDisplay: ByteFormatting.formatBytesPerSecond(upload),
            downloadDisplay: ByteFormatting.formatBytesPerSecond(download)
        )
    }

    nonisolated private static func isWiFiConnected() -> Bool {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return false
        }

        // serviceActive() 仅表示 Wi-Fi 服务/射频已打开，不能代表已关联到某个 AP。
        if interface.wlanChannel() != nil {
            return true
        }

        if interface.activePHYMode() != .modeNone {
            return true
        }

        if let ssid = interface.ssid(), !ssid.isEmpty {
            return true
        }

        return wifiAssociatedViaDynamicStore(interfaceName: interface.interfaceName ?? "en0")
    }

    /// 通过 SystemConfiguration 读取 AirPort 状态；不依赖定位权限，CHANNEL 仅在已关联时出现。
    nonisolated private static func wifiAssociatedViaDynamicStore(interfaceName: String) -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "com.hyco.monitor.network" as CFString, nil, nil) else {
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

        bufferLock.lock()
        if sysctlBufferCapacity < length {
            sysctlBuffer?.deallocate()
            sysctlBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
            sysctlBufferCapacity = length
        }
        guard let buffer = sysctlBuffer else {
            bufferLock.unlock()
            return (0, 0)
        }

        guard sysctl(&mib, UInt32(mib.count), buffer, &length, nil, 0) == 0 else {
            bufferLock.unlock()
            return (0, 0)
        }
        bufferLock.unlock()

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
                    .withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0 }
                let nameLength = Int(socketAddress.pointee.sdl_nlen)

                if nameLength > 0 {
                    var socketData = socketAddress.pointee
                    let nameData = Data(bytes: &socketData.sdl_data, count: nameLength)
                    if let name = String(data: nameData, encoding: .ascii), name.hasPrefix("en") {
                        totalDownload &+= interfaceInfo.ifm_data.ifi_ibytes
                        totalUpload &+= interfaceInfo.ifm_data.ifi_obytes
                    }
                }
            }

            cursor = cursor.advanced(by: messageLength)
        }

        return (totalUpload, totalDownload)
    }
}
