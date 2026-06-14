import SwiftUI

/// 复古 CRT 单色绿屏像素配色（黑色显示器 + 荧光绿内容）
enum TypeRacingPixelStyle {
    // 机身 / 外框：老式显示器的近黑塑料外壳
    static let terminalBG = Color(hex: 0x070807)
    static let terminalBGDark = Color(hex: 0x030403)
    static let bezel = Color(hex: 0x16191A)
    static let bezelDark = Color(hex: 0x0B0D0C)

    // 屏幕玻璃：几乎纯黑、带一丝磷光绿底色
    static let screenBG = Color(hex: 0x030A05)
    static let screenBGDark = Color(hex: 0x020602)

    // 荧光绿：高亮主光 + 柔和余辉
    static let screenGlow = Color(hex: 0x57FF7B)
    static let screenGlowSoft = Color(hex: 0x33C854)
    static let scanline = Color(hex: 0x000000)

    static let textPending = Color(hex: 0x4FE86E)
    static let textPendingDark = Color(hex: 0x46DC64)
    static let textCurrent = Color(hex: 0xC4FFD2)
    static let textDone = Color(hex: 0x276B39)
    static let textDoneDark = Color(hex: 0x1E5630)
    static let danger = Color(hex: 0xFF6B3D)

    static let runnerBody = Color(hex: 0x8BFF9F)
    static let runnerBodyDark = Color(hex: 0x78ED90)
    static let chaserBody = Color(hex: 0x46C25E)
    static let chaserBodyDark = Color(hex: 0x39A84F)

    static let hudText = Color(hex: 0xB6FFC6)

    static let carDotRadius: CGFloat = 5

    static func font(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    static func pendingText(isDark: Bool) -> Color {
        isDark ? textPendingDark : textPending
    }

    static func doneText(isDark: Bool) -> Color {
        isDark ? textDoneDark : textDone
    }

    static func runnerColor(isDark: Bool) -> Color {
        isDark ? runnerBodyDark : runnerBody
    }

    static func chaserColor(isDark: Bool) -> Color {
        isDark ? chaserBodyDark : chaserBody
    }
}

enum TypeRacingPixelRenderer {
    private static var cachedCircuit: TypeRacingCircuitTrack?
    private static var cachedCircuitSize: CGSize = .zero

    static func drawCircuit(
        context: GraphicsContext,
        size: CGSize,
        runnerPhase: CGFloat,
        chaserPhase: CGFloat,
        runnerColor: Color,
        chaserColor: Color
    ) {
        let circuit: TypeRacingCircuitTrack
        if let cached = cachedCircuit, cachedCircuitSize == size {
            circuit = cached
        } else {
            circuit = TypeRacingCircuitTrack(size: size)
            cachedCircuit = circuit
            cachedCircuitSize = size
        }

        let trackPath = circuit.trackPath

        // 磷光余辉：先描一圈柔和宽光晕，再叠清晰亮线
        context.stroke(
            trackPath,
            with: .color(TypeRacingPixelStyle.screenGlow.opacity(0.18)),
            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            trackPath,
            with: .color(TypeRacingPixelStyle.screenGlowSoft.opacity(0.7)),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )

        drawCarDot(
            context: context,
            at: circuit.point(at: chaserPhase),
            color: chaserColor,
            radius: TypeRacingPixelStyle.carDotRadius
        )
        drawCarDot(
            context: context,
            at: circuit.point(at: runnerPhase),
            color: runnerColor,
            radius: TypeRacingPixelStyle.carDotRadius + 0.5
        )
    }

    private static func drawCarDot(
        context: GraphicsContext,
        at center: CGPoint,
        color: Color,
        radius: CGFloat
    ) {
        let outer = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        // 光点外晕
        let haloRadius = radius + 4
        let halo = CGRect(
            x: center.x - haloRadius,
            y: center.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        )
        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.22)))
        context.fill(Path(ellipseIn: outer), with: .color(color))
        context.stroke(
            Path(ellipseIn: outer),
            with: .color(TypeRacingPixelStyle.screenGlow),
            lineWidth: 1
        )
    }
}
