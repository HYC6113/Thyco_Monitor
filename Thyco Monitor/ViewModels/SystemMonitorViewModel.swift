import AppKit
import CoreAudio
import Foundation
import Observation

enum MemoryMetricKey: Hashable {
    case physicalMemory
    case used
    case cachedFiles
    case swapUsed
    case appMemory
    case wiredMemory
    case compressed
}

/// 内存卡片里的一行：指标键 + 已格式化的数值
struct MemoryMetric: Identifiable, Equatable {
    let key: MemoryMetricKey
    let value: String

    var id: MemoryMetricKey { key }
}

@MainActor
@Observable
final class SystemMonitorViewModel {
    static let preview: SystemMonitorViewModel = {
        let viewModel = SystemMonitorViewModel(isPreview: true)
        viewModel.headerSummary = "MacBook Pro · Apple M3 Pro · macOS 15.0.0"
        viewModel.cpuTemperatureDisplay = "42°C"
        viewModel.fanRPMDisplay = "1,280 RPM"
        viewModel.wifiConnected = true
        viewModel.uploadSpeedDisplay = "128 KB/s"
        viewModel.downloadSpeedDisplay = "2.4 MB/s"
        viewModel.availableStorageDisplay = "312 GB"
        viewModel.usedStorageDisplay = "688 GB"
        viewModel.totalStorageDisplay = "1 TB"
        viewModel.storageUsageFraction = 0.688
        viewModel.batteryDisplay = "87%"
        viewModel.batteryPercentage = 87
        viewModel.isBatteryCharging = true
        viewModel.chargingPowerDisplay = "45"
        viewModel.cpuLoadDisplay = "23"
        viewModel.memoryOverview = [
            MemoryMetric(key: .physicalMemory, value: "16 GB"),
            MemoryMetric(key: .used, value: "11.2 GB"),
            MemoryMetric(key: .cachedFiles, value: "2.1 GB"),
            MemoryMetric(key: .swapUsed, value: "0 B")
        ]
        viewModel.memoryBreakdown = [
            MemoryMetric(key: .appMemory, value: "4.8 GB"),
            MemoryMetric(key: .wiredMemory, value: "3.2 GB"),
            MemoryMetric(key: .compressed, value: "1.6 GB")
        ]
        viewModel.outputDevices = [AudioDevice(id: 1, name: "MacBook Pro 扬声器")]
        viewModel.inputDevices = [AudioDevice(id: 2, name: "MacBook Pro 麦克风")]
        viewModel.selectedOutputDeviceID = 1
        viewModel.selectedInputDeviceID = 2
        viewModel.volume = 62
        viewModel.balance = 0
        return viewModel
    }()

    private let isPreview: Bool
    // Header
    var headerSummary = ""

    // CPU / Network
    var cpuTemperatureDisplay = "—"
    var fanRPMDisplay = "—"
    var wifiConnected = false
    var uploadSpeedDisplay = ByteFormatting.formatBytesPerSecond(0)
    var downloadSpeedDisplay = ByteFormatting.formatBytesPerSecond(0)

    // Storage
    var availableStorageDisplay = "—"
    var usedStorageDisplay = "—"
    var totalStorageDisplay = "—"
    var storageUsageFraction = 0.0
    var storageCleanerAppName: String?
    var storageCleanerAppIcon: NSImage?

    // Battery / Tools
    var batteryDisplay = "—"
    var batteryPercentage: Int?
    var isBatteryCharging = false
    var chargingPowerDisplay: String?
    var cpuLoadDisplay = "0"
    var hideDesktop = false
    var cleanMode = false
    var launchAtLoginEnabled = false
    var appLanguage: AppLanguage = .chs
    /// 每次面板展示递增，供界面重置临时弹层状态。
    var panelOpenGeneration = 0

    // Memory
    var memoryOverview: [MemoryMetric] = []
    var memoryBreakdown: [MemoryMetric] = []
    var memoryPressureLevel: MemoryPressureLevel = .normal

    // Audio
    var outputDevices: [AudioDevice] = []
    var inputDevices: [AudioDevice] = []
    var selectedOutputDeviceID: AudioDeviceID?
    var selectedInputDeviceID: AudioDeviceID?
    var volume: Double = 0
    var balance: Double = 0

    private let scheduler = MonitorUpdateScheduler()
    private let batteryObserver = BatteryPowerSourceObserver()
    private let audioManager = AudioManager()
    private var isUpdatingAudioFromSystem = false
    private var volumeBeforeMute: Double?
    private var isMonitoring = false
    private var monitoringGeneration: UInt = 0
    private var desktopUpdateGeneration: UInt = 0

