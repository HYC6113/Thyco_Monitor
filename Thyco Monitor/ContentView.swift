import AppKit
import SwiftUI

enum SoundDeviceKind: Hashable {
    case output
    case input
}

struct PickerAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [SoundDeviceKind: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SoundDeviceKind: Anchor<CGRect>],
        nextValue: () -> [SoundDeviceKind: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum SettingsAnchor: Hashable {
    case settingsButton
}

struct SettingsAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [SettingsAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SettingsAnchor: Anchor<CGRect>],
        nextValue: () -> [SettingsAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 面板骨架：只负责整体布局、两个浮层以及它们的临时状态。
/// 每秒刷新的指标都收在各自的卡片视图里，避免整棵视图树随指标失效。
struct ContentView: View {
    var viewModel: SystemMonitorViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var openDevicePicker: SoundDeviceKind?
    @State private var isSettingsMenuOpen = false

    private var strings: MonitorStrings {
        MonitorStrings(language: viewModel.appLanguage)
    }

    private var palette: MonitorPalette { .of(colorScheme) }

    private var sectionTitleTracking: CGFloat {
        MonitorTheme.sectionTitleTracking(for: viewModel.appLanguage)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PanelChromeBackground()

            VStack(spacing: MonitorPanelLayout.cardSpacing) {
                PanelHeaderRow(viewModel: viewModel) { isSettingsMenuOpen = false }
                upperMonitorCardGrid
                SoundCard(
                    viewModel: viewModel,
                    strings: strings,
                    openDevicePicker: $openDevicePicker,
                    isSettingsMenuOpen: $isSettingsMenuOpen
                )
                .monitorCardCell(
                    width: MonitorPanelLayout.contentAreaWidth,
                    height: MonitorPanelLayout.soundCardHeight
                )
                footerSection
            }
            .padding(MonitorPanelLayout.contentInsets)
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
        .overlayPreferenceValue(SettingsAnchorPreferenceKey.self) { anchors in
            settingsMenuOverlay(anchors: anchors)
        }
        .onChange(of: viewModel.panelOpenGeneration) { _, _ in
            isSettingsMenuOpen = false
            openDevicePicker = nil
        }
        .clipShape(MonitorTheme.panelShape)
        .scaleEffect(MonitorPanelLayout.scale, anchor: .topLeading)
        .frame(
            width: MonitorPanelLayout.panelWidth,
            height: MonitorPanelLayout.panelHeight,
            alignment: .topLeading
        )
        // 监控的启停由 MonitorPanelController 随面板显隐驱动（onAppear/onDisappear
        // 在窗口 orderOut 时不可靠），确保面板隐藏时彻底停掉轮询以降低功耗。
    }
}

// MARK: - Layout

private extension ContentView {
    var upperMonitorCardGrid: some View {
        VStack(spacing: MonitorPanelLayout.cardSpacing) {
            HStack(spacing: MonitorPanelLayout.cardSpacing) {
                CPUNetworkCard(
                    viewModel: viewModel,
                    strings: strings,
                    titleTracking: sectionTitleTracking
                )
                .monitorCardCell(
                    width: MonitorPanelLayout.cardWidth,
                    height: MonitorPanelLayout.topGridCardHeight
                )

                StorageCard(
                    viewModel: viewModel,
                    strings: strings,
                    titleTracking: sectionTitleTracking
                )
                .monitorCardCell(
                    width: MonitorPanelLayout.cardWidth,
                    height: MonitorPanelLayout.topGridCardHeight
                )
            }
            .monitorCardRowSlot(height: MonitorPanelLayout.topGridCardHeight)

            HStack(spacing: MonitorPanelLayout.cardSpacing) {
                BatteryToolsCard(
                    viewModel: viewModel,
                    strings: strings,
                    titleTracking: sectionTitleTracking
                )
                .monitorCardCell(
                    width: MonitorPanelLayout.cardWidth,
                    height: MonitorPanelLayout.bottomGridCardHeight
                )

                MemoryCard(
                    viewModel: viewModel,
                    strings: strings,
                    titleTracking: sectionTitleTracking
                )
                .monitorCardCell(
                    width: MonitorPanelLayout.cardWidth,
                    height: MonitorPanelLayout.bottomGridCardHeight
                )
            }
            .monitorCardRowSlot(height: MonitorPanelLayout.bottomGridCardHeight)
        }
        .frame(height: MonitorPanelLayout.upperCardsHeight, alignment: .topLeading)
    }

    var footerSection: some View {
        PanelFooterRow(
            viewModel: viewModel,
            strings: strings,
            isSettingsMenuOpen: $isSettingsMenuOpen,
            openDevicePicker: $openDevicePicker
        )
    }
}

// MARK: - Floating Overlays

private extension ContentView {
    var outputDeviceOptionNames: [String] {
        viewModel.outputDevices.map(\.name)
    }

    var inputDeviceOptionNames: [String] {
        viewModel.inputDevices.map(\.name)
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

    var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLoginEnabled },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    @ViewBuilder
    func deviceDropdownOverlay(anchors: [SoundDeviceKind: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let kind = openDevicePicker, let anchor = anchors[kind] {
                let fieldRect = proxy[anchor]
                let options = kind == .output ? outputDeviceOptionNames : inputDeviceOptionNames
                let selection = kind == .output ? outputDeviceBinding : inputDeviceBinding
                let listHeight = PanelMenuList.height(optionCount: options.count)
                let gap: CGFloat = 4
                let listY = max(gap, fieldRect.minY - listHeight - gap)

                ZStack(alignment: .topLeading) {
                    dismissLayer(size: proxy.size) { openDevicePicker = nil }

                    PanelMenuList(
                        options: options,
                        selected: selection.wrappedValue,
                        colorScheme: colorScheme,
                        palette: palette,
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

    @ViewBuilder
    func settingsMenuOverlay(anchors: [SettingsAnchor: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if isSettingsMenuOpen, let anchor = anchors[.settingsButton] {
                let buttonRect = proxy[anchor]
                let menuWidth: CGFloat = 210
                let menuHeight: CGFloat = 44

                ZStack(alignment: .topLeading) {
                    dismissLayer(size: proxy.size) { isSettingsMenuOpen = false }

                    PanelSettingsMenu(
                        isOn: launchAtLoginBinding,
                        title: strings.launchAtLogin,
                        colorScheme: colorScheme,
                        palette: palette
                    )
                    .frame(width: menuWidth, height: menuHeight)
                    .offset(x: buttonRect.minX, y: buttonRect.minY - menuHeight - 4)
                }
            }
        }
    }

    /// 铺满面板的透明层：点击浮层以外区域将其收起
    func dismissLayer(size: CGSize, onTap: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
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
