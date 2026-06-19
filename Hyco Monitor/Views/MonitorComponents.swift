import SwiftUI

// MARK: - Reusable Components

struct CircleIconButton: View {
    enum Style {
        case neutral
        case accent
        case theme(isDark: Bool)
    }

    private static let diameter: CGFloat = 28
    private static let iconPointSize: CGFloat = 11

    let symbolName: String
    var style: Style = .neutral
    var accent: Color = Color(hex: 0x0A84FF)
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            switch style {
            case .neutral:
                Image(systemName: symbolName)
                    .font(.system(size: Self.iconPointSize, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? Color(hex: 0x8E8E93) : Color(hex: 0x86868B))
                    .frame(width: Self.diameter, height: Self.diameter)
                    .background(colorScheme == .dark ? MonitorDarkPalette.neutralButtonFill : Color.black.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(MonitorTheme.subtleBorderColor(for: colorScheme), lineWidth: MonitorTheme.borderLineWidth)
                    )
            case .accent:
                materialCircleIcon(foreground: accent, iconWeight: .heavy, gradientForeground: true)
            case .theme(let isDark):
                materialCircleIcon(foreground: isDark ? Color(hex: 0xFFD60A) : Color(hex: 0xFF9500))
            }
        }
        .buttonStyle(.plain)
        .frame(width: Self.diameter, height: Self.diameter)
    }

    private func materialCircleIcon(
        foreground: Color,
        iconWeight: Font.Weight = .semibold,
        gradientForeground: Bool = false
    ) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: Self.iconPointSize, weight: iconWeight))
            .foregroundStyle(
                gradientForeground
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [foreground, foreground.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    : AnyShapeStyle(foreground)
            )
            .frame(width: Self.diameter, height: Self.diameter)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(
                                colorScheme == .dark
                                    ? MonitorDarkPalette.iconButtonOverlay
                                    : MonitorLightPalette.iconButtonOverlay
                            )
                    )
            }
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(MonitorTheme.controlBorderColor(for: colorScheme), lineWidth: MonitorTheme.borderLineWidth)
            )
    }
}

struct MonitorCard<Content: View>: View {
    var title: String?
    let colorScheme: ColorScheme
    var titleTracking: CGFloat = MonitorTheme.sectionTitleTracking
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        colorScheme: ColorScheme,
        titleTracking: CGFloat = MonitorTheme.sectionTitleTracking,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.colorScheme = colorScheme
        self.titleTracking = titleTracking
        self.content = content()
    }

    private var cardSurfaceFill: Color {
        colorScheme == .dark
            ? MonitorDarkPalette.cardBase.opacity(MonitorDarkPalette.cardSurfaceOpacity)
            : MonitorLightPalette.cardBase.opacity(MonitorLightPalette.cardSurfaceOpacity)
    }

    private var cardSurfaceHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(MonitorDarkPalette.cardSheenOpacity)
            : Color.white.opacity(MonitorLightPalette.cardSheenOpacity)
    }

    private var innerPadding: EdgeInsets { CardRhythm.cardInset }

    @ViewBuilder
    private var cardBorderOverlay: some View {
        MonitorTheme.cardShape
            .strokeBorder(
                MonitorTheme.cardBorderGradient(for: colorScheme),
                lineWidth: MonitorTheme.borderLineWidth
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(titleTracking)
                    .padding(.bottom, CardRhythm.titleGap)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(innerPadding)
        .background {
            MonitorTheme.cardShape
                .fill(.ultraThinMaterial)
                .overlay(
                    MonitorTheme.cardShape
                        .fill(cardSurfaceFill)
                )
                .overlay(
                    MonitorTheme.cardShape
                        .fill(cardSurfaceHighlight)
                )
        }
        .clipShape(MonitorTheme.cardShape)
        .overlay { cardBorderOverlay }
        .compositingGroup()
        .monitorCardShadow(colorScheme: colorScheme)
    }
}

struct CardSectionDivider: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
    }
}

struct BatteryChargingIcon: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

