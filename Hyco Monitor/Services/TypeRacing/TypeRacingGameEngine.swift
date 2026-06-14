import Foundation
import Observation

enum TypeRacingPhase: Equatable {
    case ready
    case playing
    case caught
}

enum TypeRacingCharState: Equatable {
    case typed
    case current
    case pending
}

struct TypeRacingVisibleChar: Identifiable, Equatable {
    let index: Int
    let character: Character
    let x: CGFloat
    let state: TypeRacingCharState

    var id: Int { index }
}

@MainActor
@Observable
final class TypeRacingGameEngine {
    static let charWidth: CGFloat = 14
    static let catchLineX: CGFloat = 24
    static let laneHeight: CGFloat = 60
    /// 开局时追车落后玩家的小数圈比例（赛道长度的六分之一）
    static let startTrackGapFraction: CGFloat = 1 / 6

    private(set) var phase: TypeRacingPhase = .ready
    private(set) var distanceMeters: Int = 0
    private(set) var scrollSpeed: CGFloat = 28
    private(set) var streamOffset: CGFloat = 0
    private(set) var streamText: [Character] = []
    private(set) var streamIndex = 0
    private(set) var wrongFlash = false
    private(set) var bestDistanceMeters: Int = 0
    private(set) var roadTravel: CGFloat = 0

    /// 平滑后的打字余量，避免打对字符时间距突变
    private var smoothedHeadroom: CGFloat = 0

    /// 环形跑道：每圈对应的行程单位
    private let travelPerLap: CGFloat = 300

    /// 玩家车在跑道上的位置（0...1 为一圈）
    var runnerTrackPhase: CGFloat {
        (roadTravel / travelPerLap).truncatingRemainder(dividingBy: 1)
    }

    /// 追车在跑道上的位置（落后玩家若干比例）
    var chaserTrackPhase: CGFloat {
        var phase = runnerTrackPhase - displayedChaserLapGap
        if phase < 0 { phase += 1 }
        return phase
    }

    private var laneWidth: CGFloat = 500
    private var streamStartX: CGFloat = 360
    private var language: AppLanguage = .eng
    private var elapsed: TimeInterval = 0
    private var wrongFlashTask: Task<Void, Never>?

    private let baseScrollSpeed: CGFloat = 28
    private let maxScrollSpeed: CGFloat = 48
    private let speedRampDuration: TimeInterval = 110
    private let minStreamLength = 160
    /// 已离屏字符积压超过该阈值时触发数组压缩
    private let maxConsumedBacklog = 512
    /// 追车间距平滑系数（越大越快贴近真实余量，越小越柔和）
    private let chaserGapSmoothingRate: CGFloat = 7

    func configureLaneWidth(_ width: CGFloat) {
        laneWidth = max(320, width)
        streamStartX = laneWidth * 0.68
        if phase == .ready {
            streamOffset = 0
        }
    }

    func prepare(language: AppLanguage) {
        self.language = language
        bestDistanceMeters = TypeRacingHighScoreStore.best()
        resetToReady()
    }

    func beginIfReady() {
        guard phase == .ready else { return }
        startRun()
    }

    func restart() {
        startRun()
    }

    /// 清除 UserDefaults 中的游戏本地记录（如最佳里程）
    func clearLocalSavedData() {
        TypeRacingHighScoreStore.clearAll()
        bestDistanceMeters = 0
    }

    func tick(delta: TimeInterval) {
        guard phase == .playing, delta > 0, delta < 0.5 else { return }

        elapsed += delta
        scrollSpeed = currentScrollSpeed(at: elapsed)
        streamOffset += scrollSpeed * CGFloat(delta)
        roadTravel += scrollSpeed * CGFloat(delta)
        distanceMeters += max(1, Int(scrollSpeed * CGFloat(delta) * 0.11))

        advanceSmoothedHeadroom(delta: delta)
        ensureStreamBuffer()
        compactConsumedStreamIfNeeded()
        checkCaught()
    }

