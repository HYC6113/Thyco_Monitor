import Foundation
import Testing
@testable import Thyco_Monitor

@Suite(.serialized)
struct SpeedTestTests {
    @Test func medianLatencyKeepsJitterInSamplingOrder() throws {
        let stats = try #require(SpeedTestMath.pingAndJitter(samples: [20, 80, 90, 100, 110, 120]))
        #expect(stats.ping == 95)
        #expect(stats.jitter == 20)
        let shuffled = try #require(SpeedTestMath.pingAndJitter(samples: [10, 100, 20]))
        #expect(shuffled.ping == 20)
        #expect(shuffled.jitter == 85)
        #expect(SpeedTestMath.pingAndJitter(samples: [.nan, .infinity, -1, 0]) == nil)
    }

    @Test func percentileInterpolatesAndIgnoresOrder() {
        #expect(SpeedTestMath.percentile([], 0.9) == nil)
        #expect(SpeedTestMath.percentile([42], 0.9) == 42)
        let rates: [Double] = [100, 0, 90, 10, 80, 20, 70, 30, 60, 40, 50]
        #expect(SpeedTestMath.percentile(rates, 0.9) == 90)
        #expect(SpeedTestMath.percentile([0, 10], 0.9) == 9)
    }

    @Test func throughputWindowReturnsZeroAfterStall() {
        var window = SpeedTestThroughputWindow()
        #expect(window.append(bytes: 125_000, elapsed: 0.3) != nil)
        for step in 4...14 {
            _ = window.append(bytes: 125_000, elapsed: Double(step) / 10)
        }
        #expect(window.append(bytes: 125_000, elapsed: 1.5) == 0)
    }

    @Test func identityOnlyMergesMatchingAddresses() {
        let current = PublicNetworkInfo(ip: "203.0.113.1", city: "A")
        let other = PublicNetworkInfo(ip: "198.51.100.1", city: "B", isp: "Other ISP")
        #expect(current.fillingGaps(from: other) == current)
        #expect(PublicNetworkInfo().fillingGaps(from: current) == current)
        #expect(current.fillingGaps(from: PublicNetworkInfo(isp: "Unknown IP")) == current)
        let same = PublicNetworkInfo(ip: "203.0.113.1", isp: "Matching ISP")
        #expect(current.fillingGaps(from: same).isp == "Matching ISP")
        #expect(other.fillingGaps(from: current).city == "B")
    }

    @Test func cloudflareMetaDecodesPublicIdentity() throws {
        let data = """
        {
          "clientIp":"198.51.100.10",
          "country":"US",
          "region":"California",
          "city":"Los Angeles",
          "timezone":"America/Los_Angeles",
          "asOrganization":"Example ISP",
          "asn":64500,
          "colo":"LAX",
          "latitude":34.05,
          "longitude":"-118.24"
        }
        """.data(using: .utf8)!

        let info = try #require(PublicNetworkInfo.cloudflareMeta(data))
        // 元数据完整时不再请求第三方 IP 库。
        #expect(info.isComplete)
        #expect(info.ip == "198.51.100.10")
        #expect(info.countryCode == "US")
        #expect(info.city == "Los Angeles")
        #expect(info.isp == "Example ISP")
        #expect(info.asn == "64500")
        #expect(info.colo == "LAX")
        #expect(info.longitude == -118.24)
    }

    @Test func cloudflareTraceProvidesMinimalIdentityFallback() throws {
        let data = "ip=198.51.100.10\nloc=US\ncolo=LAX\n".data(using: .utf8)!
        let info = try #require(PublicNetworkInfo.cloudflareTrace(data))
        #expect(info.ip == "198.51.100.10")
        #expect(info.countryCode == "US")
        #expect(info.colo == "LAX")
        #expect(!info.isComplete)
    }

    @Test func pconlineDecodesGBKAndRejectsMismatchedIP() throws {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let json = """
        \r\n{"ip":"113.88.0.1","pro":"广东省","city":"深圳市","addr":"广东省深圳市 电信","err":""}
        """
        let data = try #require(json.data(using: gbk))
        let location = try #require(ChineseIPLocation.pconline(data, ip: "113.88.0.1"))
        #expect(location == ChineseIPLocation(province: "广东省", city: "深圳市", isp: "中国电信"))
        // IPv6 查询时服务端改查请求方 IP，结果不能用于当前出口。
        #expect(ChineseIPLocation.pconline(data, ip: "2408:8000::1") == nil)
        let foreign = try #require(#"{"ip":"8.8.8.8","pro":"","city":"","addr":" 美国","err":"noprovince"}"#.data(using: gbk))
        #expect(ChineseIPLocation.pconline(foreign, ip: "8.8.8.8") == nil)
    }

