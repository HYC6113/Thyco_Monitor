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
        viewModel.cpuLoadDisplay = "23"
        viewModel.memoryOverview = [
            (.physicalMemory, "16 GB", true),
            (.used, "11.2 GB", false),
            (.cachedFiles, "2.1 GB", false),
            (.swapUsed, "0 B", false)
        ]
        viewModel.memoryBreakdown = [
            (.appMemory, "4.8 GB", false),
            (.wiredMemory, "3.2 GB", false),
            (.compressed, "1.6 GB", false)
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
    var isBatteryCharging = false
    var cpuLoadDisplay = "0"
    var hideDesktop = false
    var cleanMode = false
    var appLanguage: AppLanguage = .chs

    // Memory
    var memoryOverview: [(MemoryMetricKey, String, Bool)] = []
    var memoryBreakdown: [(MemoryMetricKey, String, Bool)] = []

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
    private var fastTickTask: Task<Void, Never>?
    private var mediumTickTask: Task<Void, Never>?
    private var isFastTickRunning = false
    private var isMediumTickRunning = false

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

        let info = SystemInfoProvider.snapshot()
        headerSummary = info.headerSummary
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

        scheduler.onFastTick = { [weak self] in
            Task { @MainActor in
                self?.runFastTickIfNeeded()
            }
        }
        scheduler.onMediumTick = { [weak self] in
            Task { @MainActor in
                self?.runMediumTickIfNeeded()
            }
        }
        scheduler.start()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        fastTickTask?.cancel()
        mediumTickTask?.cancel()
        fastTickTask = nil
        mediumTickTask = nil
        isFastTickRunning = false
        isMediumTickRunning = false
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
            if success {
                hideDesktop = SystemToolsService.isDesktopHidden()
            } else {
                hideDesktop = previous
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
        if let app = StorageCleanerAppService.savedApp() {
            storageCleanerAppName = app.name
            storageCleanerAppIcon = app.icon
        } else {
            storageCleanerAppName = nil
            storageCleanerAppIcon = nil
        }
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

    private func runFastTickIfNeeded() {
        guard isMonitoring, !isFastTickRunning else { return }
        isFastTickRunning = true
        fastTickTask?.cancel()

        fastTickTask = Task(priority: .userInitiated) {
            defer { isFastTickRunning = false }

            let snapshots = await Task.detached {
                (
                    hardware: HardwareMonitor.snapshot(),
                    network: NetworkMonitor.snapshot(),
                    cpu: CPUMonitor.snapshot(),
                    memory: MemoryMonitor.snapshot()
                )
            }.value

            guard !Task.isCancelled, isMonitoring else { return }
            applyFastMetrics(
                hardware: snapshots.hardware,
                network: snapshots.network,
                cpu: snapshots.cpu,
                memory: snapshots.memory
            )
        }
    }

    private func runMediumTickIfNeeded() {
        guard isMonitoring, !isMediumTickRunning else { return }
        isMediumTickRunning = true
        mediumTickTask?.cancel()

        mediumTickTask = Task(priority: .utility) {
            defer { isMediumTickRunning = false }

            let storage = await Task.detached { StorageMonitor.snapshot() }.value

            guard !Task.isCancelled, isMonitoring else { return }
            applyMediumMetrics(storage: storage)
        }
    }

    private func applyFastMetrics(hardware: HardwareSnapshot, network: NetworkSnapshot, cpu: CPUSnapshot, memory: MemorySnapshot) {
        let temperature = ByteFormatting.formatTemperature(hardware.cpuTemperatureCelsius)
        if cpuTemperatureDisplay != temperature {
            cpuTemperatureDisplay = temperature
        }

        let fanRPM = ByteFormatting.formatRPM(hardware.fanRPM)
        if fanRPMDisplay != fanRPM {
            fanRPMDisplay = fanRPM
        }

        if wifiConnected != network.isWifiConnected {
            wifiConnected = network.isWifiConnected
        }
        if uploadSpeedDisplay != network.uploadDisplay {
            uploadSpeedDisplay = network.uploadDisplay
        }
        if downloadSpeedDisplay != network.downloadDisplay {
            downloadSpeedDisplay = network.downloadDisplay
        }

        let cpuLoad = ByteFormatting.formatPercent(cpu.usagePercent)
        if cpuLoadDisplay != cpuLoad {
            cpuLoadDisplay = cpuLoad
        }

        let overview: [(MemoryMetricKey, String, Bool)] = [
            (.physicalMemory, memory.physicalDisplay, true),
            (.used, memory.usedDisplay, false),
            (.cachedFiles, memory.cachedDisplay, false),
            (.swapUsed, memory.swapDisplay, false)
        ]
        if !memoryMetricsEqual(memoryOverview, overview) {
            memoryOverview = overview
        }

        let breakdown: [(MemoryMetricKey, String, Bool)] = [
            (.appMemory, memory.appDisplay, false),
            (.wiredMemory, memory.wiredDisplay, false),
            (.compressed, memory.compressedDisplay, false)
        ]
        if !memoryMetricsEqual(memoryBreakdown, breakdown) {
            memoryBreakdown = breakdown
        }
    }

    private func refreshBatteryMetrics() {
        let battery = BatteryMonitor.snapshot()
        guard batteryDisplay != battery.displayValue || isBatteryCharging != battery.isCharging else { return }
        batteryDisplay = battery.displayValue
        isBatteryCharging = battery.isCharging
    }

    private func applyMediumMetrics(storage: StorageSnapshot) {
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

    private func memoryMetricsEqual(
        _ lhs: [(MemoryMetricKey, String, Bool)],
        _ rhs: [(MemoryMetricKey, String, Bool)]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if left.0 != right.0 || left.1 != right.1 || left.2 != right.2 {
                return false
            }
        }
        return true
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
