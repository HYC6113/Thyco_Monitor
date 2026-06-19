import Foundation

enum AppLanguage: String, CaseIterable, Hashable {
    case chs
    case eng

    var segmentTitle: String {
        switch self {
        case .chs: "CHS"
        case .eng: "ENG"
        }
    }
}

struct MonitorStrings {
    let language: AppLanguage

    var cpuNetworkTitle: String { t("CPU / 网络", "CPU / Network") }
    var storageTitle: String { t("存储", "Storage") }
    var batteryToolsTitle: String { t("电池 / 工具", "Battery / Tools") }
    var memoryTitle: String { t("内存", "Memory") }
    var soundTitle: String { t("声音", "Sound") }

    var cpuTemperature: String { t("CPU 温度", "CPU Temp") }
    var fan: String { t("风扇", "Fan") }
    var upload: String { t("上传", "Upload") }
    var download: String { t("下载", "Download") }
    var wifiConnected: String { t("Wi-Fi已连接", "Wi-Fi Connected") }
    var wifiDisconnected: String { t("Wi-Fi未连接", "Wi-Fi Not Connected") }
    var availableSpace: String { t("可用空间", "Available") }
    var used: String { t("已用", "Used") }
    var total: String { t("总计", "Total") }
    var pickCleanerApp: String { t("选择清理工具", "Choose Cleaner") }
    var openCleanerApp: String { t("打开清理工具", "Open Cleaner") }
    var changeCleanerApp: String { t("更换应用", "Change App") }
    var clearCleanerApp: String { t("清除选择", "Clear Selection") }
    var cleanStorage: String { t("清理", "Clean") }
    var batteryLevel: String { t("电量", "Battery") }
    var chargingPowerLabel: String { t("充电功率 ", "Chg. ") }
    func chargingPowerValue(_ watts: String) -> String { "\(watts)W" }
    var cpuLoad: String { t("CPU 负载", "CPU Load") }
    var hideDesktop: String { t("隐藏桌面", "Hide Desktop") }
    var cleanMode: String { t("清洁模式", "Clean Mode") }
    var typeRacingDistance: String { t("行驶里程", "Distance") }
    var typeRacingChaseSpeed: String { t("追车速度", "Chase") }
    var typeRacingReadyTitle: String { t("Type Racing", "Type Racing") }
    var typeRacingReadyHint: String { t("按空格键开始游戏", "Press Space to start") }
    var typeRacingCaughtTitle: String { t("被追上了！", "Caught!") }
    var typeRacingCaughtHint: String { t("按空格重新开始", "Press Space to retry") }
    func typeRacingBest(_ meters: Int) -> String {
        t("最佳 \(meters) m", "Best \(meters) m")
    }
    var typeRacingClose: String { t("关闭", "Close") }
    var typeRacingPressEscToExit: String { t("按 ESC 退出游戏", "Press ESC to exit") }
    var typeRacingExitSuffix: String { t("退出游戏", "to exit") }
    var typeRacingClearSavedData: String { t("清除本地游戏记录", "Clear saved game data") }
    var cleanModeExitPrefix: String { t("按", "Press") }
    var cleanModeExitSuffix: String { t("退出", "to exit") }
    var cleanModeExitKey: String { "ESC" }
    var memoryOverviewTitle: String { t("内存概览", "Memory Overview") }
    var memoryOverview: String { t("概览", "Overview") }
    var memoryBreakdown: String { t("已用细分", "Breakdown") }
    var outputDevice: String { t("输出设备", "Output") }
    var inputDevice: String { t("输入设备", "Input") }
    var volume: String { t("音量", "Volume") }
    var balance: String { t("平衡", "Balance") }
    var balanceLeft: String { t("偏左", "Left") }
    var balanceRight: String { t("偏右", "Right") }
    var noAvailableDevices: String { t("无可用设备", "No Devices") }
    var noOutputDevice: String { t("无输出设备", "No Output") }
    var noInputDevice: String { t("无输入设备", "No Input") }

    func memoryLabel(for key: MemoryMetricKey) -> String {
        switch key {
        case .physicalMemory: t("物理内存", "Physical")
        case .used: t("已用", "Used")
        case .cachedFiles: t("缓存", "Cached")
        case .swapUsed: t("交换", "Swap")
        case .appMemory: t("App", "App")
        case .wiredMemory: t("联动", "Wired")
        case .compressed: t("压缩", "Compr.")
        }
    }

    private func t(_ chinese: String, _ english: String) -> String {
        language == .chs ? chinese : english
    }
}