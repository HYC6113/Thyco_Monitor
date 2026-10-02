import Foundation

/// 公网身份。字段优先来自 Cloudflare 专用元数据接口，缺的部分再用 IP 查询补齐。
nonisolated struct PublicNetworkInfo: Sendable, Equatable {
    var ip: String = ""
    var countryCode: String?
    var countryName: String?
    var region: String?
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var timeZoneID: String?
    var isp: String?
    var asn: String?
    var colo: String?
    var chinese: ChineseIPLocation?

    var hasContent: Bool {
        !ip.isEmpty || city != nil || countryCode != nil || timeZoneID != nil
    }

    /// 面板各行都有数据；地区可能本来就没有，不作要求。
    var isComplete: Bool {
        !ip.isEmpty && countryCode != nil && city != nil && timeZoneID != nil && (isp != nil || asn != nil)
    }

    func fillingGaps(from other: PublicNetworkInfo) -> PublicNetworkInfo {
        // 分流代理、IPv4/IPv6 或换网可能让查询服务看到不同出口；不能跨 IP 拼接字段。
        guard !ip.isEmpty else { return other }
        guard ip.lowercased() == other.ip.lowercased() else { return self }
        var copy = self
        if copy.countryCode == nil { copy.countryCode = other.countryCode }
        if copy.countryName == nil { copy.countryName = other.countryName }
        if copy.region == nil { copy.region = other.region }
        if copy.city == nil { copy.city = other.city }
        if copy.latitude == nil { copy.latitude = other.latitude }
        if copy.longitude == nil { copy.longitude = other.longitude }
        if copy.timeZoneID == nil { copy.timeZoneID = other.timeZoneID }
        if copy.isp == nil { copy.isp = other.isp }
        if copy.asn == nil { copy.asn = other.asn }
        if copy.colo == nil { copy.colo = other.colo }
        if copy.chinese == nil { copy.chinese = other.chinese }
        return copy
    }

    static func cloudflareMeta(_ data: Data) -> PublicNetworkInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else { return nil }

        var info = PublicNetworkInfo()
        info.ip = stringValue(payload["clientIp"]) ?? ""
        info.countryCode = stringValue(payload["country"])
        info.region = stringValue(payload["region"])
        info.city = stringValue(payload["city"])
        info.timeZoneID = stringValue(payload["timezone"])
        info.isp = stringValue(payload["asOrganization"])
        info.asn = stringValue(payload["asn"])
        info.colo = stringValue(payload["colo"])
        info.latitude = doubleValue(payload["latitude"])
        info.longitude = doubleValue(payload["longitude"])
        return info.hasContent ? info : nil
    }

    /// Cloudflare trace 是元数据接口不可用时的轻量备用，只提供出口 IP、国家和 Colo。
    static func cloudflareTrace(_ data: Data) -> PublicNetworkInfo? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let fields = text.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            result[parts[0]] = parts[1]
        }
        var info = PublicNetworkInfo()
        info.ip = fields["ip"] ?? ""
        info.countryCode = fields["loc"]
        info.colo = fields["colo"]
        return info.hasContent ? info : nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

