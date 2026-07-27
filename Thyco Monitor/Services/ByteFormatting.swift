import Foundation

enum ByteFormatting {
    nonisolated static func formatBytes(_ bytes: UInt64, decimals: Int = 1) -> String {
        let value = Double(bytes)
        switch value {
        case 1_099_511_627_776...:
            return String(format: "%.\(decimals)f TB", value / 1_099_511_627_776)
        case 1_073_741_824...:
            return String(format: "%.\(decimals)f GB", value / 1_073_741_824)
        case 1_048_576...:
            return String(format: "%.\(decimals)f MB", value / 1_048_576)
        case 1_024...:
            return String(format: "%.\(decimals)f KB", value / 1_024)
        default:
            return "\(bytes) B"
        }
    }

    nonisolated static func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        let absValue = abs(bytesPerSecond)
        switch absValue {
        case 1_073_741_824...:
            return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824)
        case 1_048_576...:
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        case 1_024...:
            return String(format: "%.0f KB/s", bytesPerSecond / 1_024)
        default:
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    /// 磁盘容量展示（1000 进制，与系统设置 / 柠檬清理一致）
    nonisolated static func formatDecimalGB(_ bytes: UInt64) -> String {
        let gb = Int((Double(bytes) / 1_000_000_000).rounded())
        return "\(gb) GB"
    }

    nonisolated static func formatTemperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        return String(format: "%.0f", celsius)
    }

    nonisolated static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f", value.rounded())
    }

    nonisolated static func formatRPM(_ rpm: Int?) -> String {
        guard let rpm else { return "—" }
        return "\(rpm)"
    }
}