    @Test func defaultSpeedTestSessionUsesSystemProxySettings() {
        let configuration = SpeedTestEngine.sessionConfiguration()
        #expect(configuration.connectionProxyDictionary == nil)
    }

    @Test func directSpeedTestSessionIgnoresSystemProxy() {
        let configuration = SpeedTestEngine.directSessionConfiguration()
        #expect(configuration.connectionProxyDictionary?.isEmpty == true)
        #expect(OoklaServerDirectory.usesProxyRoute(for: configuration) == false)
    }

    @Test func ooklaDirectoryDecodesHTTPSHost() throws {
        let json = """
        [{"name":"Shanghai","sponsor":"China Telecom","cc":"CN","host":"sh.example:8080","https_functional":1}]
        """.data(using: .utf8)!
        let records = try OoklaServerDirectory.decode(json)
        let server = try #require(SpeedTestServer(record: records[0]))
        #expect(server.label == "Shanghai · China Telecom")
        #expect(server.latencyURL.absoluteString == "https://sh.example:8080/speedtest/latency.txt")
        #expect(server.downloadURL.absoluteString == "https://sh.example:8080/speedtest/random4000x4000.jpg")
        #expect(server.uploadURL.absoluteString == "https://sh.example:8080/speedtest/upload.php")
    }

    @Test func ooklaDirectCandidatesUseNearestHongKongServersAndSkipMainland() {
        let nearest = [
            ooklaRecord(name: "Kunshan", cc: "CN", host: "ks.example:8080"),
            ooklaRecord(name: "Taoyuan", cc: "TW", host: "ty.example:8080"),
            ooklaRecord(name: "Sha Tin", cc: "HK", host: "st.example:8080")
        ]
        let hongKong = [ooklaRecord(name: "Hong Kong", cc: "HK", host: "hk.example:8080")]
        let names = OoklaServerDirectory.candidates(nearest: nearest, hongKong: hongKong, usesSystemProxy: false).map(\.name)
        #expect(names == ["Sha Tin"])
    }

    @Test func ooklaDirectCandidatesFallBackToHongKongSearchList() {
        let nearest = [ooklaRecord(name: "Kunshan", cc: "CN", host: "ks.example:8080")]
        let hongKong = [
            ooklaRecord(name: "Hong Kong", cc: "HK", host: "hk.example:8080"),
            ooklaRecord(name: "Hong Kong", cc: "US", host: "us.example:8080")
        ]
        let hosts = OoklaServerDirectory.candidates(nearest: nearest, hongKong: hongKong, usesSystemProxy: false).map(\.host)
        #expect(hosts == ["hk.example:8080"])
    }

    @Test func ooklaCandidatesUseProxyExitNearestListWhenSystemProxyIsEnabled() {
        let nearest = [ooklaRecord(name: "Tokyo", cc: "JP", host: "ty.example:8080")]
        let hongKong = [ooklaRecord(name: "Hong Kong", cc: "HK", host: "hk.example:8080")]
        let names = OoklaServerDirectory.candidates(nearest: nearest, hongKong: hongKong, usesSystemProxy: true).map(\.name)
        #expect(names == ["Tokyo"])
    }

    @Test func trialPicksServerThatDeliversDataOverLowestLatency() async throws {
        let engine = makeEngine(path: "success")
        let finalists = ["pending", "reject", "success"].map { path in
            let url = URL(string: "https://speed-test.invalid/\(path)")!
            return SpeedTestServer(name: path, sponsor: "", countryCode: "HK", latencyURL: url, downloadURL: url, uploadURL: url)
        }
        let session = URLSession(configuration: testSessionConfiguration())
        defer { session.invalidateAndCancel() }
        #expect(try await engine.fastestByTrial(finalists, session: session).name == "success")
        #expect(try await engine.fastestByTrial(Array(finalists.prefix(2)), session: session).name == "pending")
    }

