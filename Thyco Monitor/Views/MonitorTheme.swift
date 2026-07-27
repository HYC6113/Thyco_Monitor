import SwiftUI

// MARK: - Layout Constants

enum MonitorPanelLayout {
    /// 整体界面等比例缩放（设计稿尺寸 × scale = 实际 NSPanel 尺寸）
    static let scale: CGFloat = 0.84

    static let designWidth: CGFloat = 520

    static var panelWidth: CGFloat { (designWidth * scale).rounded(.toNearestOrAwayFromZero) }
    static var panelHeight: CGFloat { (designHeight * scale).rounded(.toNearestOrAwayFromZero) }

    static var contentInsets: EdgeInsets { CardRhythm.cardInset }
    static var contentAreaWidth: CGFloat {
        designWidth - contentInsets.leading - contentInsets.trailing
    }

    static let cardSpacing: CGFloat = 10

    static var cardWidth: CGFloat {
        (contentAreaWidth - cardSpacing) / 2
    }
    static let topGridCardHeight: CGFloat = 182
    static let bottomGridCardHeight: CGFloat = 182
    /// 声音板块内容高度（两行控件 + 分隔线 + 区块间距）
    static let soundCardContentHeight: CGFloat = 114.5
    /// 顶/底内边距与侧面一致（13pt），内容区无额外留白
    static var soundCardHeight: CGFloat {
        CardRhythm.cardInset.top + soundCardContentHeight + CardRhythm.cardInset.bottom
    }
    static let headerHeight: CGFloat = 28
    static let footerHeight: CGFloat = 20
    /// 充电功率胶囊文字区固定宽度（适配「充电功率 100W / Chg. 100W」）
    static let chargingPowerCapsuleContentWidth: CGFloat = 88

    /// 上方四张卡片区域高度（两行 + 行间距）
    static var upperCardsHeight: CGFloat {
        topGridCardHeight + cardSpacing + bottomGridCardHeight
    }

    /// 五张卡片区域总高度（含行/列间距）
    static var monitorCardsHeight: CGFloat {
        upperCardsHeight + cardSpacing + soundCardHeight
    }

    static var contentHeight: CGFloat {
        headerHeight
            + monitorCardsHeight
            + footerHeight
            + (cardSpacing * 2)
    }

    static var designHeight: CGFloat {
        contentHeight + contentInsets.top + contentInsets.bottom
    }
}

/// 卡片内部排版节奏
enum CardRhythm {
    static let titleGap: CGFloat = 8
    static let sectionGap: CGFloat = 11
    static let itemGap: CGFloat = 7
    static let rowGap: CGFloat = 6
    static let labelGap: CGFloat = 4
    static let memoryHeaderBottomSpacing: CGFloat = titleGap
    static let memoryRowMinHeight: CGFloat = 31
    static let cardInset = EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
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

    /// NSPanel 外层裁切圆角（换算为缩放后的物理像素）
    static var scaledPanelCornerRadius: CGFloat {
        (panelCornerRadius * MonitorPanelLayout.scale).rounded(.toNearestOrAwayFromZero)
    }

    static func continuousRect(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static var panelShape: RoundedRectangle { continuousRect(panelCornerRadius) }
    static var cardShape: RoundedRectangle { continuousRect(cardCornerRadius) }
    static var controlShape: RoundedRectangle { continuousRect(controlCornerRadius) }
    static var minorShape: RoundedRectangle { continuousRect(minorCornerRadius) }
    static var scaledPanelShape: RoundedRectangle { continuousRect(scaledPanelCornerRadius) }
    static var capsuleShape: Capsule { Capsule(style: .continuous) }

    static func panelBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.07), Color.white.opacity(0.02)]
                : [Color.white.opacity(0.34), Color.white.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.08), Color.white.opacity(0.02)]
                : [Color.white.opacity(0.30), Color.white.opacity(0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 浮层下拉列表描边：比卡片略强，便于与底层毛玻璃区分
    static func menuListBorderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.16), Color.white.opacity(0.06)]
                : [Color.white.opacity(0.56), Color.black.opacity(0.09)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func controlBorderColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    static func subtleBorderColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035)
    }

    static let capsuleTrackHeight: CGFloat = 8
    static let sliderTrackHeight: CGFloat = 9
    static let sectionTitleTracking: CGFloat = 1.1

    static func sectionTitleTracking(for language: AppLanguage) -> CGFloat {
        language == .eng ? 0 : sectionTitleTracking
    }

    static func accentColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x0A84FF) : Color(hex: 0x007AFF)
    }
}

/// 暗色模式统一色板
enum MonitorDarkPalette {
    static let panelBase = Color(hex: 0x101012)
    static let cardBase = Color(hex: 0x18181A)

    /// 实色叠层：保留毛玻璃透底，同时稳定可读性
    /// （叠层略放轻、白色 sheen 收敛，减少深色玻璃的奶灰膜，使观感更通透）
    static let panelOverlayOpacity: Double = 0.66
    static let panelSheenOpacity: Double = 0.016
    static let cardSurfaceOpacity: Double = 0.38
    static let cardSheenOpacity: Double = 0.018
    static let controlFill = Color.white.opacity(0.065)
    static let iconButtonOverlay = cardBase.opacity(0.38)
    static let cardDivider = Color.white.opacity(0.08)
    static let neutralButtonFill = Color.white.opacity(0.06)
    static let languageTrackFill = cardBase.opacity(0.30)
    static let languageSelectedFill = cardBase.opacity(0.40)
    static let menuListOverlayOpacity: Double = 0.30
    static let sliderTrackFill = Color.white.opacity(0.10)
    static let valuePillFill = Color.white.opacity(0.08)
    static let progressTrackFill = Color.white.opacity(0.10)
}

/// 浅色模式统一色板
enum MonitorLightPalette {
    /// 偏纯净的冷白底色（替代原灰色 0xF2F2F7），去除浅色玻璃的灰蒙蒙感
    static let panelBase = Color(hex: 0xFAFBFE)
    static let cardBase = Color.white

    static let panelOverlayOpacity: Double = 0.50
    static let panelSheenOpacity: Double = 0.075
    static let cardSurfaceOpacity: Double = 0.36
    static let cardSheenOpacity: Double = 0.06
    static let controlFill = Color.black.opacity(0.045)
    static let iconButtonOverlay = Color.white.opacity(0.58)
    static let languageTrackFill = Color.white.opacity(0.24)
    static let languageSelectedFill = Color.white.opacity(0.34)
    static let menuListOverlayOpacity: Double = 0.22
}

extension View {
    func monitorControlShadow(colorScheme: ColorScheme) -> some View {
        shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.024),
            radius: colorScheme == .dark ? 2.5 : 1.5,
            x: 0,
            y: colorScheme == .dark ? 0.8 : 0.4
        )
    }

    /// 卡片悬浮阴影：边距收紧后略收敛，避免贴边时阴影显得过重
    func monitorCardShadow(colorScheme: ColorScheme) -> some View {
        shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.075),
            radius: colorScheme == .dark ? 2.5 : 3,
            x: 0,
            y: colorScheme == .dark ? 1.5 : 1.2
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