enum LiveMetricLeadingAccessoryLayout {
    static let iconSpacing: CGFloat = 3
    static let iconWidth: CGFloat = 10
    static var overlayOffset: CGFloat { -(iconWidth + iconSpacing) }
}

struct LiveMetricBlock<LeadingAccessory: View>: View {
    private let valueFontSize: CGFloat = 25

    let value: String
    let unit: String
    let label: String
    let secondaryText: Color
    let primaryText: Color
    var valueColor: Color? = nil
    var overlaysLeadingAccessory = false
    @ViewBuilder private var leadingAccessory: () -> LeadingAccessory

    init(
        value: String,
        unit: String,
        label: String,
        secondaryText: Color,
        primaryText: Color,
        valueColor: Color? = nil,
        overlaysLeadingAccessory: Bool = false,
        @ViewBuilder leadingAccessory: @escaping () -> LeadingAccessory
    ) {
        self.value = value
        self.unit = unit
        self.label = label
        self.secondaryText = secondaryText
        self.primaryText = primaryText
        self.valueColor = valueColor
        self.overlaysLeadingAccessory = overlaysLeadingAccessory
        self.leadingAccessory = leadingAccessory
    }

    @ViewBuilder
    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor ?? primaryText)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardRhythm.labelGap) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)

            if overlaysLeadingAccessory {
                valueRow
                    .overlay(alignment: .leading) {
                        leadingAccessory()
                            .offset(x: LiveMetricLeadingAccessoryLayout.overlayOffset)
                    }
            } else {
                HStack(alignment: .center, spacing: 5) {
                    leadingAccessory()
                    valueRow
                }
            }
        }
    }
}

extension LiveMetricBlock where LeadingAccessory == EmptyView {
    init(
        value: String,
        unit: String,
        label: String,
        secondaryText: Color,
        primaryText: Color,
        valueColor: Color? = nil
    ) {
        self.init(
            value: value,
            unit: unit,
            label: label,
            secondaryText: secondaryText,
            primaryText: primaryText,
            valueColor: valueColor,
            leadingAccessory: { EmptyView() }
        )
    }
}

struct StorageStatItem: View {
    let label: String
    let value: String
    let secondaryText: Color
    let primaryText: Color
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(primaryText)
                .monospacedDigit()
        }
    }
}

struct StorageCleanerLaunchButton: View {
    let appName: String?
    let appIcon: NSImage?
    let strings: MonitorStrings
    let accent: Color
    let controlBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let onOpen: () -> Void
    let onPick: () -> Void
    let onClear: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isConfigured: Bool { appName != nil }

    private static let textMaxWidth: CGFloat = 76
    private static let iconTextSpacing: CGFloat = 3
    private static let contentWidth: CGFloat = 14 + iconTextSpacing + textMaxWidth

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Self.iconTextSpacing) {
                iconView
                Text(buttonTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isConfigured ? primaryText : accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.textMaxWidth)
            }
            .frame(width: Self.contentWidth, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(buttonBackground)
            .clipShape(MonitorTheme.controlShape)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(strings.openCleanerApp, action: onOpen)
                .disabled(!isConfigured)
            Button(strings.changeCleanerApp, action: onPick)
            if isConfigured {
                Divider()
                Button(strings.clearCleanerApp, role: .destructive, action: onClear)
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "plus.app")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 14, height: 14)
        }
    }

    private var buttonTitle: String {
        if let appName {
            return appName
        }
        return strings.pickCleanerApp
    }

    private var helpText: String {
        isConfigured ? strings.openCleanerApp : strings.pickCleanerApp
    }

    private var buttonBackground: Color {
        isHovering
            ? controlBackground.opacity(colorScheme == .dark ? 1.15 : 1.05)
            : controlBackground
    }
}

struct NetworkThroughput: View {
    let label: String
    let value: String
    let secondaryText: Color
    let primaryText: Color
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: CardRhythm.labelGap) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)
            Text(value)
                .font(.system(size: emphasized ? 13 : 12, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? primaryText : secondaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, emphasized ? 0 : 10)
        .padding(.leading, emphasized ? 10 : 0)
    }
}