    func handleInput(_ raw: String) {
        for scalar in raw.unicodeScalars {
            handleSingleInput(Character(scalar))
        }
    }

    private func handleSingleInput(_ raw: Character) {
        guard let input = TypeRacingTextFactory.normalizedInput(raw) else { return }

        switch phase {
        case .ready:
            if input == " " { startRun() }
        case .playing:
            guard TypeRacingTextFactory.isTypingCharacter(input) else { return }
            guard streamIndex < streamText.count else { return }
            let expected = streamText[streamIndex]

            if input == expected {
                streamIndex += 1
                distanceMeters += 2
                advanceSmoothedHeadroom(delta: 1.0 / 60.0)
                ensureStreamBuffer()
                checkCaught()
            } else {
                // 已通过 isTypingCharacter 过滤，此处必为可打印字符（非换行）。
                triggerWrongFlash()
                scrollSpeed = min(maxScrollSpeed, scrollSpeed + 2)
                checkCaught()
            }
        case .caught:
            if input == " " || input == "\n" {
                restart()
            }
        }
    }

    func visibleCharacters() -> [TypeRacingVisibleChar] {
        guard !streamText.isEmpty else { return [] }

        var chars: [TypeRacingVisibleChar] = []
        chars.reserveCapacity(80)

        for i in streamIndex..<streamText.count {
            let x = streamStartX + CGFloat(i) * Self.charWidth - streamOffset
            
            // Because x is monotonically increasing, if we passed the right edge, we can stop evaluating
            if x >= laneWidth + Self.charWidth * 2 {
                break
            }
            
            // Skip characters that have passed the left edge
            if x <= -Self.charWidth {
                continue
            }

            let ch = streamText[i]
            let state: TypeRacingCharState
            if i < streamIndex {
                state = .typed
            } else if i == streamIndex {
                state = .current
            } else {
                state = .pending
            }
            chars.append(TypeRacingVisibleChar(index: i, character: ch, x: x, state: state))
        }
        
        // Let's also include typed characters that are still on screen, iterating backwards from streamIndex
        var i = streamIndex - 1
        while i >= 0 {
            let x = streamStartX + CGFloat(i) * Self.charWidth - streamOffset
            if x <= -Self.charWidth {
                break // Passed the left edge, stop backwards iteration
            }
            let ch = streamText[i]
            chars.insert(TypeRacingVisibleChar(index: i, character: ch, x: x, state: .typed), at: 0)
            i -= 1
        }
        
        return chars
    }

    // MARK: - Private

    private func resetToReady() {
        phase = .ready
        distanceMeters = 0
        scrollSpeed = baseScrollSpeed
        elapsed = 0
        streamOffset = 0
        streamText = []
        streamIndex = 0
        wrongFlash = false
        roadTravel = 0
        syncSmoothedHeadroomToTarget()
        resetStream()
    }

    private func startRun() {
        phase = .playing
        distanceMeters = 0
        scrollSpeed = baseScrollSpeed
        elapsed = 0
        streamIndex = 0
        streamOffset = 0
        wrongFlash = false
        roadTravel = 0
        syncSmoothedHeadroomToTarget()
        resetStream()
    }

    private func endRun() {
        phase = .caught
        bestDistanceMeters = TypeRacingHighScoreStore.saveIfHigher(distanceMeters)
    }

    private func currentCharX() -> CGFloat {
        streamStartX + CGFloat(streamIndex) * Self.charWidth - streamOffset
    }

    private var maxTypingHeadroom: CGFloat {
        max(1, streamStartX - Self.catchLineX)
    }

    private var targetTypingHeadroom: CGFloat {
        max(0, currentCharX() - Self.catchLineX)
    }

    /// 追车与玩家在圈上的弧长间距（1 = 整圈），由平滑余量驱动
    private var displayedChaserLapGap: CGFloat {
        switch phase {
        case .ready:
            return Self.startTrackGapFraction
        case .playing:
            let fraction = min(1, smoothedHeadroom / maxTypingHeadroom)
            return fraction * Self.startTrackGapFraction
        case .caught:
            return 0
        }
    }

