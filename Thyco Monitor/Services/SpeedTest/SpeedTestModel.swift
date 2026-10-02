import Foundation
import Observation

enum SpeedTestPhase: Equatable {
    case idle
    case latency
    case download
    case upload
    case finished
    case failed
}

enum NetworkIdentityState: Equatable {
    case loading
    case ready
    case failed
}

enum SpeedTestFailure: Equatable {
    case offline
    case timedOut
    case generic
}

@MainActor
@Observable
final class SpeedTestModel {
    private(set) var phase: SpeedTestPhase = .idle
    private(set) var gaugeMegabits: Double = 0
    private(set) var hasLiveSpeedSample = false
    private(set) var pingMilliseconds: Double?
    private(set) var jitterMilliseconds: Double?
    private(set) var downloadMegabits: Double?
    private(set) var uploadMegabits: Double?
    private(set) var latencyProgress: Double = 0
    private(set) var livePing: Double?
    private(set) var failureReason: SpeedTestFailure?
    private(set) var info: PublicNetworkInfo?
    /// 最近一次测速选中的节点；新一轮选服完成前保留上一台，避免界面闪回。
    private(set) var server: SpeedTestServer?
    private(set) var identityState: NetworkIdentityState = .loading
    private(set) var isRefreshingIdentity = false

    var isRunning: Bool {
        switch phase {
        case .latency, .download, .upload: true
        case .idle, .finished, .failed: false
        }
    }

    private let engine: SpeedTestEngine
    private let fetchIdentity: @Sendable () async -> PublicNetworkInfo?
    private var identityTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var runID = UUID()

    init(
        engine: SpeedTestEngine = SpeedTestEngine(),
        fetchIdentity: @escaping @Sendable () async -> PublicNetworkInfo? = { await NetworkIdentityService.fetch() }
    ) {
        self.engine = engine
        self.fetchIdentity = fetchIdentity
    }

    func loadIdentity() {
        identityTask?.cancel()
        if info == nil {
            identityState = .loading
        }
        isRefreshingIdentity = true
        identityTask = Task { [weak self, fetchIdentity] in
            let fetched = await fetchIdentity()
            guard let self, !Task.isCancelled else { return }
            self.isRefreshingIdentity = false
            self.identityTask = nil
            if let fetched {
                self.updateIdentity(with: fetched)
            } else if self.info == nil {
                self.identityState = .failed
            }
        }
    }

    func toggle() {
        if isRunning {
            stopRun()
        } else {
            begin()
        }
    }

    func clearServerHistory() {
        engine.clearServerHistory()
    }

    func shutdown() {
        identityTask?.cancel()
        identityTask = nil
        isRefreshingIdentity = false
        stopRun()
    }

    func applyPreviewFixture() {
        phase = .finished
        gaugeMegabits = 86.4
        pingMilliseconds = 18
        jitterMilliseconds = 2.4
        downloadMegabits = 86.4
        uploadMegabits = 24.1
        latencyProgress = 1
        identityState = .ready
        isRefreshingIdentity = false
        info = PublicNetworkInfo(
            ip: "203.0.113.8",
            countryCode: "CN",
            countryName: "China",
            region: "Shanghai",
            city: "Shanghai",
            timeZoneID: "Asia/Shanghai",
            isp: "China Telecom",
            asn: "4134",
            colo: "SHA"
        )
    }

    private func begin() {
        let id = UUID()
        runID = id
        // 与选服并行刷新出口信息，刚切换的系统代理不会继续显示旧出口，也不推迟测速开始。
        loadIdentity()
        runTask?.cancel()
        pingMilliseconds = nil
        jitterMilliseconds = nil
        downloadMegabits = nil
        uploadMegabits = nil
        gaugeMegabits = 0
        hasLiveSpeedSample = false
        livePing = nil
        latencyProgress = 0
        failureReason = nil
        phase = .latency
        runTask = Task { [weak self] in
            await self?.run(id: id)
        }
    }

    private func stopRun() {
        runID = UUID()
        runTask?.cancel()
        runTask = nil
        guard isRunning else { return }
        phase = .idle
        gaugeMegabits = 0
        hasLiveSpeedSample = false
        livePing = nil
    }

    private func run(id: UUID) async {
        defer {
            if runID == id { runTask = nil }
        }
        do {
            let server = try await engine.resolveServer()
            guard isCurrent(id) else { return }
            self.server = server

            let latency = try await engine.measureLatency(url: server.latencyURL) { [weak self] done, total, latest in
                guard let self, self.isCurrent(id) else { return }
                self.latencyProgress = Double(done) / Double(max(total, 1))
                self.livePing = latest
            }
            guard isCurrent(id) else { return }
            pingMilliseconds = latency.pingMilliseconds
            jitterMilliseconds = latency.jitterMilliseconds
            livePing = nil

            phase = .download
            gaugeMegabits = 0
            hasLiveSpeedSample = false
            let down = try await engine.measureDownload(from: server.downloadURL) { [weak self] live in
                guard let self, self.isCurrent(id) else { return }
                self.gaugeMegabits = live
                self.hasLiveSpeedSample = true
            }
            guard isCurrent(id) else { return }
            engine.recordDownload(down, on: server)
            downloadMegabits = down
            gaugeMegabits = down

            phase = .upload
            gaugeMegabits = 0
            hasLiveSpeedSample = false
            let up = try await engine.measureUpload(to: server.uploadURL) { [weak self] live in
                guard let self, self.isCurrent(id) else { return }
                self.gaugeMegabits = live
                self.hasLiveSpeedSample = true
            }
            guard isCurrent(id) else { return }
            uploadMegabits = up
            phase = .finished
            gaugeMegabits = downloadMegabits ?? up
        } catch {
            guard isCurrent(id) else { return }
            phase = .failed
            failureReason = Self.failureReason(for: error)
        }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        runID == id && !Task.isCancelled
    }

    private func updateIdentity(with incoming: PublicNetworkInfo) {
        if let existing = info {
            // 新出口替换旧出口；只有 IP 一致时才保留旧字段。
            info = incoming.fillingGaps(from: existing)
        } else {
            info = incoming
        }
        if info?.hasContent == true {
            identityState = .ready
        }
    }

    private static func failureReason(for error: Error) -> SpeedTestFailure {
        guard let urlError = error as? URLError else {
            return .generic
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .generic
        }
    }
}
