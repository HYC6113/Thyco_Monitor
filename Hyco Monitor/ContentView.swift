import AppKit
import SwiftUI

enum SoundDeviceKind: Hashable {
    case output
    case input
}

private struct PickerAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [SoundDeviceKind: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SoundDeviceKind: Anchor<CGRect>],
        nextValue: () -> [SoundDeviceKind: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ContentView: View {
    var viewModel: SystemMonitorViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var openDevicePicker: SoundDeviceKind?

    private var strings: MonitorStrings {
        MonitorStrings(language: viewModel.appLanguage)
    }

    private var sectionTitleTracking: CGFloat {
        MonitorTheme.sectionTitleTracking(for: viewModel.appLanguage)
    }

    private var outputDeviceOptionNames: [String] {
        viewModel.outputDevices.map(\.name)
    }

    private var inputDeviceOptionNames: [String] {
        viewModel.inputDevices.map(\.name)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelBackgroundMaterial

            VStack(spacing: MonitorPanelLayout.cardSpacing) {
                headerSection
                upperMonitorCardGrid
                soundCard
                    .monitorCardCell(
                        width: MonitorPanelLayout.contentAreaWidth,
                        height: MonitorPanelLayout.soundCardHeight
                    )
                footerSection
            }
            .padding(MonitorPanelLayout.contentPadding)
            .frame(
                width: MonitorPanelLayout.designWidth,
                height: MonitorPanelLayout.designHeight,
                alignment: .topLeading
            )
        }
        .frame(width: MonitorPanelLayout.designWidth, height: MonitorPanelLayout.designHeight)
        .overlayPreferenceValue(PickerAnchorPreferenceKey.self) { anchors in
            deviceDropdownOverlay(anchors: anchors)
        }
        .clipShape(MonitorTheme.panelShape)
        .scaleEffect(MonitorPanelLayout.scale, anchor: .topLeading)
        .frame(
            width: MonitorPanelLayout.panelWidth,
            height: MonitorPanelLayout.panelHeight,
            alignment: .topLeading
        )
        // 监控的启停由 AppDelegate 随面板显隐驱动（onAppear/onDisappear 在窗口
        // orderOut 时不可靠），确保面板隐藏时彻底停掉轮询以降低功耗。
    }
}

// MARK: - Main Sections