    var onCleanModeChange: ((Bool) -> Void)?
    var onPresentTypeRacing: (() -> Void)?
    var onPresentSpeedTest: (() -> Void)?

    func presentTypeRacing() {
        onPresentTypeRacing?()
    }

    func presentSpeedTest() {
        onPresentSpeedTest?()
    }

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
        if !isPreview {
            appLanguage = MonitorPreferencesService.savedLanguage()
        }
        audioManager.onStateChanged = { [weak self] in
            self?.syncAudioFromManager()
        }
    }

    var selectedOutputDeviceName: String {
        deviceName(for: selectedOutputDeviceID, in: outputDevices) ?? ""
    }

    var selectedInputDeviceName: String {
        deviceName(for: selectedInputDeviceID, in: inputDevices) ?? ""
    }

    func startMonitoring() {
        guard !isPreview, !isMonitoring else { return }
        isMonitoring = true
        monitoringGeneration &+= 1
        let generation = monitoringGeneration

        update(\.headerSummary, to: SystemInfoProvider.headerSummary)
        update(\.hideDesktop, to: SystemToolsService.isDesktopHidden())

        audioManager.start()
        syncAudioFromManager()
        refreshStorageCleanerApp()
        refreshBatteryMetrics()

        batteryObserver.start { [weak self] in
            Task { @MainActor in
                guard let self, self.isMonitoring, self.monitoringGeneration == generation else { return }
                self.refreshBatteryMetrics()
            }
        }

        // 采样在调度器的后台队列完成，这里只把结果搬回主线程写入
        scheduler.start(
            onFastTick: { [weak self] sample in
                Task { @MainActor [weak self] in
                    guard let self, self.monitoringGeneration == generation else { return }
                    self.applyFastMetrics(sample)
                }
            },
            onMediumTick: { [weak self] storage in
                Task { @MainActor [weak self] in
                    guard let self, self.monitoringGeneration == generation else { return }
                    self.applyMediumMetrics(storage)
                }
            }
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        batteryObserver.stop()
        scheduler.stop()
        audioManager.stop()
    }

    func setOutputDeviceByName(_ name: String) {
        audioManager.setOutputDeviceByName(name)
    }

    func setInputDeviceByName(_ name: String) {
        audioManager.setInputDeviceByName(name)
    }

    func updateVolume(_ newValue: Double) {
        guard !isUpdatingAudioFromSystem else { return }
        let effective = max(0, min(100, newValue.rounded()))
        if effective > 0 {
            volumeBeforeMute = nil
        }
        audioManager.setVolume(effective)
    }

    func toggleVolumeMute() {
        guard !isUpdatingAudioFromSystem else { return }
        if volume <= 0 {
            guard let restore = volumeBeforeMute else { return }
            volumeBeforeMute = nil
            audioManager.setVolume(restore)
        } else {
            volumeBeforeMute = volume
            audioManager.setVolume(0)
        }
    }

    func updateBalance(_ newValue: Double) {
        guard !isUpdatingAudioFromSystem else { return }
        audioManager.applyBalance(newValue)
    }

    func updateHideDesktop(_ hidden: Bool) {
        hideDesktop = hidden
        desktopUpdateGeneration &+= 1
        let generation = desktopUpdateGeneration
        SystemToolsService.setDesktopHidden(hidden) { [weak self] actualHidden in
            Task { @MainActor [weak self] in
                guard let self, self.desktopUpdateGeneration == generation else { return }
                self.hideDesktop = actualHidden
            }
        }
    }

    func updateCleanMode(_ enabled: Bool) {
        cleanMode = enabled
        onCleanModeChange?(enabled)
    }

    func dismissCleanMode() {
        guard cleanMode else { return }
        cleanMode = false
        onCleanModeChange?(false)
    }

    func refreshStorageCleanerApp() {
        let app = StorageCleanerAppService.savedApp()
        storageCleanerAppName = app?.name
        storageCleanerAppIcon = app?.icon
    }

    func openStorageCleanerApp() {
        Task {
            if StorageCleanerAppService.savedApp() == nil {
                guard StorageCleanerAppService.pickApp() != nil else { return }
                refreshStorageCleanerApp()
            }
            let success = await StorageCleanerAppService.openApp()
            if !success {
                refreshStorageCleanerApp()
            }
        }
    }

    func pickStorageCleanerApp() {
        guard StorageCleanerAppService.pickApp() != nil else { return }
        refreshStorageCleanerApp()
    }

    func clearStorageCleanerApp() {
        StorageCleanerAppService.clearApp()
        refreshStorageCleanerApp()
    }

    func resetAllStoredPreferences() {
        MonitorPreferencesService.clearAll()
        StorageCleanerAppService.clearApp()
        SpeedTestServerHistory().clear()

        appLanguage = .chs
        MonitorPreferencesService.applySystemAppearance()

        refreshStorageCleanerApp()
        volumeBeforeMute = nil
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }

    func setAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        MonitorPreferencesService.saveLanguage(language)
    }

    func toggleAppearance(isCurrentlyDark: Bool) {
        let next: MonitorAppearance = isCurrentlyDark ? .light : .dark
        MonitorPreferencesService.saveAppearance(next)
        MonitorPreferencesService.applyAppearance(next)
    }

    func willPresentPanel() {
        panelOpenGeneration += 1
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LaunchAtLoginService.isEnabled else {
            launchAtLoginEnabled = enabled
            return
        }
        do {
            try LaunchAtLoginService.setEnabled(enabled)
        } catch {
            // 用户未在系统设置中授权时 register 可能失败，回读真实状态。
        }
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }

    // MARK: - 指标写入

    /// `@Observable` 的 setter 无条件通知观察者；值未变时跳过赋值，对应卡片不重绘。
    private func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<SystemMonitorViewModel, Value>,
        to value: Value
    ) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    private func applyFastMetrics(_ sample: FastMetricsSample) {
        guard isMonitoring else { return }

        update(\.cpuTemperatureDisplay, to: ByteFormatting.formatTemperature(sample.hardware.cpuTemperatureCelsius))
        update(\.fanRPMDisplay, to: ByteFormatting.formatRPM(sample.hardware.fanRPM))

        update(\.wifiConnected, to: sample.network.isWifiConnected)
        // 基线样本的差分为 0；保留上次读数直到首个有效值，避免打开面板时先闪一下 0。
        if !sample.isBaseline {
            update(\.uploadSpeedDisplay, to: sample.network.uploadDisplay)
            update(\.downloadSpeedDisplay, to: sample.network.downloadDisplay)
            update(\.cpuLoadDisplay, to: ByteFormatting.formatPercent(sample.cpu.usagePercent))
        }

        let memory = sample.memory
        update(\.memoryOverview, to: [
            MemoryMetric(key: .physicalMemory, value: memory.physicalDisplay),
            MemoryMetric(key: .used, value: memory.usedDisplay),
            MemoryMetric(key: .cachedFiles, value: memory.cachedDisplay),
            MemoryMetric(key: .swapUsed, value: memory.swapDisplay)
        ])
        update(\.memoryBreakdown, to: [
            MemoryMetric(key: .appMemory, value: memory.appDisplay),
            MemoryMetric(key: .wiredMemory, value: memory.wiredDisplay),
            MemoryMetric(key: .compressed, value: memory.compressedDisplay)
        ])
        update(\.memoryPressureLevel, to: memory.pressureLevel)

        applyBatteryMetrics(from: sample.battery)
    }

    private func applyMediumMetrics(_ storage: StorageSnapshot) {
        guard isMonitoring else { return }

        update(\.availableStorageDisplay, to: storage.availableDisplay)
        update(\.usedStorageDisplay, to: storage.usedDisplay)
        update(\.totalStorageDisplay, to: storage.totalDisplay)
        update(\.storageUsageFraction, to: storage.usageFraction)
    }

    private func refreshBatteryMetrics() {
        applyBatteryMetrics(from: BatteryMonitor.snapshot())
    }

    private func applyBatteryMetrics(from battery: BatterySnapshot) {
        update(\.batteryDisplay, to: battery.displayValue)
        update(\.batteryPercentage, to: battery.percentage)
        update(\.isBatteryCharging, to: battery.isCharging)
        update(\.chargingPowerDisplay, to: battery.chargingPowerDisplay)
    }

    private func syncAudioFromManager() {
        isUpdatingAudioFromSystem = true
        update(\.outputDevices, to: audioManager.outputDevices)
        update(\.inputDevices, to: audioManager.inputDevices)
        update(\.selectedOutputDeviceID, to: audioManager.selectedOutputDeviceID)
        update(\.selectedInputDeviceID, to: audioManager.selectedInputDeviceID)
        update(\.volume, to: audioManager.volume)
        update(\.balance, to: audioManager.balance)
        if volume > 0 {
            volumeBeforeMute = nil
        }
        isUpdatingAudioFromSystem = false
    }

    private func deviceName(for id: AudioDeviceID?, in devices: [AudioDevice]) -> String? {
        guard let id else { return devices.first?.name }
        return devices.first(where: { $0.id == id })?.name
    }
}