    @Test func trialDoesNotLetLaterResponseBenefitFromSharedBandwidth() async throws {
        TrialURLProtocol.traffic.reset()
        let session = trialSession()
        defer { session.invalidateAndCancel() }
        let selected = try await SpeedTestEngine().fastestByTrial([trialServer("fast"), trialServer("slow")], session: session)
        #expect(selected.name == "fast")
        #expect(TrialURLProtocol.traffic.maximumConcurrent == 1)
        #expect(TrialURLProtocol.traffic.activeCount == 0)
    }

    @Test func cancellingTrialDoesNotStartNextCandidate() async throws {
        TrialURLProtocol.traffic.reset()
        let session = trialSession()
        defer { session.invalidateAndCancel() }
        let task = Task { try await SpeedTestEngine().fastestByTrial([trialServer("fast"), trialServer("slow")], session: session) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while TrialURLProtocol.traffic.activeCount == 0, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        #expect(TrialURLProtocol.traffic.activeCount == 1)
        let cancelled = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(cancelled.duration(to: clock.now) < .seconds(1))
        #expect(TrialURLProtocol.traffic.startedPaths == ["fast"])
        #expect(TrialURLProtocol.traffic.activeCount == 0)
    }

    @Test func historyDoesNotExcludeServersAfterExitChanges() throws {
        let suite = "SpeedTestTests.routes.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let history = SpeedTestServerHistory(suiteName: suite)
        let a = trialServer("a")
        let b = trialServer("b")
        for proxy in [false, true] {
            let oldA = try #require(SpeedTestServerHistory.key(for: a, publicIP: "203.0.113.1", usesProxyRoute: proxy))
            let oldB = try #require(SpeedTestServerHistory.key(for: b, publicIP: "203.0.113.1", usesProxyRoute: proxy))
            history.record(50, for: oldA)
            history.record(300, for: oldB)
            let finalists = { (ip: String?) in
                SpeedTestServerHistory.finalists(ranked: [a, b], megabits: history.megabits()) {
                    SpeedTestServerHistory.key(for: $0, publicIP: ip, usesProxyRoute: proxy)
                }.map(\.name)
            }
            #expect(finalists("203.0.113.1") == ["b"])
            #expect(finalists("198.51.100.2") == ["a", "b"])
            #expect(finalists(nil) == ["a", "b"])
            #expect(finalists("") == ["a", "b"])
        }
        // 无出口信息的旧版缓存不能继续参与筛选。
        history.record(1, for: "direct|\(a.downloadURL.absoluteString)")
        history.record(900, for: "direct|\(b.downloadURL.absoluteString)")
        let migrated = SpeedTestServerHistory.finalists(ranked: [a, b], megabits: history.megabits()) {
            SpeedTestServerHistory.key(for: $0, publicIP: "198.51.100.3", usesProxyRoute: false)
        }
        #expect(migrated.map(\.name) == ["a", "b"])
        #expect(SpeedTestServerHistory.key(for: a, publicIP: nil, usesProxyRoute: false) == nil)
        #expect(SpeedTestServerHistory.key(for: a, publicIP: " \n", usesProxyRoute: false) == nil)
    }

    @Test func downloadHistoryUsesSelectionContextAndSkipsUnknownExit() throws {
        let suite = "SpeedTestTests.selection.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let history = SpeedTestServerHistory(suiteName: suite)
        let server = trialServer("a")
        let key = try #require(SpeedTestServerHistory.key(for: server, publicIP: "203.0.113.1", usesProxyRoute: false))
        let engine = SpeedTestEngine(history: history)
        engine.recordDownload(100, for: SpeedTestSelection(server: server, historyKey: key))
        engine.recordDownload(900, for: SpeedTestSelection(server: server, historyKey: nil))
        #expect(history.megabits() == [key: 100])
    }

    @Test func finalistsAddProvenServersAndDropSlowOnes() {
        let ranked = ["a", "b", "c", "d", "e", "f"].map { name in
            let url = URL(string: "https://\(name).example/speedtest/random4000x4000.jpg")!
            return SpeedTestServer(name: name, sponsor: "", countryCode: "HK", latencyURL: url, downloadURL: url, uploadURL: url)
        }
        let finalists = { (megabits: [String: Double]) in
            SpeedTestServerHistory.finalists(ranked: ranked, megabits: megabits, key: \.name).map(\.name)
        }
        #expect(finalists([:]) == ["a", "b", "c"])
        #expect(finalists(["b": 40, "e": 300, "f": 280]) == ["a", "c", "d", "e", "f"])
    }

    @Test func historySmoothsAndExpiresRecords() {
        let suite = "SpeedTestTests.history"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let history = SpeedTestServerHistory(suiteName: suite)
        let start = Date(timeIntervalSince1970: 0)
        history.record(100, for: "hk", now: start)
        history.record(300, for: "hk", now: start)
        history.record(.nan, for: "hk", now: start)
        #expect(history.megabits(now: start) == ["hk": 200])
        #expect(history.megabits(now: start.addingTimeInterval(8 * 24 * 60 * 60)).isEmpty)
    }

    @Test func adaptiveUploadSizeIsBounded() {
        #expect(SpeedTestMath.nextUploadSize(current: 16_384, elapsed: 0.01) == 32_768)
        #expect(SpeedTestMath.nextUploadSize(current: 16_384, elapsed: 4) == 16_384)
        #expect(SpeedTestMath.nextUploadSize(current: 4_194_304, elapsed: 0.01) == 4_194_304)
        #expect(SpeedTestMath.nextUploadSize(current: 1_048_576, elapsed: 2) == 524_288)
    }

    @Test func counterExcludesWarmupAndPostDeadlineBytes() {
        let now = ContinuousClock.now
        let session = URLSession(configuration: testSessionConfiguration())
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://speed-test.invalid/pending")!)
        let warmup = SpeedTestTransfer(direction: .download, measurementStart: now.advanced(by: .seconds(10)), deadline: now.advanced(by: .seconds(20)))
        warmup.urlSession(session, dataTask: task, didReceive: Data(count: 100))
        #expect(warmup.snapshot().totalBytes == 100)
        #expect(warmup.snapshot().measuredBytes == 0)

        let measuring = SpeedTestTransfer(direction: .download, measurementStart: now, deadline: now.advanced(by: .seconds(10)))
        measuring.urlSession(session, dataTask: task, didReceive: Data(count: 100))
        #expect(measuring.snapshot().measuredBytes == 100)

        let finished = SpeedTestTransfer(direction: .download, measurementStart: now.advanced(by: .seconds(-10)), deadline: now)
        finished.urlSession(session, dataTask: task, didReceive: Data(count: 100))
        #expect(finished.snapshot().totalBytes == 0)
        #expect(finished.snapshot().measuredBytes == 0)
    }

    @Test func rejectedUploadsCannotProduceSuccessfulMeasurement() async {
        let engine = makeEngine(path: "reject")
        await #expect(throws: SpeedTestError.httpStatus(500)) {
            try await engine.measureUpload { _ in }
        }
    }