struct TypeRacingEntryButton: View {
    let accent: Color
    let secondaryText: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "steeringwheel")
                    .font(.system(size: 10, weight: .semibold))
                Text("Type Racing")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isHovering ? accent : secondaryText.opacity(0.88))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Type Racing")
    }
}

struct ToggleRow: View {
    private static let switchHorizontalScale: CGFloat = 1.14

    let title: String
    @Binding var isOn: Bool
    var showDivider: Bool = false
    let border: Color
    let titleColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(titleColor)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .scaleEffect(x: Self.switchHorizontalScale, y: 1.0, anchor: .trailing)
        }
        .padding(.vertical, CardRhythm.rowGap)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle()
                    .fill(border)
                    .frame(height: 0.5)
            }
        }
    }
}

struct MemoryColumn: View {
    let title: String
    let titleTracking: CGFloat
    let entries: [(MemoryMetricKey, String, Bool)]
    let strings: MonitorStrings
    let secondaryText: Color
    let primaryText: Color
    let cardBorder: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(titleTracking)
                .lineLimit(1)
                .padding(.bottom, CardRhythm.memoryHeaderBottomSpacing)

            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(strings.memoryLabel(for: entry.0))
                        .foregroundStyle(secondaryText)
                        .font(.system(size: 11, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                    Spacer(minLength: 4)
                    Text(entry.1)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                .frame(minHeight: CardRhythm.memoryRowMinHeight, alignment: .center)
                .overlay(alignment: .bottom) {
                    if index < entries.count - 1 {
                        Rectangle()
                            .fill(cardBorder)
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LanguageTrackCapsuleChrome: ViewModifier {
    let colorScheme: ColorScheme

    private var trackSurfaceFill: Color {
        colorScheme == .dark
            ? MonitorDarkPalette.languageTrackFill
            : MonitorLightPalette.languageTrackFill
    }

    func body(content: Content) -> some View {
        content
            .padding(2)
            .background {
                MonitorTheme.capsuleShape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        MonitorTheme.capsuleShape
                            .fill(trackSurfaceFill)
                    )
                    .overlay(
                        MonitorTheme.capsuleShape
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.025)
                                    : Color.white.opacity(0.045)
                            )
                    )
            }
            .clipShape(MonitorTheme.capsuleShape)
            .overlay {
                MonitorTheme.capsuleShape
                    .strokeBorder(
                        MonitorTheme.cardBorderGradient(for: colorScheme),
                        lineWidth: MonitorTheme.borderLineWidth
                    )
            }
            .monitorControlShadow(colorScheme: colorScheme)
    }
}

extension View {
    func languageTrackCapsuleChrome(colorScheme: ColorScheme) -> some View {
        modifier(LanguageTrackCapsuleChrome(colorScheme: colorScheme))
    }
}

struct LanguageSegmentedControl: View {
    @Binding var selection: AppLanguage
    let colorScheme: ColorScheme
    let primaryText: Color
    let tertiaryText: Color

    private var selectedBorderOpacity: Double {
        colorScheme == .dark ? 0.09 : 0.20
    }

    private var selectedSurfaceFill: Color {
        colorScheme == .dark
            ? MonitorDarkPalette.languageSelectedFill
            : MonitorLightPalette.languageSelectedFill
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = language
                    }
                } label: {
                    Text(language.segmentTitle)
                        .font(.system(size: 10, weight: selection == language ? .semibold : .medium))
                        .foregroundStyle(selection == language ? primaryText : tertiaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background {
                            if selection == language {
                                MonitorTheme.capsuleShape
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        MonitorTheme.capsuleShape
                                            .fill(selectedSurfaceFill)
                                    )
                                    .overlay(
                                        MonitorTheme.capsuleShape
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.05))
                                    )
                                    .overlay(
                                        MonitorTheme.capsuleShape
                                            .strokeBorder(
                                                Color.white.opacity(selectedBorderOpacity),
                                                lineWidth: MonitorTheme.borderLineWidth
                                            )
                                    )
                            }
                        }
                        .contentShape(MonitorTheme.capsuleShape)
                }
                .buttonStyle(.plain)
            }
        }
        .languageTrackCapsuleChrome(colorScheme: colorScheme)
    }
}

