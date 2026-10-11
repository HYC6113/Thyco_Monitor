import Foundation

/// 一次快节拍采集到的全部指标
struct FastMetricsSample {
    let hardware: HardwareSnapshot
    let network: NetworkSnapshot
    let cpu: CPUSnapshot
    let memory: MemorySnapshot
    let battery: BatterySnapshot
    /// 重置后的首个样本只为 CPU / 网络建立差分基线，这两项读数无效；其余指标正常可用。
    let isBaseline: Bool

    nonisolated static func collect(isBaseline: Bool = false) -> FastMetricsSample {
        FastMetricsSample(
            hardware: HardwareMonitor.snapshot(),
            network: NetworkMonitor.snapshot(),
            cpu: CPUMonitor.snapshot(),
            memory: MemoryMonitor.snapshot(),
            battery: BatteryMonitor.snapshot(),
            isBaseline: isBaseline
        )
    }
}

/// 指标轮询节拍。采样直接在各自的串行队列上完成，回调携带结果，主线程只负责写入界面状态。
/// `DispatchSourceTimer` 的事件处理器本身串行，因此无需额外的重入保护。
final class MonitorUpdateScheduler {
    /// 内存 / CPU / 网络 / 硬件：1s，与活动监视器刷新节奏接近
    private static let fastInterval: TimeInterval = 1.0
    /// 存储：5s；电池同时响应 IOPS 通知，音频由 CoreAudio 属性监听驱动
    private static let mediumInterval: TimeInterval = 5.0
    /// 启动时立即采一次基线样本，CPU / 网络的首个有效差值在这段间隔后给出，而不是等满一秒。
    private static let firstFastTickDelay: TimeInterval = 0.25

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
        // 与采样排在同一队列，确保上次已开始的采样结束后再重置差分基线，且先于首个节拍执行。
        fastQueue.async {
            CPUMonitor.resetBaseline()
            NetworkMonitor.resetBaseline()
            onFastTick(.collect(isBaseline: true))
        }
        fastTimer = makeTimer(on: fastQueue, interval: Self.fastInterval, initialDelay: Self.firstFastTickDelay) {
            onFastTick(.collect())
        }
        mediumTimer = makeTimer(on: mediumQueue, interval: Self.mediumInterval, initialDelay: 0) {
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
        initialDelay: TimeInterval,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // 默认零容差会阻止系统合并唤醒；给 10% 余量，刷新节奏肉眼无差别。
        timer.schedule(deadline: .now() + initialDelay, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }
}
