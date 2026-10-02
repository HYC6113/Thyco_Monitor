import Foundation
import SystemConfiguration

/// Ookla 公开目录里的一台 HTTPS 测速节点。
nonisolated struct SpeedTestServer: Sendable, Equatable {
    var name: String
    var sponsor: String
    var countryCode: String
    var latencyURL: URL
    var downloadURL: URL
    var uploadURL: URL

    var label: String {
        let city = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isp = sponsor.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.isEmpty { return isp }
        if isp.isEmpty { return city }
        return "\(city) · \(isp)"
    }

    init(name: String, sponsor: String, countryCode: String, latencyURL: URL, downloadURL: URL, uploadURL: URL) {
        self.name = name
        self.sponsor = sponsor
        self.countryCode = countryCode
        self.latencyURL = latencyURL
        self.downloadURL = downloadURL
        self.uploadURL = uploadURL
    }

    init?(record: OoklaServerRecord) {
        guard let latencyURL = Self.endpoint(host: record.host, path: "/speedtest/latency.txt"),
              let downloadURL = Self.endpoint(host: record.host, path: "/speedtest/random4000x4000.jpg"),
              let uploadURL = Self.endpoint(host: record.host, path: "/speedtest/upload.php") else {
            return nil
        }
        self.name = record.name
        self.sponsor = record.sponsor
        self.countryCode = record.countryCode
        self.latencyURL = latencyURL
        self.downloadURL = downloadURL
        self.uploadURL = uploadURL
    }

    /// `host` 来自目录的 host 字段，形如 `name.prod.hosts.ooklaserver.net:8080`。
    /// 直接连这个地址的 HTTPS，避免 legacy `url` 上的跳转。
    private static func endpoint(host: String, path: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var hostname = trimmed
        var port: Int?
        if let colon = trimmed.lastIndex(of: ":"),
           trimmed[trimmed.index(after: colon)...].allSatisfy(\.isNumber),
           let value = Int(trimmed[trimmed.index(after: colon)...]) {
            hostname = String(trimmed[..<colon])
            port = value
        }
        guard !hostname.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = hostname
        components.port = port
        components.path = path
        return components.url
    }
}

nonisolated struct OoklaServerRecord: Sendable, Equatable {
    var name: String
    var sponsor: String
    var countryCode: String
    var host: String
    var httpsFunctional: Bool
}

