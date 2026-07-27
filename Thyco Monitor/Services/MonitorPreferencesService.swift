import AppKit
import Foundation

enum MonitorAppearance: String {
    case light
    case dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// 用户界面偏好（语言、浅暗色），持久化于 UserDefaults
enum MonitorPreferencesService {
    private static let languageKey = "appLanguage"
    private static let appearanceKey = "appearanceMode"

    static func savedLanguage() -> AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: languageKey),
              let language = AppLanguage(rawValue: raw) else {
            return .chs
        }
        return language
    }

    static func saveLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }

    static func savedAppearance() -> MonitorAppearance? {
        guard let raw = UserDefaults.standard.string(forKey: appearanceKey),
              let appearance = MonitorAppearance(rawValue: raw) else {
            return nil
        }
        return appearance
    }

    static func saveAppearance(_ appearance: MonitorAppearance) {
        UserDefaults.standard.set(appearance.rawValue, forKey: appearanceKey)
    }

    @MainActor
    static func applyAppearance(_ appearance: MonitorAppearance) {
        NSApp.appearance = appearance.nsAppearance
    }

    @MainActor
    static func applySystemAppearance() {
        NSApp.appearance = nil
    }

    @MainActor
    static func applySavedAppearance() {
        if let appearance = savedAppearance() {
            applyAppearance(appearance)
        } else {
            applySystemAppearance()
        }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: languageKey)
        UserDefaults.standard.removeObject(forKey: appearanceKey)
    }
}