// MARK: - Panel Components (Hyco 精简版风格)

struct PanelCapsuleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accent: Color
    var showTooltip: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var isDragging = false

    private let trackHeight: CGFloat = MonitorTheme.sliderTrackHeight

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let rangeSpan = max(range.upperBound - range.lowerBound, 0.001)
            let normalizedValue = (value - range.lowerBound) / rangeSpan
            let clampedNormalized = min(max(normalizedValue, 0), 1)
            let fillWidth = width * CGFloat(clampedNormalized)

            ZStack(alignment: .leading) {
                MonitorTheme.capsuleShape
                    .fill(colorScheme == .dark ? MonitorDarkPalette.sliderTrackFill : Color.black.opacity(0.08))
                    .frame(height: trackHeight)

                MonitorTheme.capsuleShape
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, fillWidth), height: trackHeight)
                    .shadow(color: accent.opacity(0.22), radius: 2.5, x: 0, y: 1)

                if showTooltip && (isHovering || isDragging) {
                    Text("\(Int(value) > 0 ? "+" : "")\(Int(value))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tooltipTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tooltipBackground, in: MonitorTheme.minorShape)
                        .overlay(
                            MonitorTheme.minorShape
                                .strokeBorder(tooltipBorder, lineWidth: MonitorTheme.borderLineWidth)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 3, x: 0, y: 1)
                        .fixedSize()
                        .position(x: fillWidth, y: geometry.size.height / 2 - 16)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isHovering = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let x = gesture.location.x
                        let newValue = (x / width) * rangeSpan + range.lowerBound
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }

    private var tooltipBackground: Color {
        colorScheme == .dark ? Color(white: 0.95) : Color(white: 0.18)
    }

    private var tooltipTextColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    private var tooltipBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.12)
    }
}

/// 与面板风格统一的设备选择下拉列表（替代系统 NSMenu 弹窗）
struct PanelMenuList: View {
    let options: [String]
    let selected: String
    let colorScheme: ColorScheme
    let accent: Color
    let primaryText: Color
    let secondaryText: Color
    let onSelect: (String) -> Void

    @State private var hoveredOption: String?

    private let rowHeight: CGFloat = 28
    private let maxVisibleRows = 6

    var visibleHeight: CGFloat {
        let rows = min(options.count, maxVisibleRows)
        return CGFloat(rows) * rowHeight + 8
    }

    var body: some View {
        Group {
            if options.count > maxVisibleRows {
                ScrollView(.vertical, showsIndicators: false) { rows }
                    .frame(height: visibleHeight)
            } else {
                rows
            }
        }
        .background { listBackground }
        .clipShape(MonitorTheme.controlShape)
        .overlay {
            MonitorTheme.controlShape
                .strokeBorder(
                    MonitorTheme.menuListBorderGradient(for: colorScheme),
                    lineWidth: MonitorTheme.borderLineWidth
                )
        }
        .compositingGroup()
        .monitorMenuListShadow(colorScheme: colorScheme)
    }

    private var rows: some View {
        VStack(spacing: 1) {
            ForEach(options, id: \.self) { option in
                rowView(option)
            }
        }
        .padding(4)
    }