/// 按当前网络路径选择 Ookla 节点：直连时固定在香港，启用系统代理时跟随代理出口。
/// 公开目录里几乎没有大陆运营商节点，仅剩的教育网节点跨网严重偏慢，因此直连改用香港运营商节点。
nonisolated enum OoklaServerDirectory {
    static let nearestURL = URL(string: "https://www.speedtest.net/api/js/servers?engine=js&https_functional=true&limit=20")!
    static let hongKongURL = URL(string: "https://www.speedtest.net/api/js/servers?engine=js&https_functional=true&limit=20&search=Hong%20Kong")!
    private static let probeCount = 4
    /// 香港节点距离相近，到各节点的线路质量取决于用户所在运营商，因此全部参与探测。
    private static let hongKongProbeCount = 20

    private static let proxyEnableKeys = [
        "HTTPEnable",
        "HTTPSEnable",
        "SOCKSEnable",
        "ProxyAutoConfigEnable",
        "ProxyAutoDiscoveryEnable"
    ]

    static func decode(_ data: Data) throws -> [OoklaServerRecord] {
        try JSONDecoder().decode([RawRecord].self, from: data).compactMap(\.record)
    }

    /// 直连时只返回香港节点；使用系统代理时保留目录按代理出口返回的最近节点。
    static func candidates(
        nearest: [OoklaServerRecord],
        hongKong: [OoklaServerRecord],
        usesSystemProxy: Bool
    ) -> [OoklaServerRecord] {
        let nearestHTTPS = httpsRecords(nearest)
        if usesSystemProxy {
            return Array(nearestHTTPS.prefix(probeCount))
        }
        let nearestHongKongHTTPS = nearestHTTPS.filter(isHongKong)
        if !nearestHongKongHTTPS.isEmpty { return Array(nearestHongKongHTTPS.prefix(hongKongProbeCount)) }
        return Array(httpsRecords(hongKong).filter(isHongKong).prefix(hongKongProbeCount))
    }

    /// 返回可达的候选节点，按 HTTP 往返从快到慢排序；至少一台。
    static func rankedServers(session: URLSession, usesProxyRoute: Bool? = nil) async throws -> [SpeedTestServer] {
        try Task.checkCancellation()
        let usesProxyRoute = usesProxyRoute ?? systemProxyIsEnabled()
        let nearest = try await fetch(nearestURL, session: session)
        try Task.checkCancellation()
        let hongKong: [OoklaServerRecord]
        if usesProxyRoute || httpsRecords(nearest).contains(where: isHongKong) {
            hongKong = []
        } else {
            do {
                hongKong = try await fetch(hongKongURL, session: session)
            } catch {
                try Task.checkCancellation()
                hongKong = []
            }
        }
        let servers = candidates(
            nearest: nearest,
            hongKong: hongKong,
            usesSystemProxy: usesProxyRoute
        ).compactMap(SpeedTestServer.init(record:))
        let ranked = try await rankedByLatency(servers, session: session)
        guard !ranked.isEmpty else { throw SpeedTestError.noServer }
        return ranked
    }

    /// 读取 macOS 当前网络位置的系统代理开关。PAC/自动发现也按代理路径处理，
    /// 这样代理客户端切换出口后，目录返回的最近节点就会对应代理出口。
    static func systemProxyIsEnabled() -> Bool {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return false }
        return proxyEnableKeys.contains { key in
            (settings[key] as? NSNumber)?.boolValue == true
        }
    }

    /// URLSession 未显式覆盖代理时，沿用系统代理；空字典表示调用方明确要求直连。
    static func usesProxyRoute(for configuration: URLSessionConfiguration) -> Bool {
        if let proxy = configuration.connectionProxyDictionary {
            return !proxy.isEmpty
        }
        return systemProxyIsEnabled()
    }

    private static func isHongKong(_ record: OoklaServerRecord) -> Bool {
        record.countryCode.caseInsensitiveCompare("HK") == .orderedSame
    }

    private static func httpsRecords(_ records: [OoklaServerRecord]) -> [OoklaServerRecord] {
        records.filter { $0.httpsFunctional && !$0.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func fetch(_ url: URL, session: URLSession) async throws -> [OoklaServerRecord] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try SpeedTestEngine.validate(response)
        return try decode(data)
    }

    /// 同时探测全部候选，按 HTTP 往返从快到慢排序，不可达的节点剔除。
    /// 每台先发一次请求建立连接，再计第二次往返，避免 TCP/TLS 握手干扰排序。
    private static func rankedByLatency(_ servers: [SpeedTestServer], session: URLSession) async throws -> [SpeedTestServer] {
        try Task.checkCancellation()
        let samples = await withTaskGroup(of: (Int, Double)?.self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    let clock = ContinuousClock()
                    var elapsed: Double?
                    for _ in 0..<2 {
                        var request = URLRequest(url: server.latencyURL)
                        request.timeoutInterval = 2
                        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                        let start = clock.now
                        do {
                            let (_, response) = try await session.data(for: request)
                            try SpeedTestEngine.validate(response)
                        } catch {
                            return nil
                        }
                        elapsed = SpeedTestMath.seconds(start.duration(to: clock.now)) * 1_000
                    }
                    return elapsed.map { (index, $0) }
                }
            }
            var results: [(Int, Double)] = []
            for await sample in group {
                if let sample { results.append(sample) }
            }
            return results
        }
        try Task.checkCancellation()
        return samples.sorted { $0.1 < $1.1 }.map { servers[$0.0] }
    }
}

private nonisolated struct RawRecord: Decodable {
    var record: OoklaServerRecord? {
        guard let host, !host.isEmpty else { return nil }
        return OoklaServerRecord(
            name: name ?? "",
            sponsor: sponsor ?? "",
            countryCode: countryCode ?? "",
            host: host,
            httpsFunctional: httpsFunctional ?? false
        )
    }

    private var name: String?
    private var sponsor: String?
    private var countryCode: String?
    private var host: String?
    private var httpsFunctional: Bool?

    enum CodingKeys: String, CodingKey {
        case name, sponsor, host
        case countryCode = "cc"
        case httpsFunctional = "https_functional"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sponsor = try container.decodeIfPresent(String.self, forKey: .sponsor)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        if let enabled = try? container.decode(Int.self, forKey: .httpsFunctional) {
            httpsFunctional = enabled != 0
        } else if let enabled = try? container.decode(Bool.self, forKey: .httpsFunctional) {
            httpsFunctional = enabled
        } else if let enabled = try? container.decode(String.self, forKey: .httpsFunctional) {
            httpsFunctional = enabled == "1" || enabled.lowercased() == "true"
        } else {
            httpsFunctional = nil
        }
    }
}