    @Test func sentBytesDoNotOverrideRejectedHTTPResponse() async {
        let now = ContinuousClock.now
        let transfer = SpeedTestTransfer(direction: .upload, measurementStart: now, deadline: now.advanced(by: .seconds(3)))
        let session = URLSession(configuration: testSessionConfiguration(), delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://speed-test.invalid/reject")!)
        request.httpMethod = "POST"
        let task = session.uploadTask(with: request, from: Data(count: 16_384))
        // 模拟服务端作出 HTTP 响应之前 URLSession 已上报的上传进度。
        transfer.urlSession(session, task: task, didSendBodyData: 16_384, totalBytesSent: 16_384, totalBytesExpectedToSend: 16_384)
        #expect(transfer.snapshot().measuredBytes == 16_384)
        await #expect(throws: SpeedTestError.httpStatus(500)) {
            try await transfer.run(task)
        }
        #expect(!transfer.snapshot().hasAcceptedResponse)
    }

    @Test func stoppedTransferCancelsPendingAndRejectsNewRequests() async {
        let now = ContinuousClock.now
        let transfer = SpeedTestTransfer(direction: .download, measurementStart: now, deadline: now.advanced(by: .seconds(3)))
        let session = URLSession(configuration: testSessionConfiguration(), delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://speed-test.invalid/pending")!

        let pending = Task { try await transfer.run(session.dataTask(with: url)) }
        try? await Task.sleep(for: .milliseconds(100))
        transfer.stop()
        await #expect(throws: URLError.self) { try await pending.value }

        let late = session.dataTask(with: url)
        do {
            try await transfer.run(late)
            Issue.record("Stopped transfer unexpectedly started a request")
        } catch {
            #expect((error as? URLError)?.code == .cancelled)
        }
        #expect(late.state == .suspended)
    }

    @Test func transferPreservesOfflineError() async {
        do {
            _ = try await makeEngine(path: "offline").measureDownload { _ in }
            Issue.record("Offline transfer unexpectedly succeeded")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @MainActor
    @Test func stalledDownloadPublishesZero() async throws {
        let values = LiveValues()
        _ = try await makeEngine(path: "stall").measureDownload { values.values.append($0) }
        #expect(values.values.contains { $0 > 0 })
        #expect(values.values.last == 0)
    }

    @Test func successfulDownloadProducesFiniteResult() async throws {
        let rate = try await makeEngine(path: "success").measureDownload { _ in }
        #expect(rate.isFinite && rate > 0)
    }

    @Test func cancellationStopsOutstandingRequests() async {
        let clock = ContinuousClock()
        let task = Task { try await makeEngine(path: "pending", duration: .seconds(5)).measureDownload { _ in } }
        try? await Task.sleep(for: .milliseconds(100))
        let cancelled = clock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled transfer unexpectedly succeeded")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(cancelled.duration(to: clock.now) < .seconds(1))
    }

    @Test func concurrentCancellationFinishesEveryTransfer() async {
        let now = ContinuousClock.now
        let transfer = SpeedTestTransfer(direction: .download, measurementStart: now, deadline: now.advanced(by: .seconds(3)))
        let session = URLSession(configuration: testSessionConfiguration(), delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://speed-test.invalid/pending")!
        let workers = (0..<256).map { _ in
            Task.detached { try await transfer.run(session.dataTask(with: url)) }
        }
        // 让取消与后台请求的启动竞争，每个等待者都必须结束。
        workers.forEach { $0.cancel() }
        for worker in workers {
            do {
                try await worker.value
                Issue.record("Cancelled request unexpectedly succeeded")
            } catch {
                #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
            }
        }
    }

    @MainActor
    @Test func cancelledIdentityRefreshCannotFinishNewRefresh() async {
        let source = IdentitySource()
        let model = SpeedTestModel(fetchIdentity: { await source.fetch() })
        defer { model.shutdown() }
        model.loadIdentity()
        await source.waitForRequests(1)
        model.loadIdentity()
        await source.waitForRequests(2)
        await source.finish(0, with: PublicNetworkInfo(ip: "203.0.113.1"))
        // 旧任务恢复到主线程之后也不能清除新任务的 loading 标志或写入身份。
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.isRefreshingIdentity)
        #expect(model.info == nil)
        await source.finish(1, with: PublicNetworkInfo(ip: "198.51.100.1"))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!model.isRefreshingIdentity)
        #expect(model.info?.ip == "198.51.100.1")
    }

    @Test func prefetchedCandidatesOnlyServeTheSameFreshRoute() {
        let servers = [trialServer("a")]
        let fresh = SpeedTestCandidates(servers: servers, usesProxyRoute: true, fetchedAt: .now)
        #expect(fresh.isUsable(forProxyRoute: true))
        #expect(!fresh.isUsable(forProxyRoute: false))
        let stale = SpeedTestCandidates(servers: servers, usesProxyRoute: true, fetchedAt: .now.advanced(by: .seconds(-121)))
        #expect(!stale.isUsable(forProxyRoute: true))
    }

    @MainActor
    @Test func startingTestKeepsIdentityRefreshInProgress() async {
        let source = IdentitySource()
        let model = SpeedTestModel(engine: makeEngine(path: "pending"), fetchIdentity: { await source.fetch() })
        defer { model.shutdown() }
        model.loadIdentity()
        await source.waitForRequests(1)
        model.toggle()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await source.requestCount == 1)
        await source.finish(0, with: PublicNetworkInfo(ip: "203.0.113.1"))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.info?.ip == "203.0.113.1")
        #expect(model.isRunning)
    }

