import SwiftUI

// MARK: - Layout Constants

enum MonitorPanelLayout {
    /// 整体界面等比例缩放（设计稿尺寸 × scale = 实际 NSPanel 尺寸）
    static let scale: CGFloat = 0.84

    static let designWidth: CGFloat = 520

    static let panelWidth: CGFloat = (designWidth * scale).rounded(.toNearestOrAwayFromZero)
    static let panelHeight: CGFloat = (designHeight * scale).rounded(.toNearestOrAwayFromZero)

    static let contentInsets: EdgeInsets = CardRhythm.cardInset
    static let contentAreaWidth: CGFloat = designWidth - contentInsets.leading - contentInsets.trailing

    static let cardSpacing: CGFloat = 10

    static let cardWidth: CGFloat = (contentAreaWidth - cardSpacing) / 2
    static let topGridCardHeight: CGFloat = 182
    static let bottomGridCardHeight: CGFloat = 182
    /// 声音板块内容高度（两行控件 + 分隔线 + 区块间距）
    static let soundCardContentHeight: CGFloat = 114.5
    /// 顶/底内边距与侧面一致（13pt），内容区无额外留白
    static let soundCardHeight: CGFloat =
        CardRhythm.cardInset.top + soundCardContentHeight + CardRhythm.cardInset.bottom
    static let headerHeight: CGFloat = 28
    static let footerHeight: CGFloat = 20
    /// 充电功率胶囊文字区固定宽度（适配「充电功率 100W / Chg. 100W」）
    static let chargingPowerCapsuleContentWidth: CGFloat = 88

    /// 上方四张卡片区域高度（两行 + 行间距）
    static let upperCardsHeight: CGFloat = topGridCardHeight + cardSpacing + bottomGridCardHeight

    /// 五张卡片区域总高度（含行/列间距）
    static let monitorCardsHeight: CGFloat = upperCardsHeight + cardSpacing + soundCardHeight

    static let contentHeight: CGFloat =
        headerHeight + monitorCardsHeight + footerHeight + (cardSpacing * 2)

    static let designHeight: CGFloat = contentHeight + contentInsets.top + contentInsets.bottom
}

/// 卡片内部排版节奏
enum CardRhythm {
    static let sectionGap: CGFloat = 11
    static let itemGap: CGFloat = 7
    static let rowGap: CGFloat = 6
    static let labelGap: CGFloat = 4
    static let memoryHeaderBottomSpacing: CGFloat = 8
    static let memoryRowMinHeight: CGFloat = 31
    static let cardInset = EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)

    /// 三张卡片共用的顶部指标区高度。内容底部对齐后，
    /// 顶部文字到卡片上边缘的距离因此完全一致。
    static let metricHeaderAreaHeight: CGFloat = 67
    /// 顶部指标区与下半部分之间的间距；配合固定高度，下半部分仍停留在原位。
    static let metricToLowerGap: CGFloat = 10
    /// 存储卡片下半部分比 CPU/电池低 2pt；同时为卡片底部留出 3pt 余量。
    static let storageHeaderToLowerGap: CGFloat = metricToLowerGap + 2
}

/// 全界面统一视觉参数（对齐 Thyco 精简版 Sound 板块）
enum MonitorTheme {
    static let borderLineWidth: CGFloat = 0.5

    // 设计稿坐标系连续圆角（随 ContentView scaleEffect 等比缩放）
    // 等比级数：20 → 14 → 9 → 6
    static let panelCornerRadius: CGFloat = 20
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 9
    static let minorCornerRadius: CGFloat = 6

    static func continuousRect(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static let panelShape = continuousRect(panelCornerRadius)
    static let controlShape = continuousRect(controlCornerRadius)
    static let minorShape = continuousRect(minorCornerRadius)
    static let capsuleShape = Capsule(style: .continuous)

    static func panelBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.055), Color.white.opacity(0.015)]
                : [Color.black.opacity(0.05), Color.black.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.06), Color.white.opacity(0.015)]
                : [Color.black.opacity(0.06), Color.black.opacity(0.025)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 底部语言切换胶囊的描边，比普通卡片略强。
    static func capsuleBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.18), Color.white.opacity(0.08)]
                : [Color.black.opacity(0.13), Color.black.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 浮层下拉列表描边：比卡片略强，便于与底层毛玻璃区分
    static func menuListBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.14), Color.white.opacity(0.05)]
                : [Color.black.opacity(0.08), Color.black.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func controlBorderColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.06)
    }

    static func subtleBorderColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.045)
    }

    /// 充电状态与内存压力「正常」状态共用的正向绿色。
    static func positiveGreen(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x30D158) : Color(hex: 0x34C759)
    }

    /// 卡片与语言选中胶囊共用的表面填充色。
    static func selectedSurfaceFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? MonitorDarkPalette.languageSelectedFill
            : MonitorLightPalette.languageSelectedFill
    }

    static let capsuleTrackHeight: CGFloat = 8
    static let sliderTrackHeight: CGFloat = 9
    static let sectionTitleTracking: CGFloat = 1.1

    static func sectionTitleTracking(for language: AppLanguage) -> CGFloat {
        language == .eng ? 0 : sectionTitleTracking
    }
}

