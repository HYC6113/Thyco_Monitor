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
    var uploadSpeedDisplay = "0 B/s"
    var downloadSpeedDisplay = "0 B/s"

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

    var onCleanModeChange: ((Bool) -> Void)?
    var onPresentTypeRacing: (() -> Void)?

    func presentTypeRacing() {
        onPresentTypeRacing?()
    }

    init(isPreview: Bool = false) {
        self.isPreview = isPreview
        if !isPreview {
            appLanguage = MonitorPreferencesService.savedLanguage()
        }
        audioManager.onStateChanged = { [weak self] in
            Task { @MainActor in
                self?.syncAudioFromManager()
            }
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

        headerSummary = SystemInfoProvider.headerSummary
        hideDesktop = SystemToolsService.isDesktopHidden()

        audioManager.start()
        syncAudioFromManager()
        refreshStorageCleanerApp()
        refreshBatteryMetrics()

        batteryObserver.start { [weak self] in
            Task { @MainActor in
                self?.refreshBatteryMetrics()
            }
        }

        // 采样在调度器的后台队列完成，这里只把结果搬回主线程写入
        scheduler.start(
            onFastTick: { [weak self] sample in
                guard let self else { return }
                Task { @MainActor in self.applyFastMetrics(sample) }
            },
            onMediumTick: { [weak self] storage in
                guard let self else { return }
                Task { @MainActor in self.applyMediumMetrics(storage) }
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
        let previous = hideDesktop
        hideDesktop = hidden
        Task {
            let success = await Task.detached(priority: .userInitiated) {
                SystemToolsService.setDesktopHidden(hidden)
            }.value
            hideDesktop = success ? SystemToolsService.isDesktopHidden() : previous
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
    //
    // `@Observable` 的 setter 无条件通知观察者，因此逐项比较后再赋值，
    // 数值未变时不触发对应卡片重绘。

    private func applyFastMetrics(_ sample: FastMetricsSample) {
        guard isMonitoring else { return }

        let temperature = ByteFormatting.formatTemperature(sample.hardware.cpuTemperatureCelsius)
        if cpuTemperatureDisplay != temperature {
            cpuTemperatureDisplay = temperature
        }

        let fanRPM = ByteFormatting.formatRPM(sample.hardware.fanRPM)
        if fanRPMDisplay != fanRPM {
            fanRPMDisplay = fanRPM
        }

        let network = sample.network
        if wifiConnected != network.isWifiConnected {
            wifiConnected = network.isWifiConnected
        }
        if uploadSpeedDisplay != network.uploadDisplay {
            uploadSpeedDisplay = network.uploadDisplay
        }
        if downloadSpeedDisplay != network.downloadDisplay {
            downloadSpeedDisplay = network.downloadDisplay
        }

        let cpuLoad = ByteFormatting.formatPercent(sample.cpu.usagePercent)
        if cpuLoadDisplay != cpuLoad {
            cpuLoadDisplay = cpuLoad
        }

        let memory = sample.memory
        let overview = [
            MemoryMetric(key: .physicalMemory, value: memory.physicalDisplay),
            MemoryMetric(key: .used, value: memory.usedDisplay),
            MemoryMetric(key: .cachedFiles, value: memory.cachedDisplay),
            MemoryMetric(key: .swapUsed, value: memory.swapDisplay)
        ]
        if memoryOverview != overview {
            memoryOverview = overview
        }

        let breakdown = [
            MemoryMetric(key: .appMemory, value: memory.appDisplay),
            MemoryMetric(key: .wiredMemory, value: memory.wiredDisplay),
            MemoryMetric(key: .compressed, value: memory.compressedDisplay)
        ]
        if memoryBreakdown != breakdown {
            memoryBreakdown = breakdown
        }
        if memoryPressureLevel != memory.pressureLevel {
            memoryPressureLevel = memory.pressureLevel
        }

        applyBatteryMetrics(from: sample.battery)
    }

    private func applyMediumMetrics(_ storage: StorageSnapshot) {
        guard isMonitoring else { return }

        if availableStorageDisplay != storage.availableDisplay {
            availableStorageDisplay = storage.availableDisplay
        }
        if usedStorageDisplay != storage.usedDisplay {
            usedStorageDisplay = storage.usedDisplay
        }
        if totalStorageDisplay != storage.totalDisplay {
            totalStorageDisplay = storage.totalDisplay
        }
        if storageUsageFraction != storage.usageFraction {
            storageUsageFraction = storage.usageFraction
        }
    }

    private func refreshBatteryMetrics() {
        applyBatteryMetrics(from: BatteryMonitor.snapshot())
    }

    private func applyBatteryMetrics(from battery: BatterySnapshot) {
        let nextChargingPowerDisplay = battery.chargingPowerDisplay
        guard batteryDisplay != battery.displayValue
            || batteryPercentage != battery.percentage
            || isBatteryCharging != battery.isCharging
            || chargingPowerDisplay != nextChargingPowerDisplay
        else { return }
        batteryDisplay = battery.displayValue
        batteryPercentage = battery.percentage
        isBatteryCharging = battery.isCharging
        chargingPowerDisplay = nextChargingPowerDisplay
    }

    private func syncAudioFromManager() {
        isUpdatingAudioFromSystem = true
        outputDevices = audioManager.outputDevices
        inputDevices = audioManager.inputDevices
        selectedOutputDeviceID = audioManager.selectedOutputDeviceID
        selectedInputDeviceID = audioManager.selectedInputDeviceID
        volume = audioManager.volume
        balance = audioManager.balance
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
