import Foundation

final class MonitorUpdateScheduler {
    private var fastTimer: DispatchSourceTimer?
    private var mediumTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.hyco.monitor.scheduler", qos: .utility)

    var onFastTick: (() -> Void)?
    var onMediumTick: (() -> Void)?

    func start() {
        stop()
        // 内存 / CPU / 网络 / 硬件：1s，与活动监视器刷新节奏接近
        fastTimer = makeTimer(interval: 1.0, handler: { [weak self] in self?.onFastTick?() })
        // 存储：5s；电池由 IOPS 电源变化通知驱动，音频由 CoreAudio 属性监听驱动
        mediumTimer = makeTimer(interval: 5.0, handler: { [weak self] in self?.onMediumTick?() })

        onFastTick?()
        onMediumTick?()
    }

    func stop() {
        fastTimer?.cancel()
        mediumTimer?.cancel()
        fastTimer = nil
        mediumTimer = nil
    }

    private func makeTimer(interval: TimeInterval, handler: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

    deinit {
        stop()
    }
}
