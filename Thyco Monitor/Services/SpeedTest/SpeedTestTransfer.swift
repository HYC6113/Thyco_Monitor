import Foundation

/// 小于一秒的滑动窗口；只保留近期计数，停滞时正常产生 0。
nonisolated struct SpeedTestThroughputWindow {
    static let span: TimeInterval = 0.9

    private var samples: [(bytes: Int64, elapsed: TimeInterval)] = [(0, 0)]

    mutating func append(bytes: Int64, elapsed: TimeInterval) -> Double? {
        samples.append((bytes, elapsed))
        samples.removeAll { elapsed - $0.elapsed > Self.span }
        guard let first = samples.first, elapsed - first.elapsed >= 0.25 else { return nil }
        return SpeedTestMath.megabitsPerSecond(bytes: bytes - first.bytes, seconds: elapsed - first.elapsed)
    }
}

/// URLSession 回调与采样任务跨线程访问状态；所有可变字段均由 lock 保护。
/// 仅此 Foundation delegate 桥接需要 unchecked Sendable，引擎自身由编译器检查。
nonisolated final class SpeedTestTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Direction: Sendable { case download, upload }

    struct Snapshot: Sendable {
        let totalBytes: Int64
        let measuredBytes: Int64
        let hasAcceptedResponse: Bool
    }

    private let direction: Direction
    private let measurementStart: ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    private let lock = NSLock()
    private var totalBytes: Int64 = 0
    private var measuredBytes: Int64 = 0
    private var hasAcceptedResponse = false
    private var isStopped = false
    private var running: [Int: (task: URLSessionTask, continuation: CheckedContinuation<Void, Error>)] = [:]

    init(direction: Direction, measurementStart: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
        self.direction = direction
        self.measurementStart = measurementStart
        self.deadline = deadline
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(totalBytes: totalBytes, measuredBytes: measuredBytes, hasAcceptedResponse: hasAcceptedResponse)
    }

    func run(_ task: URLSessionTask) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                // 取消可能在前面的检查后完成 delegate 回调；登记等待者前须在锁内再核对。
                guard !isStopped, !Task.isCancelled else {
                    lock.unlock()
                    continuation.resume(throwing: URLError(.cancelled))
                    return
                }
                running[task.taskIdentifier] = (task, continuation)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// 到期时取消在途请求并拒绝后续请求。会话必须等全部子任务结束后再失效：
    /// 在已失效的 URLSession 上创建任务会抛出 Objective-C 异常。
    func stop() {
        lock.lock()
        isStopped = true
        let tasks = running.values.map(\.task)
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            try SpeedTestEngine.validate(response)
            if direction == .download {
                lock.lock()
                hasAcceptedResponse = true
                lock.unlock()
            }
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if direction == .download { noteBytes(Int64(data.count)) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        if direction == .upload { noteBytes(bytesSent) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error> = Result {
            // HTTP 非 2xx 可能同时带 cancelled；应优先保留服务端拒绝原因。
            if let response = task.response { try SpeedTestEngine.validate(response) }
            if let error { throw error }
            guard task.response != nil else { throw URLError(.badServerResponse) }
        }
        lock.lock()
        let continuation = running.removeValue(forKey: task.taskIdentifier)?.continuation
        if case .success = result, direction == .upload { hasAcceptedResponse = true }
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func noteBytes(_ count: Int64) {
        let now = ContinuousClock.now
        guard now < deadline else { return }
        lock.lock()
        totalBytes += count
        if now >= measurementStart { measuredBytes += count }
        lock.unlock()
    }
}