    private func syncSmoothedHeadroomToTarget() {
        smoothedHeadroom = targetTypingHeadroom
    }

    private func advanceSmoothedHeadroom(delta: TimeInterval) {
        guard phase == .playing, delta > 0 else { return }
        let target = targetTypingHeadroom
        let alpha = min(1, CGFloat(delta) * chaserGapSmoothingRate)
        smoothedHeadroom += (target - smoothedHeadroom) * alpha
    }

    private func currentScrollSpeed(at elapsed: TimeInterval) -> CGFloat {
        let progress = min(1, max(0, elapsed / speedRampDuration))
        return baseScrollSpeed + (maxScrollSpeed - baseScrollSpeed) * CGFloat(progress)
    }

    private func checkCaught() {
        guard phase == .playing, currentCharX() <= Self.catchLineX else { return }
        endRun()
    }

    private func triggerWrongFlash() {
        wrongFlash = true
        wrongFlashTask?.cancel()
        wrongFlashTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            wrongFlash = false
        }
    }

    private func resetStream() {
        streamText = Array(TypeRacingTextFactory.initialStream())
        streamIndex = 0
    }

    /// 保证未打字符缓冲不少于 `minStreamLength`，不足时持续补足。
    private func ensureStreamBuffer() {
        while streamText.count - streamIndex < minStreamLength {
            streamText.append(contentsOf: TypeRacingTextFactory.appendChunk())
        }
    }

    /// 丢弃已滚出屏幕左侧的已打字符，避免长时间游玩时 `streamText` 无限增长。
    /// 通过同步减少 `streamOffset` 保证剩余字符的绘制位置完全不变。
    private func compactConsumedStreamIfNeeded() {
        guard streamIndex > maxConsumedBacklog else { return }

        // 离屏判定：x = streamStartX + i * charWidth - streamOffset <= -charWidth
        let lastOffscreenIndex = Int(floor((streamOffset - streamStartX - Self.charWidth) / Self.charWidth))
        let dropCount = min(streamIndex, lastOffscreenIndex)
        guard dropCount > maxConsumedBacklog else { return }

        streamText.removeFirst(dropCount)
        streamIndex -= dropCount
        streamOffset -= CGFloat(dropCount) * Self.charWidth
    }
}

// MARK: - Text factory

enum TypeRacingTextFactory {
    static let charset: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyz;,."
    )
    private static let allowedInput = Set(charset)

    static func isTypingCharacter(_ character: Character) -> Bool {
        guard let normalized = normalizedInput(character) else { return false }
        return allowedInput.contains(normalized)
    }

    /// 统一为小写并修剪，便于与随机字母流比对（兼容大写与全角标点）
    static func normalizedInput(_ character: Character) -> Character? {
        if character == "\n" || character == "\r" { return character }
        if character == "\u{3000}" { return " " }

        let text = String(character)
        if text == "；" { return ";" }
        if text == "，" { return "," }
        if text == "．" || text == "。" { return "." }

        if text.count == 1, let ascii = text.lowercased().first {
            return ascii
        }
        return nil
    }

    static func initialStream() -> String {
        var result = ""
        while result.count < 140 {
            result += appendChunk()
        }
        return result
    }

    static func appendChunk() -> String {
        let length = Int.random(in: 4...11)
        var chunk = ""
        chunk.reserveCapacity(length + 1)
        for _ in 0..<length {
            chunk.append(charset.randomElement()!)
        }
        return chunk
    }
}

enum TypeRacingHighScoreStore {
    private static let key = "typeRacing.best"

    static func best() -> Int {
        UserDefaults.standard.integer(forKey: key)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    @discardableResult
    static func saveIfHigher(_ score: Int) -> Int {
        let current = best()
        let updated = max(current, score)
        if updated > current {
            UserDefaults.standard.set(updated, forKey: key)
        }
        return updated
    }
}