    private func makeEngine(path: String, duration: Duration = .milliseconds(1600)) -> SpeedTestEngine {
        let url = URL(string: "https://speed-test.invalid/\(path)")!
        return SpeedTestEngine(
            configuration: SpeedTestConfiguration(downloadURL: url, uploadURL: url, transferDuration: duration, warmupDuration: .milliseconds(100)),
            makeSessionConfiguration: { testSessionConfiguration() }
        )
    }
}

private func ooklaRecord(name: String, cc: String, host: String) -> OoklaServerRecord {
    OoklaServerRecord(name: name, sponsor: "China Telecom", countryCode: cc, host: host, httpsFunctional: true)
}

private func trialServer(_ name: String) -> SpeedTestServer {
    let url = URL(string: "https://speed-test.invalid/\(name)")!
    return SpeedTestServer(name: name, sponsor: "", countryCode: "HK", latencyURL: url, downloadURL: url, uploadURL: url)
}

/// 两个端点共享 600 KB/s，慢端点上限 400 KB/s 且首字节延后 450 ms。
/// 并发且错开的计时窗口会使慢端点受益；独占窗口应稳定选中快端点。
private final class TrialURLProtocol: URLProtocol, @unchecked Sendable {
    static let traffic = TrialTraffic()
    private let lock = NSLock()
    private let id = UUID()
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var started = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.lastPathComponent
        let source = DispatchSource.makeTimerSource(queue: .global())
        source.schedule(deadline: .now() + (path == "slow" ? 0.45 : 0), repeating: .milliseconds(20))
        source.setEventHandler { [weak self] in self?.sendChunk(path: path) }
        lock.lock()
        timer = source
        source.resume()
        lock.unlock()
    }

    private func sendChunk(path: String) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        let first = !started
        if first {
            started = true
            Self.traffic.start(id, path: path)
        }
        let bytes = Self.traffic.chunkSize(limit: path == "slow" ? 400_000 : 600_000)
        lock.unlock()
        if first {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(count: bytes))
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        timer?.cancel()
        timer = nil
        if started { Self.traffic.stop(id) }
        lock.unlock()
    }
}