/// 暗色模式统一色板
enum MonitorDarkPalette {
    static let panelBase = Color(hex: 0x17171A)
    static let cardBase = Color(hex: 0x232327)

    /// 轻量毛玻璃：用稍亮一点的底色降低“黑板”的沉重感，
    /// 但纯色叠层保持较高浓度，避免桌面内容透进来造成杂乱。
    static let panelOverlayOpacity: Double = 0.68
    static let controlFill = Color.white.opacity(0.06)
    static let iconButtonOverlay = cardBase.opacity(0.42)
    static let cardDivider = Color.white.opacity(0.08)
    static let languageTrackFill = cardBase.opacity(0.30)
    static let languageSelectedFill = cardBase.opacity(0.42)
    static let menuListOverlayOpacity: Double = 0.30
    static let sliderTrackFill = Color.white.opacity(0.10)
    static let valuePillFill = Color.white.opacity(0.08)
    static let progressTrackFill = Color.white.opacity(0.10)
}

/// 浅色模式统一色板
enum MonitorLightPalette {
    /// 纯白底色：浅色模式要的是“亮”，不是透出桌面颜色。
    static let panelBase = Color(hex: 0xFFFFFF)

    /// 轻量毛玻璃：用高亮纯色叠层把面板提亮，同时保持足够浓度，
    /// 不依赖高透明度来取巧，避免杂乱的背景透色。
    static let panelOverlayOpacity: Double = 0.64
    static let controlFill = Color.black.opacity(0.045)
    static let iconButtonOverlay = Color.white.opacity(0.58)
    static let languageTrackFill = Color.black.opacity(0.07)
    static let languageSelectedFill = Color.white.opacity(0.70)
    static let menuListOverlayOpacity: Double = 0.22
}

/// 面板内文字与控件的取色表。按 `colorScheme` 取预置实例，
/// 避免在每个视图里重复展开深浅色三元表达式，也省去逐个透传颜色参数。
struct MonitorPalette {
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let controlBackground: Color
    let cardBorder: Color
    let accent: Color
    let batteryCharging: Color
    let batteryLow: Color

    static let dark = MonitorPalette(
        primaryText: Color(hex: 0xF5F5F7),
        secondaryText: Color(hex: 0xA8A8AD),
        tertiaryText: Color(hex: 0x6E6E73),
        controlBackground: MonitorDarkPalette.controlFill,
        cardBorder: MonitorDarkPalette.cardDivider,
        accent: Color(hex: 0x0A84FF),
        batteryCharging: MonitorTheme.positiveGreen(for: .dark),
        batteryLow: Color(hex: 0xE06458)
    )

    static let light = MonitorPalette(
        primaryText: Color(hex: 0x1D1D1F),
        secondaryText: Color(hex: 0x5E5E63),
        tertiaryText: Color(hex: 0x76767C),
        controlBackground: MonitorLightPalette.controlFill,
        cardBorder: Color.black.opacity(0.06),
        accent: Color(hex: 0x006FE6),
        batteryCharging: MonitorTheme.positiveGreen(for: .light),
        batteryLow: Color(hex: 0xD95048)
    )

    static func of(_ colorScheme: ColorScheme) -> MonitorPalette {
        colorScheme == .dark ? .dark : .light
    }
}

extension View {
    func monitorControlShadow(colorScheme: ColorScheme) -> some View {
        shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.06 : 0.022),
            radius: colorScheme == .dark ? 2.5 : 1.5,
            x: 0,
            y: colorScheme == .dark ? 0.8 : 0.4
        )
    }

    /// 卡片悬浮阴影：降低浓度、略微放大半径，让卡片像浮在玻璃上而不是压在上面
    func monitorCardShadow(colorScheme: ColorScheme) -> some View {
        shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.06),
            radius: colorScheme == .dark ? 3.5 : 3.5,
            x: 0,
            y: colorScheme == .dark ? 1.8 : 1.4
        )
    }

    /// 浮层下拉列表阴影：与紧凑布局匹配的轻量双层投影
    func monitorMenuListShadow(colorScheme: ColorScheme) -> some View {
        shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.13),
            radius: colorScheme == .dark ? 12 : 10,
            x: 0,
            y: colorScheme == .dark ? 5 : 4
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06),
            radius: 1.5,
            x: 0,
            y: 0.8
        )
    }

    func monitorCardCell(width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height, alignment: .topLeading)
    }

    func monitorCardRowSlot(height: CGFloat) -> some View {
        frame(height: height, alignment: .topLeading)
    }
}