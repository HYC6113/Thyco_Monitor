import AppKit
import Combine
import SwiftUI

struct TypeRacingGameView: View {
    let language: AppLanguage
    let colorScheme: ColorScheme
    let onClose: () -> Void

    @State private var engine = TypeRacingGameEngine()
    /// 帧计时基准放在引用类型里，更新它不会触发 SwiftUI 视图失效，
    /// 避免游戏结束/待开始时仍以 60fps 重绘（重绘含模糊与提示卡片，拖动会卡顿）。
    @State private var frameClock = FrameClock()
    /// 只创建一次的帧计时器，避免每次 body 求值都重建发布者。
    @State private var frameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    @State private var isEscCapsuleHovering = false
    @State private var isClearDataHovering = false

    private var strings: MonitorStrings {
        MonitorStrings(language: language)
    }

    private var isDark: Bool { colorScheme == .dark }

    /// 顶栏 ESC / 清除 等胶囊统一高度
    private static let headerCapsuleHeight: CGFloat = 20
    private static let headerCapsuleStroke: CGFloat = 0.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelChrome

            VStack(spacing: 0) {
                panelHeader
                gameContentBlock
                    .padding(.horizontal, TypeRacingWindowLayout.outerPadding)
                    .padding(.bottom, TypeRacingWindowLayout.outerPadding)
            }
        }
        .frame(
            width: TypeRacingWindowLayout.width,
            height: TypeRacingWindowLayout.contentHeight
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: TypeRacingWindowLayout.panelCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            TypeRacingKeyCaptureView(onInput: handleKeyInput)
                .frame(
                    width: TypeRacingWindowLayout.width,
                    height: TypeRacingWindowLayout.contentHeight
                        - TypeRacingWindowLayout.panelHeaderHeight
                )
                .offset(y: TypeRacingWindowLayout.panelHeaderHeight)
        }
        .onAppear {
            engine.prepare(language: language)
            frameClock.last = Date()
        }
        .onReceive(frameTimer) { now in
            let last = frameClock.last
            frameClock.last = now
            // 仅在游戏进行中推进与重绘；其余阶段画面静止，不产生逐帧失效。
            guard engine.phase == .playing else { return }
            engine.tick(delta: now.timeIntervalSince(last))
        }
        .preferredColorScheme(colorScheme)
    }

    // MARK: - 浮动面板外观

    private var panelChrome: some View {
        RoundedRectangle(cornerRadius: TypeRacingWindowLayout.panelCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: TypeRacingWindowLayout.panelCornerRadius, style: .continuous)
                    .fill((isDark ? TypeRacingPixelStyle.terminalBGDark : TypeRacingPixelStyle.terminalBG).opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TypeRacingWindowLayout.panelCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                TypeRacingPixelStyle.screenGlowSoft.opacity(isDark ? 0.35 : 0.28),
                                Color.white.opacity(isDark ? 0.06 : 0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            exitHintBar
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
                .background(TypeRacingWindowDragArea())
            clearSavedDataControl
        }
        .padding(.top, TypeRacingWindowLayout.panelHeaderTopInset)
        .padding(.horizontal, 14)
        .frame(height: TypeRacingWindowLayout.panelHeaderHeight, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var exitHintBar: some View {
        HStack(spacing: 4) {
            escExitCapsule
            Text(strings.typeRacingExitSuffix)
                .font(TypeRacingPixelStyle.font(size: 10))
                .foregroundStyle(TypeRacingPixelStyle.screenGlowSoft.opacity(0.75))
        }
    }

    private var escExitCapsule: some View {
        Button(action: onClose) {
            Text(strings.cleanModeExitKey)
                .font(TypeRacingPixelStyle.font(size: 11))
                .foregroundStyle(
                    TypeRacingPixelStyle.screenGlowSoft.opacity(isEscCapsuleHovering ? 1 : 0.9)
                )
                .frame(height: Self.headerCapsuleHeight)
                .padding(.horizontal, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(TypeRacingPixelStyle.screenGlowSoft.opacity(isEscCapsuleHovering ? 0.18 : 0.1))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            TypeRacingPixelStyle.screenGlowSoft.opacity(isEscCapsuleHovering ? 0.55 : 0.4),
                            lineWidth: Self.headerCapsuleStroke
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(height: Self.headerCapsuleHeight)
        .contentShape(Capsule())
        .onHover { isEscCapsuleHovering = $0 }
    }

    private var clearSavedDataControl: some View {
        HStack(spacing: 6) {
            if isClearDataHovering {
                Text(strings.typeRacingClearSavedData)
                    .font(TypeRacingPixelStyle.font(size: 10))
                    .foregroundStyle(TypeRacingPixelStyle.screenGlowSoft.opacity(0.82))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity)
            }
            clearSavedDataCapsule
        }
        .animation(.easeOut(duration: 0.15), value: isClearDataHovering)
        .onHover { isClearDataHovering = $0 }
    }

    private var clearSavedDataCapsule: some View {
        Button {
            engine.clearLocalSavedData()
        } label: {
            Image(systemName: Self.resolvedSFSymbolName(preferred: ["broom", "broom.fill"], fallback: "eraser.fill"))
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    clearDataIconPrimary,
                    clearDataIconSecondary
                )
                .imageScale(.medium)
                .frame(width: 28, height: Self.headerCapsuleHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(TypeRacingPixelStyle.screenGlowSoft.opacity(isClearDataHovering ? 0.16 : 0.09))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            TypeRacingPixelStyle.screenGlowSoft.opacity(isClearDataHovering ? 0.48 : 0.34),
                            lineWidth: Self.headerCapsuleStroke
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(height: Self.headerCapsuleHeight)
        .contentShape(Capsule())
        .accessibilityLabel(strings.typeRacingClearSavedData)
    }

    private var clearDataIconPrimary: Color {
        TypeRacingPixelStyle.screenGlowSoft.opacity(isClearDataHovering ? 0.95 : 0.82)
    }

    private var clearDataIconSecondary: Color {
        TypeRacingPixelStyle.screenGlowSoft.opacity(isClearDataHovering ? 0.55 : 0.42)
    }

    /// 选用当前系统实际存在的 SF Symbol 名称
    private static func resolvedSFSymbolName(preferred: [String], fallback: String) -> String {
        for name in preferred {
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                return name
            }
        }
        if NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil {
            return fallback
        }
        return "trash"
    }

    // MARK: - 游戏主内容（赛道 + 打字带，底边两角与面板外框同心）

    private var gameContentBlock: some View {
        VStack(spacing: 0) {
            gameStage
            typingLane
        }
        .clipShape(gameContentBottomShape)
        .overlay(
            gameContentBottomShape
                .strokeBorder(Color.black.opacity(0.5), lineWidth: 2)
        )
    }

    private var gameContentBottomShape: UnevenRoundedRectangle {
        let radius = TypeRacingWindowLayout.contentBottomCornerRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - 游戏带（CRT 单色像素屏）

    private var showsStageMessage: Bool {
        engine.phase == .ready || engine.phase == .caught
    }

    private var gameStage: some View {
        let bezel = isDark ? TypeRacingPixelStyle.bezelDark : TypeRacingPixelStyle.bezel

        return ZStack {
            Rectangle()
                .fill(bezel)

            gameStagePlayfield
                .blur(radius: showsStageMessage ? 7 : 0)
                .brightness(showsStageMessage ? -0.06 : 0)
                .animation(.easeOut(duration: 0.22), value: showsStageMessage)

            distanceHUD
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 10)
                .padding(.trailing, 12)

            if engine.phase == .ready {
                stageMessageOverlay { readyOverlay }
            }

            if engine.phase == .caught {
                stageMessageOverlay { caughtOverlay }
            }
        }
        .frame(height: TypeRacingWindowLayout.sceneHeight)
    }

    private var gameStagePlayfield: some View {
        let screenBG = isDark ? TypeRacingPixelStyle.screenBGDark : TypeRacingPixelStyle.screenBG

        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(screenBG)
                .padding(6)

            circuitRaceTrack
                .padding(6)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.clear)
                .overlay { scanlineOverlay }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(6)
                .allowsHitTesting(false)
        }
        .drawingGroup()
    }

    private var circuitRaceTrack: some View {
        Canvas { context, size in
            TypeRacingPixelRenderer.drawCircuit(
                context: context,
                size: size,
                runnerPhase: engine.runnerTrackPhase,
                chaserPhase: engine.chaserTrackPhase,
                runnerColor: TypeRacingPixelStyle.runnerColor(isDark: isDark),
                chaserColor: TypeRacingPixelStyle.chaserColor(isDark: isDark)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanlineOverlay: some View {
        Canvas { context, size in
            // 中心磷光晕染：屏幕中心更亮，营造发光感
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let bloom = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            context.fill(
                Path(bloom),
                with: .radialGradient(
                    Gradient(colors: [
                        TypeRacingPixelStyle.screenGlow.opacity(0.10),
                        .clear
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.6
                )
            )

            // 扫描线：逐行压暗，复古 CRT 行栅
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                let line = CGRect(x: 0, y: y, width: size.width, height: 1.4)
                context.fill(Path(line), with: .color(TypeRacingPixelStyle.scanline.opacity(0.5)))
                y += step
            }

            // 暗角（晕影）：四周压暗，模拟显像管玻璃边缘
            context.fill(
                Path(bloom),
                with: .radialGradient(
                    Gradient(colors: [
                        .clear,
                        .black.opacity(0.45)
                    ]),
                    center: center,
                    startRadius: min(size.width, size.height) * 0.32,
                    endRadius: max(size.width, size.height) * 0.72
                )
            )

            // 边框内发光
            let glow = bloom.insetBy(dx: 1, dy: 1)
            context.stroke(
                Path(roundedRect: glow, cornerRadius: 5),
                with: .color(TypeRacingPixelStyle.screenGlow.opacity(0.28)),
                lineWidth: 1.5
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 打字带扫描线（与主屏一致的 CRT 行栅）
    private var laneScanlineOverlay: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                let line = CGRect(x: 0, y: y, width: size.width, height: 1.4)
                context.fill(Path(line), with: .color(TypeRacingPixelStyle.scanline.opacity(0.45)))
                y += step
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var distanceHUD: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(strings.typeRacingDistance)
                .font(TypeRacingPixelStyle.font(size: 10))
                .foregroundStyle(TypeRacingPixelStyle.hudText.opacity(0.75))
            Text("\(engine.distanceMeters) m")
                .font(TypeRacingPixelStyle.font(size: 18))
                .foregroundStyle(TypeRacingPixelStyle.hudText)
                .monospacedDigit()
        }
        .shadow(color: TypeRacingPixelStyle.screenGlow.opacity(0.28), radius: 3, x: 0, y: 0)
    }

    // MARK: - 底部打字带（加大；已打字符保留并变淡）

    private var typingLane: some View {
        let laneWidth = TypeRacingWindowLayout.typingLaneWidth
        let laneBG = isDark ? TypeRacingPixelStyle.screenBGDark : TypeRacingPixelStyle.screenBG

        return ZStack(alignment: .leading) {
            Color.clear
                .onAppear { engine.configureLaneWidth(laneWidth) }

            Rectangle()
                .fill(laneBG)
                .overlay {
                    laneScanlineOverlay
                        .allowsHitTesting(false)
                }

            ZStack(alignment: .leading) {
                ForEach(engine.visibleCharacters()) { item in
                    let snappedX = item.x.rounded(.down)
                    Text(String(item.character))
                        .font(TypeRacingPixelStyle.font(size: 22))
                        .foregroundStyle(color(for: item.state))
                        .shadow(color: glowColor(for: item.state), radius: glowRadius(for: item.state))
                        .shadow(color: glowColor(for: item.state).opacity(0.5), radius: glowRadius(for: item.state) * 2)
                        .position(x: snappedX, y: TypeRacingGameEngine.laneHeight / 2)
                }
            }
            .frame(width: laneWidth, height: TypeRacingGameEngine.laneHeight)
            .clipped()

            Rectangle()
                .fill(TypeRacingPixelStyle.danger)
                .frame(width: 3)
                .shadow(color: TypeRacingPixelStyle.danger.opacity(0.8), radius: 4)
                .offset(x: TypeRacingGameEngine.catchLineX - 1)
                .zIndex(1)
                .allowsHitTesting(false)
        }
        .frame(width: laneWidth, height: TypeRacingGameEngine.laneHeight)
        .frame(maxWidth: .infinity)
        .frame(height: TypeRacingWindowLayout.typingHeight, alignment: .center)
    }

    private func color(for state: TypeRacingCharState) -> Color {
        switch state {
        case .typed:
            return TypeRacingPixelStyle.doneText(isDark: isDark)
        case .pending:
            return TypeRacingPixelStyle.pendingText(isDark: isDark)
        case .current:
            if engine.wrongFlash {
                return TypeRacingPixelStyle.danger
            }
            return TypeRacingPixelStyle.textCurrent
        }
    }

    /// 字符磷光晕染颜色
    private func glowColor(for state: TypeRacingCharState) -> Color {
        switch state {
        case .typed:
            return .clear
        case .pending:
            return TypeRacingPixelStyle.screenGlow.opacity(0.35)
        case .current:
            return engine.wrongFlash
                ? TypeRacingPixelStyle.danger.opacity(0.7)
                : TypeRacingPixelStyle.screenGlow.opacity(0.85)
        }
    }

    private func glowRadius(for state: TypeRacingCharState) -> CGFloat {
        switch state {
        case .typed: return 0
        case .pending: return 1.5
        case .current: return 3
        }
    }

    private func stageMessageOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.28)
            content()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                .background {
                    let shape = RoundedRectangle(
                        cornerRadius: TypeRacingWindowLayout.messageCardCornerRadius,
                        style: .continuous
                    )
                    ZStack {
                        shape.fill(Color.black.opacity(0.7))
                        // 卡片内的磷光中心晕染
                        shape.fill(
                            RadialGradient(
                                colors: [
                                    TypeRacingPixelStyle.screenGlow.opacity(0.10),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        // 卡片内扫描线，与屏幕一致的 CRT 质感
                        laneScanlineOverlay
                            .clipShape(shape)
                            .opacity(0.7)
                    }
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: TypeRacingWindowLayout.messageCardCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        TypeRacingPixelStyle.screenGlowSoft.opacity(0.6),
                        lineWidth: 1
                    )
                }
                .shadow(color: TypeRacingPixelStyle.screenGlow.opacity(0.25), radius: 8)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
    }

    private var readyOverlay: some View {
        VStack(spacing: 6) {
            Text(strings.typeRacingReadyTitle)
                .font(TypeRacingPixelStyle.font(size: 13))
                .foregroundStyle(TypeRacingPixelStyle.hudText)
            Text(strings.typeRacingReadyHint)
                .font(TypeRacingPixelStyle.font(size: 10))
                .foregroundStyle(TypeRacingPixelStyle.screenGlowSoft)
        }
    }

    private var caughtOverlay: some View {
        VStack(spacing: 6) {
            Text(strings.typeRacingCaughtTitle)
                .font(TypeRacingPixelStyle.font(size: 13))
                .foregroundStyle(TypeRacingPixelStyle.danger)
            Text(strings.typeRacingCaughtHint)
                .font(TypeRacingPixelStyle.font(size: 10))
                .foregroundStyle(TypeRacingPixelStyle.screenGlowSoft)
            if engine.bestDistanceMeters > 0 {
                Text(strings.typeRacingBest(engine.bestDistanceMeters))
                    .font(TypeRacingPixelStyle.font(size: 11))
                    .foregroundStyle(TypeRacingPixelStyle.hudText)
                    .shadow(color: TypeRacingPixelStyle.screenGlow.opacity(0.4), radius: 2)
                    .padding(.top, 2)
            }
        }
    }

    private func handleKeyInput(_ text: String) -> Bool {
        if text == "\u{1B}" {
            onClose()
            return true
        }
        engine.handleInput(text)
        return true
    }
}

// MARK: - 帧计时容器

/// 引用类型的帧计时基准：更新其属性不会触发 SwiftUI 视图失效。
private final class FrameClock {
    var last = Date()
}

// MARK: - 拖动标题栏

private struct TypeRacingWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> TypeRacingWindowDragNSView {
        TypeRacingWindowDragNSView()
    }

    func updateNSView(_ nsView: TypeRacingWindowDragNSView, context: Context) {}
}

private final class TypeRacingWindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Key capture

private struct TypeRacingKeyCaptureView: NSViewRepresentable {
    let onInput: (String) -> Bool

    func makeNSView(context: Context) -> TypeRacingKeyCaptureNSView {
        let view = TypeRacingKeyCaptureNSView()
        view.onInput = onInput
        return view
    }

    func updateNSView(_ nsView: TypeRacingKeyCaptureNSView, context: Context) {
        nsView.onInput = onInput
    }
}

private final class TypeRacingKeyCaptureNSView: NSView {
    var onInput: ((String) -> Bool)?
    private var handledByKeyDown = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            _ = onInput?("\u{1B}")
            return
        }

        if event.isARepeat { return }

        handledByKeyDown = false

        if let mapped = TypeRacingKeyInput.normalizedGameCharacter(from: event) {
            handledByKeyDown = true
            if onInput?(String(mapped)) == true { return }
        }

        if let chars = event.characters, chars.count == 1, let ch = chars.first,
           let normalized = TypeRacingTextFactory.normalizedInput(ch),
           TypeRacingTextFactory.isTypingCharacter(normalized) {
            handledByKeyDown = true
            if onInput?(String(normalized)) == true { return }
        }

        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any) {
        if handledByKeyDown {
            handledByKeyDown = false
            return
        }
        guard let text = insertString as? String, !text.isEmpty else { return }
        var accepted = ""
        for ch in text {
            guard let normalized = TypeRacingTextFactory.normalizedInput(ch),
                  TypeRacingTextFactory.isTypingCharacter(normalized) else { continue }
            accepted.append(normalized)
        }
        guard !accepted.isEmpty else { return }
        _ = onInput?(accepted)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

#Preview("Type Racing") {
    TypeRacingGameView(language: .eng, colorScheme: .light, onClose: {})
        .frame(
            width: TypeRacingWindowLayout.width,
            height: TypeRacingWindowLayout.contentHeight
        )
}