private final class TrialTraffic: @unchecked Sendable {
    private let lock = NSLock()
    private var active = Set<UUID>()
    private var maximum = 0
    private var paths: [String] = []

    var maximumConcurrent: Int { lock.withLock { maximum } }
    var activeCount: Int { lock.withLock { active.count } }
    var startedPaths: [String] { lock.withLock { paths } }

    func reset() {
        lock.withLock { active = []; maximum = 0; paths = [] }
    }

    func start(_ id: UUID, path: String) {
        lock.withLock {
            active.insert(id)
            maximum = max(maximum, active.count)
            paths.append(path)
        }
    }

    func stop(_ id: UUID) { _ = lock.withLock { active.remove(id) } }

    func chunkSize(limit: Int) -> Int {
        lock.withLock { min(limit, 600_000 / active.count) / 50 }
    }
}

private func trialSession() -> URLSession {
    let configuration = testSessionConfiguration()
    configuration.protocolClasses = [TrialURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func testSessionConfiguration() -> URLSessionConfiguration {
    let configuration = SpeedTestEngine.sessionConfiguration()
    configuration.protocolClasses = [SpeedTestURLProtocol.self]
    return configuration
}

/// 仅在测试会话中拦截请求；不会触达真实测速端点。
private final class SpeedTestURLProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.lastPathComponent
        if path == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if path == "pending" { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "reject" ? 500 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "reject" {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // 分批抵达，模拟真实 delegate 时序；stall 路径在有数据后停止发送。
        for step in 1...3 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(step) * 0.08) { [self] in
                lock.lock()
                let isStopped = stopped
                lock.unlock()
                guard !isStopped else { return }
                client?.urlProtocol(self, didLoad: Data(count: 16_384))
                if path == "success", step == 3 { client?.urlProtocolDidFinishLoading(self) }
            }
        }
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

@MainActor
private final class LiveValues {
    var values: [Double] = []
}

private actor IdentitySource {
    private var requests: [CheckedContinuation<PublicNetworkInfo?, Never>?] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    var requestCount: Int { requests.count }

    func fetch() async -> PublicNetworkInfo? {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
            if let waiter, requests.count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func finish(_ index: Int, with info: PublicNetworkInfo) {
        requests[index]?.resume(returning: info)
        requests[index] = nil
    }
}
