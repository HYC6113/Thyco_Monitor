import Foundation

nonisolated enum SpeedTestError: Error, Equatable {
    case noData
    case noServer
    case httpStatus(Int)
    case insufficientLatencySamples
}

nonisolated struct LatencyMeasurement: Sendable {
    let pingMilliseconds: Double
    let jitterMilliseconds: Double
}

/// 测量边界集中配置。生产路径留空端点，开测时向 Ookla 目录选择节点；测试可直接注入 URL。
nonisolated struct SpeedTestConfiguration: Sendable {
    var latencyURL: URL?
    var downloadURL: URL?
    var uploadURL: URL?
    var transferDuration: Duration = .seconds(8)
    var warmupDuration: Duration = .seconds(1)

    var usesFixedEndpoints: Bool {
        downloadURL != nil && uploadURL != nil
    }
}

/// 到指定 HTTP 端点的吞吐量与空闲延迟。无共享可变状态，每次传输拥有独立会话。
nonisolated struct SpeedTestEngine: Sendable {
    private let configuration: SpeedTestConfiguration
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration
    private let history: SpeedTestServerHistory
    private static let uploadPayload = Data(count: 4 * 1024 * 1024)

    init(
        configuration: SpeedTestConfiguration = SpeedTestConfiguration(),
        // 默认使用系统网络设置，以便测速能反映 macOS 当前启用的 HTTP/SOCKS 代理或直连路径。
        makeSessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { SpeedTestEngine.sessionConfiguration() },
        history: SpeedTestServerHistory = SpeedTestServerHistory()
    ) {
        precondition(configuration.transferDuration > configuration.warmupDuration)
        precondition(configuration.warmupDuration >= .zero)
        self.configuration = configuration
        self.makeSessionConfiguration = makeSessionConfiguration
        self.history = history
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"
        ]
        return configuration
    }

    /// 显式绕过系统 HTTP/SOCKS 代理，让目录和测速都从本机直连出口出去。
    /// 生产默认不使用此配置；它保留给需要强制直连的调用方和诊断场景。
    static func directSessionConfiguration() -> URLSessionConfiguration {
        let configuration = sessionConfiguration()
        configuration.connectionProxyDictionary = [:]
        return configuration
    }

    /// 固定端点直接返回；否则按延迟和历史成绩选出几台 Ookla 节点，再由试下载决定。
    func resolveServer() async throws -> SpeedTestServer {
        if configuration.usesFixedEndpoints {
            return SpeedTestServer(
                name: "",
                sponsor: "",
                countryCode: "",
                latencyURL: configuration.latencyURL ?? configuration.downloadURL!,
                downloadURL: configuration.downloadURL!,
                uploadURL: configuration.uploadURL!
            )
        }
        let sessionConfiguration = makeSessionConfiguration()
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let usesProxyRoute = OoklaServerDirectory.usesProxyRoute(for: sessionConfiguration)
        let ranked = try await OoklaServerDirectory.rankedServers(session: session, usesProxyRoute: usesProxyRoute)
        let finalists = SpeedTestServerHistory.finalists(ranked: ranked, megabits: history.megabits()) {
            SpeedTestServerHistory.key(for: $0, usesProxyRoute: usesProxyRoute)
        }
        return try await fastestByTrial(finalists)
    }

    /// 记下正式测速的下载成绩，供之后选服参考。固定端点不记录。
    func recordDownload(_ megabits: Double, on server: SpeedTestServer) {
        guard !configuration.usesFixedEndpoints else { return }
        let usesProxyRoute = OoklaServerDirectory.usesProxyRoute(for: makeSessionConfiguration())
        history.record(megabits, for: SpeedTestServerHistory.key(for: server, usesProxyRoute: usesProxyRoute))
    }

    func clearServerHistory() {
        history.clear()
    }

    private static let trialFirstByteTimeout: Duration = .seconds(1)
    private static let trialRampDuration: Duration = .milliseconds(400)
    private static let trialWindowDuration: Duration = .seconds(1)

    /// 延迟最低不等于吞吐最高：候选同时试下载，取稳定阶段收到字节最多的一台。
    /// 试测都没有数据时退回第一台。`finalists` 延迟低的在前且非空。
    func fastestByTrial(_ finalists: [SpeedTestServer]) async throws -> SpeedTestServer {
        guard finalists.count > 1 else { return finalists[0] }
        let received = await withTaskGroup(of: (Int, Int64).self) { group in
            for (index, server) in finalists.enumerated() {
                group.addTask { (index, await trialBytes(from: server.downloadURL)) }
            }
            var results: [(Int, Int64)] = []
            for await result in group { results.append(result) }
            return results
        }
        try Task.checkCancellation()
        // 字节相同取排在前面的一台。
        let best = received.max { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 > $1.0) }
        guard let best, best.1 > 0 else { return finalists[0] }
        return finalists[best.0]
    }

    /// 首字节到达时握手已完成，再跳过 TCP 慢启动，只计其后固定窗口内的字节。
    /// 否则短试测比的是起步快慢，起步快但持续吞吐差的节点会胜出。
    private func trialBytes(from url: URL) async -> Int64 {
        let clock = ContinuousClock()
        let firstByteDeadline = clock.now.advanced(by: Self.trialFirstByteTimeout)
        // 首字节检测按 50 ms 轮询，计数截止需留出余量，窗口才不会被截短。
        let limit = firstByteDeadline.advanced(by: Self.trialRampDuration + Self.trialWindowDuration + .milliseconds(200))
        let transfer = SpeedTestTransfer(direction: .download, measurementStart: clock.now, deadline: limit)
        let session = URLSession(configuration: makeSessionConfiguration(), delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // 下载文件可能在窗口内传完，连续请求直到 stop() 让后续请求失败。
        async let downloads: Void = {
            while (try? await transfer.run(session.dataTask(with: Self.cacheBusted(url)))) != nil {}
        }()
        let received = await Self.steadyBytes(of: transfer, clock: clock, firstByteDeadline: firstByteDeadline)
        transfer.stop()
        await downloads
        return received
    }

    private static func steadyBytes(
        of transfer: SpeedTestTransfer,
        clock: ContinuousClock,
        firstByteDeadline: ContinuousClock.Instant
    ) async -> Int64 {
        while transfer.snapshot().totalBytes == 0 {
            guard clock.now < firstByteDeadline,
                  (try? await clock.sleep(for: .milliseconds(50))) != nil else { return 0 }
        }
        let windowStart = clock.now.advanced(by: trialRampDuration)
        guard (try? await clock.sleep(until: windowStart)) != nil else { return 0 }
        let before = transfer.snapshot().totalBytes
        guard (try? await clock.sleep(until: windowStart.advanced(by: trialWindowDuration))) != nil else { return 0 }
        return transfer.snapshot().totalBytes - before
    }

    func measureLatency(
        url: URL,
        onSample: @escaping @Sendable @MainActor (Int, Int, Double) -> Void
    ) async throws -> LatencyMeasurement {
        try Task.checkCancellation()
        let session = URLSession(configuration: makeSessionConfiguration())
        defer { session.invalidateAndCancel() }
        let clock = ContinuousClock()
        var samples: [Double] = []
        var consecutiveFailures = 0
        let total = 6

        // 首次请求预热连接；之后记录完整 HTTP 往返耗时，不将其宣称为 ICMP Ping。
        for index in 0...total {
            try Task.checkCancellation()
            var request = URLRequest(url: Self.cacheBusted(url))
            request.timeoutInterval = 4
            let start = clock.now
            do {
                let (_, response) = try await session.data(for: request)
                let elapsed = SpeedTestMath.seconds(start.duration(to: clock.now)) * 1_000
                try Self.validate(response)
                consecutiveFailures = 0
                guard index > 0 else { continue }
                samples.append(elapsed)
                await onSample(samples.count, total, elapsed)
            } catch {
                try Task.checkCancellation()
                // HTTP 拒绝不可当作丢失一个样本继续；保留 URLError 供界面区分断网和超时。
                if error is SpeedTestError { throw error }
                consecutiveFailures += 1
                if consecutiveFailures >= 2 { throw error }
            }
        }

        guard samples.count >= 3, let stats = SpeedTestMath.pingAndJitter(samples: samples) else {
            throw SpeedTestError.insufficientLatencySamples
        }
        return LatencyMeasurement(
            pingMilliseconds: stats.ping,
            jitterMilliseconds: stats.jitter
        )
    }

    func measureDownload(
        from url: URL? = nil,
        onLive: @escaping @Sendable @MainActor (Double) -> Void
    ) async throws -> Double {
        guard let url = url ?? configuration.downloadURL else { throw SpeedTestError.noServer }
        return try await performTransfer(direction: .download, url: url, onLive: onLive)
    }

    func measureUpload(
        to url: URL? = nil,
        onLive: @escaping @Sendable @MainActor (Double) -> Void
    ) async throws -> Double {
        guard let url = url ?? configuration.uploadURL else { throw SpeedTestError.noServer }
        return try await performTransfer(direction: .upload, url: url, onLive: onLive)
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw SpeedTestError.httpStatus(http.statusCode) }
    }

    private static func cacheBusted(_ url: URL) -> URL {
        url.appending(queryItems: [URLQueryItem(name: "r", value: UUID().uuidString)])
    }

    private func performTransfer(
        direction: SpeedTestTransfer.Direction,
        url: URL,
        onLive: @escaping @Sendable @MainActor (Double) -> Void
    ) async throws -> Double {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: configuration.transferDuration)
        let measurementStart = start.advanced(by: configuration.warmupDuration)
        let transfer = SpeedTestTransfer(direction: direction, measurementStart: measurementStart, deadline: deadline)
        let session = URLSession(configuration: makeSessionConfiguration(), delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // 只有整段落在预热之后的窗口才参与最终结果。
        let steadyElapsed = SpeedTestMath.seconds(configuration.warmupDuration) + SpeedTestThroughputWindow.span
        let windowRates = try await withThrowingTaskGroup(of: [Double].self) { group in
            for _ in 0..<(direction == .download ? 4 : 3) {
                group.addTask {
                    var uploadSize = 16 * 1024
                    while clock.now < deadline {
                        try Task.checkCancellation()
                        let requestStart = clock.now
                        do {
                            if direction == .download {
                                try await transfer.run(session.dataTask(with: Self.cacheBusted(url)))
                            } else {
                                var request = URLRequest(url: url)
                                request.httpMethod = "POST"
                                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                                try await transfer.run(session.uploadTask(with: request, from: Self.uploadPayload.prefix(uploadSize)))
                                uploadSize = SpeedTestMath.nextUploadSize(
                                    current: uploadSize,
                                    elapsed: SpeedTestMath.seconds(requestStart.duration(to: clock.now))
                                )
                            }
                        } catch {
                            // 到期主动中止尾部请求是正常结束；HTTP/传输错误仍必须使本轮失败。
                            if clock.now >= deadline, let error = error as? URLError, error.code == .cancelled { return [] }
                            throw error
                        }
                    }
                    return []
                }
            }
            // 截止任务独立于界面回调；主线程繁忙时也必须按时停止网络传输。
            group.addTask {
                try await clock.sleep(until: deadline)
                transfer.stop()
                return []
            }
            group.addTask {
                var window = SpeedTestThroughputWindow()
                var steadyRates: [Double] = []
                while clock.now < deadline {
                    try await clock.sleep(until: min(clock.now.advanced(by: .milliseconds(120)), deadline))
                    try Task.checkCancellation()
                    let sample = transfer.snapshot()
                    let elapsed = SpeedTestMath.seconds(start.duration(to: min(clock.now, deadline)))
                    if let live = window.append(bytes: sample.totalBytes, elapsed: elapsed) {
                        if elapsed >= steadyElapsed { steadyRates.append(live) }
                        await onLive(live) // 零速也是有效样本，必须送达界面。
                    }
                }
                return steadyRates
            }
            // next() 在首个错误出现时立即抛出，结构化并发负责取消、等待其余子任务。
            var rates: [Double] = []
            while let childRates = try await group.next() { rates += childRates }
            return rates
        }
        try Task.checkCancellation()
        let sample = transfer.snapshot()
        guard sample.hasAcceptedResponse, sample.measuredBytes > 0 else { throw SpeedTestError.noData }
        // 取稳定窗口速度的 90 分位：不被连接爬坡、请求间隙和偶发卡顿拉低，也挡住单次尖峰。
        if let rate = SpeedTestMath.percentile(windowRates, 0.9) {
            return rate
        }
        let elapsed = SpeedTestMath.seconds(measurementStart.duration(to: deadline))
        return SpeedTestMath.megabitsPerSecond(bytes: sample.measuredBytes, seconds: elapsed)
    }
}
