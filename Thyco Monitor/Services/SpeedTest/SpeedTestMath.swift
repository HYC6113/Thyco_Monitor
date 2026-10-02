import Foundation

nonisolated enum SpeedTestMath {
    /// 表盘刻度（MB/s）。位置等间距，数值本身不是线性的。
    static let gaugeMarks: [Double] = [0, 1, 2, 5, 10, 25, 50, 75, 100]

    /// 把实时速度映到刻度上。正好落在某个数字上，两档之间按数值线性补间；超过 100 MB/s 顶在最右。
    static func gaugeFraction(megabits: Double) -> Double {
        guard megabits.isFinite, megabits > 0 else { return 0 }
        let megabytes = megabits / 8
        let marks = gaugeMarks
        let last = marks.count - 1
        if megabytes >= marks[last] { return 1 }
        for index in 0..<last {
            let upper = marks[index + 1]
            guard megabytes <= upper else { continue }
            let lower = marks[index]
            let span = upper - lower
            let local = span > 0 ? (megabytes - lower) / span : 0
            return (Double(index) + local) / Double(last)
        }
        return 1
    }

    static func megabitsPerSecond(bytes: Int64, seconds: TimeInterval) -> Double {
        guard bytes > 0, seconds > 0.05 else { return 0 }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    /// HTTP 延迟取中位数；抖动按原采样顺序计算相邻差的平均值。
    static func pingAndJitter(samples: [Double]) -> (ping: Double, jitter: Double)? {
        let clean = samples.filter { $0.isFinite && $0 > 0 }
        guard !clean.isEmpty else { return nil }
        let sorted = clean.sorted()
        let middle = sorted.count / 2
        let ping = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        guard clean.count >= 2 else { return (ping, 0) }
        var total = 0.0
        for index in 1..<clean.count {
            total += abs(clean[index] - clean[index - 1])
        }
        return (ping, total / Double(clean.count - 1))
    }

    /// 线性插值分位数，`fraction` 取 0...1。
    static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = fraction * Double(sorted.count - 1)
        let lower = Int(rank)
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
    }

    static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    /// 每路上传以约半秒一块为目标，每次最多翻倍；尺寸有界且不随网速无限分配。
    static func nextUploadSize(current: Int, elapsed: TimeInterval) -> Int {
        let ratio = min(2, max(0.5, 0.5 / max(elapsed, 0.001)))
        return min(4 * 1024 * 1024, max(16 * 1024, Int(Double(current) * ratio)))
    }

    /// 把测速用的 Mbps 换成字节速率。满 1 MB/s 用 MB/s，否则用 KB/s。
    /// Mbps 本身是十进制，所以这里按 1000 进位：1 MB/s = 8 Mbps。
    static func formatByteRate(megabits: Double?) -> (value: String, unit: String) {
        guard let megabits, megabits.isFinite, megabits >= 0 else {
            return ("—", "MB/s")
        }
        let bytesPerSecond = megabits * 125_000
        if bytesPerSecond >= 1_000_000 {
            return (formatMagnitude(bytesPerSecond / 1_000_000), "MB/s")
        }
        return (formatMagnitude(bytesPerSecond / 1_000), "KB/s")
    }

    private static func formatMagnitude(_ value: Double) -> String {
        if value <= 0 { return "0" }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        if value >= 0.01 { return String(format: "%.2f", value) }
        return "0.01"
    }

    static func formatMilliseconds(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        if value >= 100 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