private extension ContentView {
    var headerSection: some View {
        HStack(spacing: 8) {
            CircleIconButton(symbolName: "power", style: .accent, accent: accentColor) {
                NSApp.terminate(nil)
            }

            Text(viewModel.headerSummary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            CircleIconButton(
                symbolName: colorScheme == .dark ? "moon.fill" : "sun.max.fill",
                style: .theme(isDark: colorScheme == .dark)
            ) {
                viewModel.toggleAppearance(isCurrentlyDark: colorScheme == .dark)
            }
        }
        .frame(height: MonitorPanelLayout.headerHeight)
    }

    var upperMonitorCardGrid: some View {
        VStack(spacing: MonitorPanelLayout.cardSpacing) {
            HStack(spacing: MonitorPanelLayout.cardSpacing) {
                cpuNetworkCard
                    .monitorCardCell(
                        width: MonitorPanelLayout.cardWidth,
                        height: MonitorPanelLayout.topGridCardHeight
                    )

                storageCard
                    .monitorCardCell(
                        width: MonitorPanelLayout.cardWidth,
                        height: MonitorPanelLayout.topGridCardHeight
                    )
            }
            .monitorCardRowSlot(height: MonitorPanelLayout.topGridCardHeight)

            HStack(spacing: MonitorPanelLayout.cardSpacing) {
                batteryToolsCard
                    .monitorCardCell(
                        width: MonitorPanelLayout.cardWidth,
                        height: MonitorPanelLayout.bottomGridCardHeight
                    )

                memoryCard
                    .monitorCardCell(
                        width: MonitorPanelLayout.cardWidth,
                        height: MonitorPanelLayout.bottomGridCardHeight
                    )
            }
            .monitorCardRowSlot(height: MonitorPanelLayout.bottomGridCardHeight)
        }
        .frame(height: MonitorPanelLayout.upperCardsHeight, alignment: .topLeading)
    }

    var cpuNetworkCard: some View {
        MonitorCard(title: strings.cpuNetworkTitle, colorScheme: colorScheme, titleTracking: sectionTitleTracking) {
            VStack(alignment: .leading, spacing: CardRhythm.sectionGap) {
                HStack(spacing: 0) {
                    LiveMetricBlock(
                        value: viewModel.cpuTemperatureDisplay,
                        unit: "C",
                        label: strings.cpuTemperature,
                        secondaryText: secondaryText,
                        primaryText: primaryText
                    )
                    .frame(maxWidth: .infinity)

                    subtleDivider
                        .frame(height: 42)

                    LiveMetricBlock(
                        value: viewModel.fanRPMDisplay,
                        unit: "rpm",
                        label: strings.fan,
                        secondaryText: secondaryText,
                        primaryText: primaryText
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: CardRhythm.itemGap) {
                    CardSectionDivider(color: cardBorder)

                    Button {
                        SystemToolsService.openNetworkSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accentColor)
                            Text(viewModel.wifiConnected ? strings.wifiConnected : strings.wifiDisconnected)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(controlBackground)
                    .clipShape(MonitorTheme.controlShape)
                    .contentShape(MonitorTheme.controlShape)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 0) {
                        NetworkThroughput(
                            label: strings.upload,
                            value: viewModel.uploadSpeedDisplay,
                            secondaryText: secondaryText,
                            primaryText: primaryText,
                            emphasized: true
                        )
                        subtleDivider.frame(height: 28)
                        NetworkThroughput(
                            label: strings.download,
                            value: viewModel.downloadSpeedDisplay,
                            secondaryText: secondaryText,
                            primaryText: primaryText,
                            emphasized: true
                        )
                    }
                }
            }
        }
    }

    var storageCard: some View {
        MonitorCard(title: strings.storageTitle, colorScheme: colorScheme, titleTracking: sectionTitleTracking) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: CardRhythm.labelGap) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(viewModel.availableStorageDisplay.replacingOccurrences(of: " GB", with: ""))
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(primaryText)
                                .monospacedDigit()
                            Text("GB")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(secondaryText)
                        }
                        Text(strings.availableSpace)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }

                    Spacer(minLength: 8)

                    Button {
                        SystemToolsService.openStorageSettings()
                    } label: {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(primaryText)
                            .padding(.top, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ProgressView(value: viewModel.storageUsageFraction)
                    .progressViewStyle(PanelCapsuleProgressStyle(colorScheme: colorScheme, accent: accentColor))
                    .frame(height: MonitorTheme.capsuleTrackHeight)
                    .padding(.top, CardRhythm.sectionGap)

                HStack(spacing: 0) {
                    StorageStatItem(
                        label: strings.used,
                        value: viewModel.usedStorageDisplay,
                        secondaryText: secondaryText,
                        primaryText: primaryText
                    )
                    Spacer(minLength: 12)
                    StorageStatItem(
                        label: strings.total,
                        value: viewModel.totalStorageDisplay,
                        secondaryText: secondaryText,
                        primaryText: primaryText,
                        alignment: .trailing
                    )
                }
                .padding(.top, CardRhythm.itemGap)

                HStack {
                    Spacer(minLength: 0)
                    StorageCleanerLaunchButton(
                        appName: viewModel.storageCleanerAppName,
                        appIcon: viewModel.storageCleanerAppIcon,
                        strings: strings,
                        accent: accentColor,
                        controlBackground: controlBackground,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        onOpen: { viewModel.openStorageCleanerApp() },
                        onPick: { viewModel.pickStorageCleanerApp() },
                        onClear: { viewModel.clearStorageCleanerApp() }
                    )
                }
                .padding(.top, CardRhythm.rowGap)
            }
        }
    }

    var batteryToolsCard: some View {
        MonitorCard(title: strings.batteryToolsTitle, colorScheme: colorScheme, titleTracking: sectionTitleTracking) {
            VStack(alignment: .leading, spacing: CardRhythm.sectionGap) {
                HStack(spacing: 0) {
                    LiveMetricBlock(
                        value: viewModel.batteryDisplay,
                        unit: "%",
                        label: strings.batteryLevel,
                        secondaryText: secondaryText,
                        primaryText: primaryText,
                        valueColor: batteryMetricValueColor,
                        overlaysLeadingAccessory: true,
                        leadingAccessory: {
                            if viewModel.isBatteryCharging {
                                BatteryChargingIcon(color: batteryMetricValueColor ?? batteryChargingColor)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)

                    subtleDivider
                        .frame(height: 42)

                    LiveMetricBlock(
                        value: viewModel.cpuLoadDisplay,
                        unit: "%",
                        label: strings.cpuLoad,
                        secondaryText: secondaryText,
                        primaryText: primaryText
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 0) {
                    CardSectionDivider(color: cardBorder)
                        .padding(.bottom, CardRhythm.itemGap)

                    VStack(spacing: 0) {
                        ToggleRow(title: strings.hideDesktop, isOn: hideDesktopBinding, showDivider: true, border: cardBorder, titleColor: primaryText)
                        ToggleRow(title: strings.cleanMode, isOn: cleanModeBinding, showDivider: false, border: cardBorder, titleColor: primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(controlBackground)
                    .clipShape(MonitorTheme.controlShape)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottomLeading) {
                    TypeRacingEntryButton(
                        accent: accentColor,
                        secondaryText: secondaryText,
                        action: { viewModel.presentTypeRacing() }
                    )
                    .padding(.leading, 5)
                    .offset(y: 6)
                }
            }
        }
    }

    var memoryCard: some View {
        MonitorCard(colorScheme: colorScheme) {
            HStack(alignment: .top, spacing: 0) {
                MemoryColumn(
                    title: strings.memoryOverviewTitle,
                    titleTracking: sectionTitleTracking,
                    entries: viewModel.memoryOverview,
                    strings: strings,
                    secondaryText: secondaryText,
                    primaryText: primaryText,
                    cardBorder: cardBorder
                )

                subtleDivider
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 10)

                MemoryColumn(
                    title: strings.memoryBreakdown,
                    titleTracking: sectionTitleTracking,
                    entries: viewModel.memoryBreakdown,
                    strings: strings,
                    secondaryText: secondaryText,
                    primaryText: primaryText,
                    cardBorder: cardBorder
                )
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var soundCard: some View {
        MonitorCard(colorScheme: colorScheme) {
            VStack(alignment: .leading, spacing: CardRhythm.sectionGap) {
                HStack(alignment: .top, spacing: 16) {
                    pickerField(
                        title: strings.outputDevice,
                        kind: .output,
                        selection: outputDeviceBinding,
                        options: outputDeviceOptionNames,
                        emptyPlaceholder: strings.noOutputDevice
                    )
                    soundVolumeField(
                        title: strings.volume,
                        value: volumeBinding,
                        accent: accentColor
                    )
                }

                CardSectionDivider(color: cardBorder)

                HStack(alignment: .top, spacing: 16) {
                    pickerField(
                        title: strings.inputDevice,
                        kind: .input,
                        selection: inputDeviceBinding,
                        options: inputDeviceOptionNames,
                        emptyPlaceholder: strings.noInputDevice
                    )

                    soundBalanceField(
                        title: strings.balance,
                        value: balanceBinding,
                        accent: accentColor
                    )
                }
            }
        }
    }

    var footerSection: some View {
        HStack(alignment: .center) {
            LanguageSegmentedControl(
                selection: Binding(
                    get: { viewModel.appLanguage },
                    set: { viewModel.setAppLanguage($0) }
                ),
                colorScheme: colorScheme,
                primaryText: primaryText,
                tertiaryText: tertiaryText
            )

            Spacer(minLength: 0)

            ZStack(alignment: .trailing) {
                madeByHycLabel
                    .opacity(viewModel.chargingPowerDisplay == nil ? 1 : 0)
                    .allowsHitTesting(viewModel.chargingPowerDisplay == nil)

                chargingPowerCapsule
            }
        }
        .frame(height: MonitorPanelLayout.footerHeight)
    }

    var madeByHycLabel: some View {
        Text("\"MADE BY HYC\"")
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(secondaryText.opacity(0.4))
            .contentShape(Rectangle())
            .onTapGesture(count: 3) {
                viewModel.resetAllStoredPreferences()
            }
    }

    @ViewBuilder
    var chargingPowerCapsule: some View {
        if let watts = viewModel.chargingPowerDisplay {
            HStack(spacing: 0) {
                Text(strings.chargingPowerLabel)
                Text(strings.chargingPowerValue(watts))
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(batteryChargingColor)
            .frame(width: MonitorPanelLayout.chargingPowerCapsuleContentWidth, alignment: .center)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .languageTrackCapsuleChrome(colorScheme: colorScheme)
            .allowsHitTesting(false)
        }
    }

    var subtleDivider: some View {
        Rectangle()
            .fill(cardBorder)
            .frame(width: 0.5)
    }
}

// MARK: - Inline Helpers

private extension ContentView {
    var hideDesktopBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hideDesktop },
            set: { viewModel.updateHideDesktop($0) }
        )
    }

    var cleanModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.cleanMode },
            set: { viewModel.updateCleanMode($0) }
        )
    }

    var outputDeviceBinding: Binding<String> {
        Binding(
            get: {
                let name = viewModel.selectedOutputDeviceName
                return name.isEmpty ? strings.noOutputDevice : name
            },
            set: { viewModel.setOutputDeviceByName($0) }
        )
    }

    var inputDeviceBinding: Binding<String> {
        Binding(
            get: {
                let name = viewModel.selectedInputDeviceName
                return name.isEmpty ? strings.noInputDevice : name
            },
            set: { viewModel.setInputDeviceByName($0) }
        )
    }

    var volumeBinding: Binding<Double> {
        Binding(
            get: { viewModel.volume },
            set: { viewModel.updateVolume($0) }
        )
    }

    var balanceBinding: Binding<Double> {
        Binding(
            get: { viewModel.balance },
            set: { viewModel.updateBalance($0) }
        )
    }

    func pickerField(
        title: String,
        kind: SoundDeviceKind,
        selection: Binding<String>,
        options: [String],
        emptyPlaceholder: String
    ) -> some View {
        let isEmpty = options.isEmpty
        let displayText = isEmpty ? emptyPlaceholder : selection.wrappedValue
        let isOpen = openDevicePicker == kind

        return VStack(alignment: .leading, spacing: CardRhythm.labelGap) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)

            Button {
                guard !isEmpty else { return }
                openDevicePicker = isOpen ? nil : kind
            } label: {
                HStack(spacing: 6) {
                    Text(displayText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isEmpty ? secondaryText : primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(controlBackground)
                .clipShape(MonitorTheme.controlShape)
                .overlay(
                    MonitorTheme.controlShape
                        .strokeBorder(
                            isOpen ? accentColor.opacity(0.55) : MonitorTheme.subtleBorderColor(for: colorScheme),
                            lineWidth: MonitorTheme.borderLineWidth
                        )
                )
                .contentShape(MonitorTheme.controlShape)
            }
            .buttonStyle(.plain)
            .anchorPreference(key: PickerAnchorPreferenceKey.self, value: .bounds) { [kind: $0] }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func deviceDropdownOverlay(anchors: [SoundDeviceKind: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let kind = openDevicePicker, let anchor = anchors[kind] {
                let fieldRect = proxy[anchor]
                let options = kind == .output ? outputDeviceOptionNames : inputDeviceOptionNames
                let selection = kind == .output ? outputDeviceBinding : inputDeviceBinding
                let listHeight = dropdownListHeight(optionCount: options.count)
                let listY = fieldRect.minY - listHeight - 4

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { openDevicePicker = nil }

                    PanelMenuList(
                        options: options,
                        selected: selection.wrappedValue,
                        colorScheme: colorScheme,
                        accent: accentColor,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        onSelect: { name in
                            selection.wrappedValue = name
                            openDevicePicker = nil
                        }
                    )
                    .frame(width: fieldRect.width)
                    .offset(x: fieldRect.minX, y: listY)
                }
            }
        }
    }

    func dropdownListHeight(optionCount: Int) -> CGFloat {
        let rowHeight: CGFloat = 28
        let rows = min(max(optionCount, 1), 6)
        return CGFloat(rows) * rowHeight + 8
    }

    func soundVolumeField(title: String, value: Binding<Double>, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: CardRhythm.labelGap + 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryText)
                Spacer(minLength: 4)
                PanelValuePill(
                    text: "\(Int(value.wrappedValue.rounded()))%",
                    colorScheme: colorScheme,
                    action: { viewModel.toggleVolumeMute() }
                )
                PanelWaveformView(value: value.wrappedValue, colorScheme: colorScheme)
            }

            PanelCapsuleSlider(
                value: value,
                range: 0...100,
                accent: accent,
                showTooltip: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func soundBalanceField(title: String, value: Binding<Double>, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: CardRhythm.labelGap + 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)

            HStack(spacing: 8) {
                PanelChannelBadge(label: "L") {
                    viewModel.updateBalance(0)
                }

                PanelCapsuleSlider(
                    value: value,
                    range: -50...50,
                    accent: accent,
                    showTooltip: true
                )

                PanelChannelBadge(label: "R") {
                    viewModel.updateBalance(0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Color Palette

private extension ContentView {
    var panelBackgroundMaterial: some View {
        MonitorTheme.panelShape
            .fill(.thinMaterial)
            .overlay(
                MonitorTheme.panelShape
                    .fill(
                        panelBackground.opacity(
                            colorScheme == .dark
                                ? MonitorDarkPalette.panelOverlayOpacity
                                : MonitorLightPalette.panelOverlayOpacity
                        )
                    )
            )
            .overlay(
                MonitorTheme.panelShape
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(MonitorDarkPalette.panelSheenOpacity)
                            : Color.white.opacity(MonitorLightPalette.panelSheenOpacity)
                    )
            )
            .overlay(
                MonitorTheme.panelShape
                    .strokeBorder(
                        MonitorTheme.panelBorderGradient(for: colorScheme),
                        lineWidth: MonitorTheme.borderLineWidth
                    )
            )
            .ignoresSafeArea()
    }

    var controlBackground: Color {
        colorScheme == .dark ? MonitorDarkPalette.controlFill : MonitorLightPalette.controlFill
    }

    var panelBackground: Color {
        colorScheme == .dark ? MonitorDarkPalette.panelBase : MonitorLightPalette.panelBase
    }

    var cardBorder: Color {
        colorScheme == .dark ? MonitorDarkPalette.cardDivider : Color.black.opacity(0.05)
    }

    var primaryText: Color {
        colorScheme == .dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x1D1D1F)
    }

    var secondaryText: Color {
        colorScheme == .dark ? Color(hex: 0x98989D) : Color(hex: 0x6E6E73)
    }

    var tertiaryText: Color {
        colorScheme == .dark ? Color(hex: 0x636366) : Color(hex: 0xAEAEB2)
    }

    var accentColor: Color {
        MonitorTheme.accentColor(for: colorScheme)
    }

    var batteryChargingColor: Color {
        colorScheme == .dark ? Color(hex: 0x30D158) : Color(hex: 0x34C759)
    }

    var batteryLowColor: Color {
        colorScheme == .dark ? Color(hex: 0xE06458) : Color(hex: 0xD95048)
    }

    var batteryMetricValueColor: Color? {
        if let level = viewModel.batteryPercentage, level <= 20 {
            return batteryLowColor
        }
        if viewModel.isBatteryCharging {
            return batteryChargingColor
        }
        return nil
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