/// 中国大陆 IP 的中文归属。国际 IP 库对国内 IP 的城市精度不足，运营商也只有英文名；仅中文界面使用。
nonisolated struct ChineseIPLocation: Sendable, Equatable {
    var province: String?
    var city: String?
    var isp: String?

    private static let carrierNames = [("电信", "中国电信"), ("联通", "中国联通"), ("移动", "中国移动"), ("广电", "中国广电")]
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
    ))

    /// 太平洋 IP 库按 GBK 返回 JSON。它不支持 IPv6，会改查请求方自己的 IP，因此必须核对 IP。
    static func pconline(_ data: Data, ip: String) -> ChineseIPLocation? {
        guard let text = String(data: data, encoding: gb18030),
              let payload = try? JSONDecoder().decode(PconlinePayload.self, from: Data(text.utf8)),
              payload.ip == ip,
              payload.err?.isEmpty != false else { return nil }
        let location = ChineseIPLocation(
            province: nonEmpty(payload.pro),
            city: nonEmpty(payload.city),
            isp: payload.addr.flatMap(carrier(from:))
        )
        return location.city != nil || location.isp != nil ? location : nil
    }

    /// `addr` 形如「广东省深圳市 电信」，运营商在最后一个空格之后。
    private static func carrier(from addr: String) -> String? {
        let parts = addr.split(separator: " ")
        guard parts.count >= 2, let last = parts.last else { return nil }
        let token = String(last)
        return carrierNames.first { token.contains($0.0) }?.1 ?? token
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private nonisolated struct PconlinePayload: Decodable {
    var ip: String?
    var pro: String?
    var city: String?
    var addr: String?
    var err: String?
}

nonisolated enum NetworkIdentityService {
    private static let ipWhoURL = URL(string: "https://ipwho.is/")!
    private static let ipSBURL = URL(string: "https://api.ip.sb/geoip")!
    private static let cloudflareMetaURL = URL(string: "https://speed.cloudflare.com/meta")!
    private static let cloudflareTraceURL = URL(string: "https://speed.cloudflare.com/cdn-cgi/trace")!
    private static let pconlineURL = URL(string: "https://whois.pconline.com.cn/ipJson.jsp")!

    private static func cloudflareMetaInfo(session: URLSession) async -> PublicNetworkInfo? {
        var request = URLRequest(url: cloudflareMetaURL)
        request.timeoutInterval = 4
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }
        return PublicNetworkInfo.cloudflareMeta(data)
    }

    private static func cloudflareTraceInfo(session: URLSession) async -> PublicNetworkInfo? {
        var request = URLRequest(url: cloudflareTraceURL)
        request.timeoutInterval = 4
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }
        return PublicNetworkInfo.cloudflareTrace(data)
    }

    static func fetch() async -> PublicNetworkInfo? {
        guard !Task.isCancelled else { return nil }
        // 每次刷新都新建会话，确保用户刚切换系统代理后不会继续复用旧出口。
        let session = URLSession(configuration: SpeedTestEngine.sessionConfiguration())
        defer { session.invalidateAndCancel() }

        // Cloudflare 元数据通常已包含全部字段，第三方 IP 库只在缺字段时依次补齐，少让一方看到出口 IP。
        // 身份刷新与选服并行，顺序请求的额外耗时被选服时间覆盖。
        var merged = PublicNetworkInfo()
        let sources: [@Sendable (URLSession) async -> PublicNetworkInfo?] = [
            { session in
                if let meta = await cloudflareMetaInfo(session: session) { return meta }
                return await cloudflareTraceInfo(session: session)
            },
            { await ipWhoInfo(session: $0) },
            { await ipSBInfo(session: $0) }
        ]
        for source in sources {
            guard !merged.isComplete, !Task.isCancelled else { break }
            if let info = await source(session) {
                merged = merged.fillingGaps(from: info)
            }
        }
        // 按已确定的出口 IP 查询，不受分流代理影响。
        if merged.countryCode?.uppercased() == "CN", !Task.isCancelled {
            merged.chinese = await pconlineInfo(ip: merged.ip, session: session)
        }
        guard !Task.isCancelled else { return nil }
        return merged.hasContent ? merged : nil
    }

    private static func pconlineInfo(ip: String, session: URLSession) async -> ChineseIPLocation? {
        let url = pconlineURL.appending(queryItems: [
            URLQueryItem(name: "ip", value: ip),
            URLQueryItem(name: "json", value: "true")
        ])
        guard let data = try? await getData(url, session: session) else { return nil }
        return ChineseIPLocation.pconline(data, ip: ip)
    }

    private static func ipWhoInfo(session: URLSession) async -> PublicNetworkInfo? {
        guard let data = try? await getData(ipWhoURL, session: session),
              let payload = try? JSONDecoder().decode(IPWhoPayload.self, from: data),
              payload.success != false else {
            return nil
        }
        var info = PublicNetworkInfo()
        info.ip = payload.ip ?? ""
        info.countryCode = payload.countryCode
        info.countryName = payload.country
        info.region = payload.region
        info.city = payload.city
        info.latitude = payload.latitude
        info.longitude = payload.longitude
        info.timeZoneID = payload.timezone?.id
        info.isp = payload.connection?.isp ?? payload.connection?.org
        if let asn = payload.connection?.asn {
            info.asn = String(asn)
        }
        return info.hasContent ? info : nil
    }

    private static func ipSBInfo(session: URLSession) async -> PublicNetworkInfo? {
        guard let data = try? await getData(ipSBURL, session: session),
              let payload = try? JSONDecoder().decode(IPSBPayload.self, from: data) else {
            return nil
        }
        var info = PublicNetworkInfo()
        info.ip = payload.ip ?? ""
        info.countryCode = payload.countryCode
        info.countryName = payload.country
        info.region = payload.region
        info.city = payload.city
        info.latitude = payload.latitude
        info.longitude = payload.longitude
        info.timeZoneID = payload.timezone
        info.isp = payload.isp ?? payload.asnOrganization ?? payload.organization
        if let asn = payload.asn {
            info.asn = String(asn)
        }
        return info.hasContent ? info : nil
    }

    private static func getData(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // 备用来源按顺序请求，超时不宜过长，否则全部不可达时等待会叠加。
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try SpeedTestEngine.validate(response)
        return data
    }
}

private nonisolated struct IPWhoPayload: Decodable {
    var success: Bool?
    var ip: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var connection: Connection?
    var timezone: Zone?

    struct Connection: Decodable {
        var asn: Int?
        var org: String?
        var isp: String?
    }

    struct Zone: Decodable {
        var id: String?
    }

    enum CodingKeys: String, CodingKey {
        case success, ip, country, region, city, latitude, longitude, connection, timezone
        case countryCode = "country_code"
    }
}

private nonisolated struct IPSBPayload: Decodable {
    var ip: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
    var isp: String?
    var organization: String?
    var asn: Int?
    var asnOrganization: String?
    var timezone: String?
    var latitude: Double?
    var longitude: Double?

    enum CodingKeys: String, CodingKey {
        case ip, country, region, city, isp, organization, asn, timezone, latitude, longitude
        case countryCode = "country_code"
        case asnOrganization = "asn_organization"
    }
}
