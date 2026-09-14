import AppKit
import SwiftUI

// MARK: - 顶栏

struct PanelHeaderRow: View {
    let viewModel: SystemMonitorViewModel
    let onCloseMenus: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 8) {
            CircleIconButton(symbolName: "power", style: .accent, accent: palette.accent) {
                NSApp.terminate(nil)
            }

            Text(viewModel.headerSummary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            CircleIconButton(
                symbolName: isDark ? "moon.fill" : "sun.max.fill",
                style: .theme(isDark: isDark)
            ) {
                onCloseMenus()
                viewModel.toggleAppearance(isCurrentlyDark: isDark)
            }
        }
        .frame(height: MonitorPanelLayout.headerHeight)
    }
}

// MARK: - CPU / 网络

struct CPUNetworkCard: View {
    let viewModel: SystemMonitorViewModel
    let strings: MonitorStrings
    let titleTracking: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }

    var body: some View {
        MonitorCard(title: strings.cpuNetworkTitle, colorScheme: colorScheme, titleTracking: titleTracking) {
            VStack(alignment: .leading, spacing: CardRhythm.sectionGap) {
                HStack(spacing: 0) {
                    LiveMetricBlock(
                        value: viewModel.cpuTemperatureDisplay,
                        unit: "C",
                        label: strings.cpuTemperature,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)

                    CardColumnDivider(color: palette.cardBorder)
                        .frame(height: 42)

                    LiveMetricBlock(
                        value: viewModel.fanRPMDisplay,
                        unit: "rpm",
                        label: strings.fan,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: CardRhythm.itemGap) {
                    CardSectionDivider(color: palette.cardBorder)

                    wifiStatusButton

                    HStack(spacing: 0) {
                        NetworkThroughput(
                            label: strings.upload,
                            value: viewModel.uploadSpeedDisplay,
                            palette: palette
                        )
                        CardColumnDivider(color: palette.cardBorder)
                            .frame(height: 28)
                        NetworkThroughput(
                            label: strings.download,
                            value: viewModel.downloadSpeedDisplay,
                            palette: palette
                        )
                    }
                }
            }
        }
    }

    private var wifiStatusButton: some View {
        Button {
            SystemToolsService.openNetworkSettings()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(viewModel.wifiConnected ? strings.wifiConnected : strings.wifiDisconnected)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.controlBackground)
            .clipShape(MonitorTheme.controlShape)
            .overlay(
                MonitorTheme.controlShape
                    .strokeBorder(MonitorTheme.subtleBorderColor(for: colorScheme), lineWidth: MonitorTheme.borderLineWidth)
            )
            .contentShape(MonitorTheme.controlShape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 存储

struct StorageCard: View {
    let viewModel: SystemMonitorViewModel
    let strings: MonitorStrings
    let titleTracking: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }

    var body: some View {
        MonitorCard(title: strings.storageTitle, colorScheme: colorScheme, titleTracking: titleTracking) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: CardRhythm.labelGap) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(viewModel.availableStorageDisplay.replacingOccurrences(of: " GB", with: ""))
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(palette.primaryText)
                                .monospacedDigit()
                            Text("GB")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(strings.availableSpace)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer(minLength: 8)

                    Button {
                        SystemToolsService.openStorageSettings()
                    } label: {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.primaryText)
                            .padding(.top, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ProgressView(value: viewModel.storageUsageFraction)
                    .progressViewStyle(PanelCapsuleProgressStyle(colorScheme: colorScheme, accent: palette.accent))
                    .frame(height: MonitorTheme.capsuleTrackHeight)
                    .padding(.top, CardRhythm.sectionGap)

                HStack(spacing: 0) {
                    StorageStatItem(
                        label: strings.used,
                        value: viewModel.usedStorageDisplay,
                        palette: palette
                    )
                    Spacer(minLength: 12)
                    StorageStatItem(
                        label: strings.total,
                        value: viewModel.totalStorageDisplay,
                        palette: palette,
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
                        palette: palette,
                        onOpen: { viewModel.openStorageCleanerApp() },
                        onPick: { viewModel.pickStorageCleanerApp() },
                        onClear: { viewModel.clearStorageCleanerApp() }
                    )
                }
                .padding(.top, CardRhythm.rowGap)
            }
        }
    }
}

// MARK: - 电池 / 工具

