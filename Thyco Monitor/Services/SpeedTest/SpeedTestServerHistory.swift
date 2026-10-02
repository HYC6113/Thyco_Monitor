import Foundation

/// 各节点近期的正式下载成绩，持久化于 UserDefaults。
/// 同一节点的表现主要取决于用户运营商和时段，比单次试测稳定；它只决定谁进入试测，最终仍由当次试测选出。
nonisolated struct SpeedTestServerHistory: Sendable {
    private struct Record: Codable {
        var megabits: Double
        var date: Date
    }

    private static let storageKey = "speedTestServerHistory"
    /// 过期后被排除的节点重新获得试测机会，换网络后旧成绩也不会长期左右选择。
    private static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let latencyFinalistCount = 3
    private static let historyFinalistCount = 2
    /// 成绩不到已知最好节点这个比例的节点不再参与试测。
    private static let exclusionRatio = 0.5

    /// 只保存 suite 名称：UserDefaults 本身未声明 Sendable。nil 表示标准域。
    private let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    static func key(for server: SpeedTestServer, usesProxyRoute: Bool) -> String {
        "\(usesProxyRoute ? "proxy" : "direct")|\(server.downloadURL.absoluteString)"
    }

    func megabits(now: Date = .now) -> [String: Double] {
        load().filter { now.timeIntervalSince($0.value.date) < Self.lifetime }.mapValues(\.megabits)
    }

    /// 与未过期的旧成绩各占一半，单次异常不会让好节点直接出局。
    func record(_ megabits: Double, for key: String, now: Date = .now) {
        guard megabits.isFinite, megabits > 0 else { return }
        var records = load().filter { now.timeIntervalSince($0.value.date) < Self.lifetime }
        let smoothed = records[key].map { ($0.megabits + megabits) / 2 } ?? megabits
        records[key] = Record(megabits: smoothed, date: now)
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// 延迟最低的几台加上历史成绩最好的两台进入试测，明显偏慢的节点剔除；结果保持延迟顺序在前。
    /// 没有历史时等同于只取延迟最低的几台。`ranked` 按延迟排序。
    static func finalists(ranked: [SpeedTestServer], megabits: [String: Double], key: (SpeedTestServer) -> String) -> [SpeedTestServer] {
        let best = ranked.compactMap { megabits[key($0)] }.max() ?? 0
        let eligible = ranked.filter { server in
            megabits[key(server)].map { $0 >= best * exclusionRatio } ?? true
        }
        let proven = eligible
            .compactMap { server in megabits[key(server)].map { (server, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(historyFinalistCount)
            .map(\.0)
        var seen = Set<String>()
        return (eligible.prefix(latencyFinalistCount) + proven).filter { seen.insert(key($0)).inserted }
    }

    private func load() -> [String: Record] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return [:]
        }
        return records
    }
}