    private func rowView(_ option: String) -> some View {
        let isSelected = option == selected
        let isHovered = hoveredOption == option

        return HStack(alignment: .center, spacing: 6) {
            Text(option)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? accent : primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isHovered {
                MonitorTheme.minorShape
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
            } else if isSelected {
                MonitorTheme.minorShape
                    .fill(accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredOption = hovering ? option : (hoveredOption == option ? nil : hoveredOption)
        }
        .onTapGesture { onSelect(option) }
    }

    private var listOverlayFill: Color {
        colorScheme == .dark
            ? MonitorDarkPalette.cardBase.opacity(MonitorDarkPalette.menuListOverlayOpacity)
            : MonitorLightPalette.panelBase.opacity(MonitorLightPalette.menuListOverlayOpacity)
    }

    private var listBackground: some View {
        MonitorTheme.controlShape
            .fill(.thinMaterial)
            .overlay(
                MonitorTheme.controlShape
                    .fill(listOverlayFill)
            )
    }
}

struct PanelValuePill: View {
    let text: String
    let colorScheme: ColorScheme
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    pillLabel
                }
                .buttonStyle(.plain)
            } else {
                pillLabel
            }
        }
    }

    private var pillLabel: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(colorScheme == .dark ? MonitorDarkPalette.valuePillFill : Color.black.opacity(0.06))
            .clipShape(MonitorTheme.capsuleShape)
            .overlay(
                MonitorTheme.capsuleShape
                    .strokeBorder(MonitorTheme.subtleBorderColor(for: colorScheme), lineWidth: MonitorTheme.borderLineWidth)
            )
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

struct PanelWaveformView: View {
    let value: Double
    let colorScheme: ColorScheme

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 3
    private let maxBarHeight: CGFloat = 12
    private let containerHeight: CGFloat = 16
    private let animationSpeed: Double = 2.4

    var body: some View {
        Group {
            if value > 0 {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                    waveformBars(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                waveformBars(phase: 0)
            }
        }
        .frame(height: containerHeight)
    }

    private func waveformBars(phase: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                MonitorTheme.capsuleShape
                    .fill(barColor)
                    .frame(width: barWidth, height: barHeight(for: index, phase: phase))
            }
        }
        .frame(height: containerHeight)
    }

    private var barColor: Color {
        let baseOpacity = colorScheme == .dark ? 0.42 : 0.32
        let volumeGain = (value / 100.0) * 0.45
        return (colorScheme == .dark ? Color.white : Color.black)
            .opacity(min(baseOpacity + volumeGain, 0.85))
    }

    private func barHeight(for index: Int, phase: TimeInterval) -> CGFloat {
        guard value > 0 else { return minBarHeight }

        let volumeRatio = CGFloat(value / 100.0)
        let dynamicAmp = (maxBarHeight - minBarHeight) * max(volumeRatio, 0.45)
        let t = phase * animationSpeed
        let i = Double(index)
        let w1 = sin(t + i * 0.5)
        let w2 = cos(t * 1.5 - i * 0.3) * 0.5
        let normalized = ((w1 + w2) / 1.5 + 1.0) / 2.0
        return minBarHeight + dynamicAmp * CGFloat(normalized)
    }
}

struct PanelChannelBadge: View {
    private static let diameter: CGFloat = 18
    private static let fontSize: CGFloat = 10

    let label: String
    var onDoubleTap: (() -> Void)?

    init(label: String, onDoubleTap: (() -> Void)? = nil) {
        self.label = label
        self.onDoubleTap = onDoubleTap
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: MonitorTheme.borderLineWidth)

            Text(label)
                .font(.system(size: Self.fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Circle())
        .onTapGesture(count: 2) {
            onDoubleTap?()
        }
    }
}

// MARK: - Custom Styles

struct PanelCapsuleProgressStyle: ProgressViewStyle {
    let colorScheme: ColorScheme
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let progress = configuration.fractionCompleted ?? 0
        let track = colorScheme == .dark ? MonitorDarkPalette.progressTrackFill : Color.black.opacity(0.08)

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                MonitorTheme.capsuleShape
                    .fill(track)

                MonitorTheme.capsuleShape
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geometry.size.width * progress, progress > 0 ? 6 : 0))
                    .shadow(color: accent.opacity(0.22), radius: 2, y: 0.5)
            }
        }
    }
}

// MARK: - Utilities

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview("Light") {
    ContentView(viewModel: .preview)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView(viewModel: .preview)
        .preferredColorScheme(.dark)
}
