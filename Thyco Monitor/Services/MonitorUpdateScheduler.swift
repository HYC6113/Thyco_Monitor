import Foundation

/// 一次快节拍采集到的全部指标
struct FastMetricsSample {
    let hardware: HardwareSnapshot
    let network: NetworkSnapshot
    let cpu: CPUSnapshot
    let memory: MemorySnapshot
    let battery: BatterySnapshot

    nonisolated static func collect() -> FastMetricsSample {
        FastMetricsSample(
            hardware: HardwareMonitor.snapshot(),
            network: NetworkMonitor.snapshot(),
            cpu: CPUMonitor.snapshot(),
            memory: MemoryMonitor.snapshot(),
            battery: BatteryMonitor.snapshot()
        )
    }
}

/// 指标轮询节拍。采样直接在各自的串行队列上完成，回调携带结果，主线程只负责写入界面状态。
/// `DispatchSourceTimer` 的事件处理器本身串行，因此无需额外的重入保护。
final class MonitorUpdateScheduler {
    /// 内存 / CPU / 网络 / 硬件：1s，与活动监视器刷新节奏接近
    private static let fastInterval: TimeInterval = 1.0
    /// 存储：5s；电池由 IOPS 电源变化通知驱动，音频由 CoreAudio 属性监听驱动
    private static let mediumInterval: TimeInterval = 5.0

    /// 拆成两条队列，避免存储采样阻塞快节拍
    private let fastQueue = DispatchQueue(label: "com.thyco.monitor.scheduler.fast", qos: .utility)
    private let mediumQueue = DispatchQueue(label: "com.thyco.monitor.scheduler.medium", qos: .utility)

    private var fastTimer: DispatchSourceTimer?
    private var mediumTimer: DispatchSourceTimer?

    func start(
        onFastTick: @escaping @Sendable (FastMetricsSample) -> Void,
        onMediumTick: @escaping @Sendable (StorageSnapshot) -> Void
    ) {
        stop()
        fastTimer = makeTimer(on: fastQueue, interval: Self.fastInterval) {
            onFastTick(.collect())
        }
        mediumTimer = makeTimer(on: mediumQueue, interval: Self.mediumInterval) {
            onMediumTick(StorageMonitor.snapshot())
        }
    }

    func stop() {
        fastTimer?.cancel()
        mediumTimer?.cancel()
        fastTimer = nil
        mediumTimer = nil
    }

    deinit {
        stop()
    }

    private func makeTimer(
        on queue: DispatchQueue,
        interval: TimeInterval,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }
}