struct BatteryToolsCard: View {
    let viewModel: SystemMonitorViewModel
    let strings: MonitorStrings
    let titleTracking: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }

    /// 低电量优先显示为红色，其次是充电中的绿色，否则跟随常规文本色
    private var batteryValueColor: Color? {
        if let level = viewModel.batteryPercentage, level <= 20 {
            return palette.batteryLow
        }
        return viewModel.isBatteryCharging ? palette.batteryCharging : nil
    }

    var body: some View {
        MonitorCard(title: strings.batteryToolsTitle, colorScheme: colorScheme, titleTracking: titleTracking) {
            VStack(alignment: .leading, spacing: CardRhythm.sectionGap) {
                HStack(spacing: 0) {
                    LiveMetricBlock(
                        value: viewModel.batteryDisplay,
                        unit: "%",
                        label: strings.batteryLevel,
                        palette: palette,
                        valueColor: batteryValueColor,
                        overlaysLeadingAccessory: true,
                        leadingAccessory: {
                            if viewModel.isBatteryCharging {
                                BatteryChargingIcon(color: batteryValueColor ?? palette.batteryCharging)
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)

                    CardColumnDivider(color: palette.cardBorder)
                        .frame(height: 42)

                    LiveMetricBlock(
                        value: viewModel.cpuLoadDisplay,
                        unit: "%",
                        label: strings.cpuLoad,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 0) {
                    CardSectionDivider(color: palette.cardBorder)
                        .padding(.bottom, CardRhythm.itemGap)

                    VStack(spacing: 0) {
                        ToggleRow(
                            title: strings.hideDesktop,
                            isOn: Binding(
                                get: { viewModel.hideDesktop },
                                set: { viewModel.updateHideDesktop($0) }
                            ),
                            showDivider: true,
                            palette: palette
                        )
                        ToggleRow(
                            title: strings.cleanMode,
                            isOn: Binding(
                                get: { viewModel.cleanMode },
                                set: { viewModel.updateCleanMode($0) }
                            ),
                            palette: palette
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(palette.controlBackground)
                    .clipShape(MonitorTheme.controlShape)
                    .overlay(
                        MonitorTheme.controlShape
                            .strokeBorder(MonitorTheme.subtleBorderColor(for: colorScheme), lineWidth: MonitorTheme.borderLineWidth)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottomLeading) {
                    TypeRacingEntryButton(palette: palette) {
                        viewModel.presentTypeRacing()
                    }
                    .padding(.leading, 5)
                    .offset(y: 6)
                }
            }
        }
    }
}

// MARK: - 内存

struct MemoryCard: View {
    let viewModel: SystemMonitorViewModel
    let strings: MonitorStrings
    let titleTracking: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }

    var body: some View {
        MonitorCard(colorScheme: colorScheme) {
            HStack(alignment: .top, spacing: 0) {
                MemoryColumn(
                    title: strings.memoryOverviewTitle,
                    titleTracking: titleTracking,
                    entries: viewModel.memoryOverview,
                    strings: strings,
                    palette: palette
                )

                CardColumnDivider(color: palette.cardBorder)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 10)

                MemoryColumn(
                    title: strings.memoryBreakdown,
                    titleTracking: titleTracking,
                    entries: viewModel.memoryBreakdown,
                    strings: strings,
                    palette: palette
                )
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                MemoryPressureIndicator(
                    level: viewModel.memoryPressureLevel,
                    accessibilityLabel: strings.memoryPressureLabel(for: viewModel.memoryPressureLevel)
                )
            }
        }
    }
}

// MARK: - 声音

struct SoundCard: View {
    let viewModel: SystemMonitorViewModel
    let strings: MonitorStrings
    @Binding var openDevicePicker: SoundDeviceKind?
    @Binding var isSettingsMenuOpen: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }

    var body: some View {
        MonitorCard(colorScheme: colorScheme) {
            VStack(alignment: .leading, spacing: CardRhythm.sectionGap) {
                HStack(alignment: .top, spacing: 16) {
                    devicePicker(
                        title: strings.outputDevice,
                        kind: .output,
                        selectedName: viewModel.selectedOutputDeviceName,
                        optionCount: viewModel.outputDevices.count,
                        emptyPlaceholder: strings.noOutputDevice
                    )
                    volumeField
                }

                CardSectionDivider(color: palette.cardBorder)

                HStack(alignment: .top, spacing: 16) {
                    devicePicker(
                        title: strings.inputDevice,
                        kind: .input,
                        selectedName: viewModel.selectedInputDeviceName,
                        optionCount: viewModel.inputDevices.count,
                        emptyPlaceholder: strings.noInputDevice
                    )
                    balanceField
                }
            }
        }
    }

    /// 设备下拉的触发按钮；列表本体由 ContentView 用 anchor preference 定位绘制
    private func devicePicker(
        title: String,
        kind: SoundDeviceKind,
        selectedName: String,
        optionCount: Int,
        emptyPlaceholder: String
    ) -> some View {
        let isEmpty = optionCount == 0
        let displayText = isEmpty || selectedName.isEmpty ? emptyPlaceholder : selectedName
        let isOpen = openDevicePicker == kind

        return VStack(alignment: .leading, spacing: CardRhythm.labelGap) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryText)

            Button {
                guard !isEmpty else { return }
                isSettingsMenuOpen = false
                openDevicePicker = isOpen ? nil : kind
            } label: {
                HStack(spacing: 6) {
                    Text(displayText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isEmpty ? palette.secondaryText : palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.controlBackground)
                .clipShape(MonitorTheme.controlShape)
                .overlay(
                    MonitorTheme.controlShape
                        .strokeBorder(
                            isOpen ? palette.accent.opacity(0.55) : MonitorTheme.subtleBorderColor(for: colorScheme),
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

    private var volumeField: some View {
        let volume = Binding(
            get: { viewModel.volume },
            set: { viewModel.updateVolume($0) }
        )

        return VStack(alignment: .leading, spacing: CardRhythm.labelGap + 2) {
            HStack(spacing: 6) {
                Text(strings.volume)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 4)
                PanelValuePill(
                    text: "\(Int(volume.wrappedValue.rounded()))%",
                    colorScheme: colorScheme
                ) {
                    viewModel.toggleVolumeMute()
                }
                PanelWaveformView(value: volume.wrappedValue, colorScheme: colorScheme)
            }

            PanelCapsuleSlider(
                value: volume,
                range: 0...100,
                accent: palette.accent,
                showTooltip: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var balanceField: some View {
        let balance = Binding(
            get: { viewModel.balance },
            set: { viewModel.updateBalance($0) }
        )

        return VStack(alignment: .leading, spacing: CardRhythm.labelGap + 2) {
            Text(strings.balance)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryText)

            HStack(spacing: 8) {
                PanelChannelBadge(label: "L") { viewModel.updateBalance(0) }

                PanelCapsuleSlider(
                    value: balance,
                    range: -50...50,
                    accent: palette.accent,
                    showTooltip: true
                )

                PanelChannelBadge(label: "R") { viewModel.updateBalance(0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 底栏

struct PanelFooterRow: View {
    let viewModel: SystemMonitorViewModel
    let strings: MonitorStrings
    @Binding var isSettingsMenuOpen: Bool
    @Binding var openDevicePicker: SoundDeviceKind?

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette { .of(colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            LanguageSegmentedControl(
                selection: Binding(
                    get: { viewModel.appLanguage },
                    set: { viewModel.setAppLanguage($0) }
                ),
                colorScheme: colorScheme,
                palette: palette
            )

            FooterSettingsButton(
                isMenuOpen: isSettingsMenuOpen,
                colorScheme: colorScheme,
                primaryText: palette.primaryText
            ) {
                openDevicePicker = nil
                isSettingsMenuOpen.toggle()
            }
            .anchorPreference(key: SettingsAnchorPreferenceKey.self, value: .bounds) { [.settingsButton: $0] }

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

    /// 连续三击清除本地偏好（隐藏彩蛋）
    private var madeByHycLabel: some View {
        Text("\"MADE BY HYC\"")
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(palette.secondaryText.opacity(0.4))
            .contentShape(Rectangle())
            .onTapGesture(count: 3) {
                viewModel.resetAllStoredPreferences()
            }
    }

    @ViewBuilder
    private var chargingPowerCapsule: some View {
        if let watts = viewModel.chargingPowerDisplay {
            HStack(spacing: 0) {
                Text(strings.chargingPowerLabel)
                Text(strings.chargingPowerValue(watts))
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.batteryCharging)
            .frame(width: MonitorPanelLayout.chargingPowerCapsuleContentWidth, alignment: .center)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .languageTrackCapsuleChrome(colorScheme: colorScheme)
            .allowsHitTesting(false)
        }
    }
}
