import CoreAudio
import Foundation

/// CoreAudio 传输类型。只在同名设备需要区分时显示给用户。
enum AudioDeviceTransport: Hashable {
    case builtIn
    case aggregate
    case virtual
    case pci
    case usb
    case fireWire
    case bluetooth
    case bluetoothLE
    case hdmi
    case displayPort
    case airPlay
    case avb
    case thunderbolt
    case continuityWired
    case continuityWireless
    case remoteScreen
    case remoteStreaming
    case unknown

    init(coreAudioValue: UInt32) {
        switch coreAudioValue {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeAggregate:
            self = .aggregate
        case kAudioDeviceTransportTypeVirtual:
            self = .virtual
        case kAudioDeviceTransportTypePCI:
            self = .pci
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeFireWire:
            self = .fireWire
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeHDMI:
            self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort:
            self = .displayPort
        case kAudioDeviceTransportTypeAirPlay:
            self = .airPlay
        case kAudioDeviceTransportTypeAVB:
            self = .avb
        case kAudioDeviceTransportTypeThunderbolt:
            self = .thunderbolt
        case kAudioDeviceTransportTypeContinuityCaptureWired:
            self = .continuityWired
        case kAudioDeviceTransportTypeContinuityCaptureWireless:
            self = .continuityWireless
        case kAudioDeviceTransportTypeRemoteScreen:
            self = .remoteScreen
        case kAudioDeviceTransportTypeRemoteStreaming:
            self = .remoteStreaming
        default:
            self = .unknown
        }
    }

    func localizedName(language: AppLanguage) -> String? {
        let chinese: String
        let english: String
        switch self {
        case .builtIn:
            (chinese, english) = ("内建", "Built-in")
        case .aggregate:
            (chinese, english) = ("聚合", "Aggregate")
        case .virtual:
            (chinese, english) = ("虚拟", "Virtual")
        case .pci:
            (chinese, english) = ("PCI", "PCI")
        case .usb:
            (chinese, english) = ("USB", "USB")
        case .fireWire:
            (chinese, english) = ("FireWire", "FireWire")
        case .bluetooth:
            (chinese, english) = ("蓝牙", "Bluetooth")
        case .bluetoothLE:
            (chinese, english) = ("蓝牙 LE", "Bluetooth LE")
        case .hdmi:
            (chinese, english) = ("HDMI", "HDMI")
        case .displayPort:
            (chinese, english) = ("DisplayPort", "DisplayPort")
        case .airPlay:
            (chinese, english) = ("隔空播放", "AirPlay")
        case .avb:
            (chinese, english) = ("AVB", "AVB")
        case .thunderbolt:
            (chinese, english) = ("雷雳", "Thunderbolt")
        case .continuityWired:
            (chinese, english) = ("连续互通（有线）", "Continuity (Wired)")
        case .continuityWireless:
            (chinese, english) = ("连续互通（无线）", "Continuity (Wireless)")
        case .remoteScreen:
            (chinese, english) = ("屏幕共享", "Screen Share")
        case .remoteStreaming:
            (chinese, english) = ("远程串流", "Remote Stream")
        case .unknown:
            return nil
        }
        return language == .chs ? chinese : english
    }
}

/// 面板上的一条设备标题。`qualifier` 只在同名设备之间出现。
struct AudioDeviceLabel: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let qualifier: String?

    var accessibilityText: String {
        guard let qualifier, !qualifier.isEmpty else { return name }
        return "\(name) · \(qualifier)"
    }
}

enum AudioDeviceLabeler {
    /// 名称唯一时不附加说明。同名时按传输类型、厂牌、型号的顺序取最短的区分信息；
    /// 仍然相同则按 UID 编一个稳定序号，避免列表行和点击目标叠在一起。
    static func labels(for devices: [AudioDevice], language: AppLanguage) -> [AudioDeviceLabel] {
        let groups = Dictionary(grouping: devices, by: \.groupingName)
        return devices.map { device in
            let siblings = groups[device.groupingName] ?? [device]
            let name = device.displayName
            guard siblings.count > 1 else {
                return AudioDeviceLabel(id: device.id, name: name, qualifier: nil)
            }
            return AudioDeviceLabel(
                id: device.id,
                name: name,
                qualifier: qualifier(for: device, among: siblings, language: language)
            )
        }
    }

    private static func qualifier(
        for device: AudioDevice,
        among siblings: [AudioDevice],
        language: AppLanguage
    ) -> String {
        let mine = tokens(for: device, language: language)
        let siblingTokens = siblings.map { tokens(for: $0, language: language) }

        if !mine.isEmpty {
            for length in 1...mine.count {
                let prefix = Array(mine.prefix(length))
                let matchCount = siblingTokens.filter { Array($0.prefix(length)) == prefix }.count
                if matchCount == 1 {
                    return mine[length - 1]
                }
            }
        }

        let peers = siblings.filter { tokens(for: $0, language: language) == mine }
        let ordered = peers.sorted { lhs, rhs in
            let uidOrder = lhs.uid.localizedStandardCompare(rhs.uid)
            if uidOrder != .orderedSame { return uidOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
        let index = (ordered.firstIndex { $0.id == device.id } ?? 0) + 1
        if let context = mine.first {
            return "\(context) · \(index)"
        }
        return "\(index)"
    }

    private static func tokens(for device: AudioDevice, language: AppLanguage) -> [String] {
        var tokens: [String] = []
        if let transport = device.transport.localizedName(language: language) {
            tokens.append(transport)
        }
        let brand = brand(for: device)
        if !brand.isEmpty {
            tokens.append(brand)
        }
        let model = shortModel(for: device, brand: brand)
        if !model.isEmpty {
            tokens.append(model)
        }
        return tokens
    }

    private static let corporateSuffixes: Set<String> = [
        "inc", "incorporated", "corp", "corporation", "ltd", "limited", "llc",
        "gmbh", "co", "company", "ag", "sa", "bv", "plc", "kk"
    ]

    private static let genericBrandWords: Set<String> = [
        "audio", "electronics", "electronic", "technology", "technologies",
        "systems", "system", "semiconductor", "computer", "computers",
        "digital", "international", "electric"
    ]

    private static func brand(for device: AudioDevice) -> String {
        let raw = device.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        let tokens = raw
            .split { $0.isWhitespace || $0 == "," }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty && !corporateSuffixes.contains($0.lowercased()) }
        guard let first = tokens.first else { return "" }

        let candidate: String
        if tokens.count >= 2, !genericBrandWords.contains(tokens[1].lowercased()) {
            let two = "\(first) \(tokens[1])"
            candidate = two.count <= 18 ? two : first
        } else {
            candidate = first
        }

        guard candidate.count <= 18 else { return "" }
        let name = device.displayName
        if candidate.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return ""
        }
        if name.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return ""
        }
        return candidate
    }

    private static func shortModel(for device: AudioDevice, brand: String) -> String {
        var model = device.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return "" }

        if !brand.isEmpty {
            let prefix = brand + " "
            if model.lowercased().hasPrefix(prefix.lowercased()) {
                model = String(model.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !model.isEmpty, model.count <= 22 else { return "" }
        let name = device.displayName
        if model.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return ""
        }
        if !brand.isEmpty,
           model.compare(brand, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return ""
        }
        if name.range(of: model, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return ""
        }
        return model
    }
}

extension AudioDevice {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    var groupingName: String {
        displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
