import AudioToolbox
import CoreAudio
import Foundation

/// 音频控制（移植自 Hyco_精简版 AudioManager 的 System Sound 能力）
@MainActor
final class AudioManager {
    var onStateChanged: (() -> Void)?

    private(set) var balance: Double = 0
    private(set) var volume: Double = 50
    private(set) var outputDevices: [AudioDevice] = []
    private(set) var inputDevices: [AudioDevice] = []
    private(set) var selectedOutputDeviceID: AudioDeviceID?
    private(set) var selectedInputDeviceID: AudioDeviceID?

    private var isRunning = false
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerDeviceID: AudioDeviceID?
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshOutputDevices()
        refreshInputDevices()
        readCurrentOutputDevice()
        readCurrentInputDevice()
        readCurrentVolume()
        readCurrentBalance()
        setupListeners()
        notifyStateChanged()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeListeners()
    }

    func setOutputDeviceByName(_ name: String) {
        guard let device = outputDevices.first(where: { $0.name == name }) else { return }
        setOutputDevice(device)
    }

    func setInputDeviceByName(_ name: String) {
        guard let device = inputDevices.first(where: { $0.name == name }) else { return }
        setInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )

        guard status == noErr else { return }

        selectedOutputDeviceID = device.id
        registerVolumeListener(for: device.id)
        readCurrentVolume()
        readCurrentBalance()
        notifyStateChanged()
    }

    func setInputDevice(_ device: AudioDevice) {
        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )

        guard status == noErr else { return }

        selectedInputDeviceID = device.id
        notifyStateChanged()
    }

    func setVolume(_ newVolume: Double) {
        guard let deviceID = effectiveOutputDeviceID() else { return }

        let clamped = max(0, min(100, newVolume.rounded()))
        let volumeValue = Float32(clamped / 100.0)

        if clamped <= 0 {
            setOutputMute(deviceID: deviceID, muted: true)
            _ = setMasterVolume(deviceID: deviceID, volume: 0)
            setAllChannelVolumes(deviceID: deviceID, volume: 0)
        } else {
            setOutputMute(deviceID: deviceID, muted: false)
            _ = setMasterVolume(deviceID: deviceID, volume: volumeValue)
            setAllChannelVolumes(deviceID: deviceID, volume: volumeValue)
        }

        volume = clamped
        notifyStateChanged()
    }

    func applyBalance(_ newBalance: Double) {
        balance = newBalance

        guard let deviceID = effectiveOutputDeviceID() else { return }

        let normalizedBalance = newBalance / 50.0
        let leftVolume: Float32
        let rightVolume: Float32

        if normalizedBalance <= 0 {
            leftVolume = 1.0
            rightVolume = Float32(1.0 + normalizedBalance)
        } else {
            leftVolume = Float32(1.0 - normalizedBalance)
            rightVolume = 1.0
        }

        if !applyStereoPan(deviceID: deviceID, balance: newBalance) {
            applyChannelVolumes(deviceID: deviceID, leftVolume: leftVolume, rightVolume: rightVolume)
        }

        notifyStateChanged()
    }

    func refreshAll() {
        refreshOutputDevices()
        refreshInputDevices()
        readCurrentOutputDevice()
        readCurrentInputDevice()
        readCurrentVolume()
        readCurrentBalance()
        notifyStateChanged()
    }

    // MARK: - Listeners

    private func setupListeners() {
        removeListeners()

        if let deviceID = effectiveOutputDeviceID() {
            registerVolumeListener(for: deviceID)
        }

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        defaultOutputListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.readCurrentOutputDevice()
                self?.readCurrentVolume()
                self?.readCurrentBalance()
                self?.notifyStateChanged()
            }
        }
        if let block = defaultOutputListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputAddress,
                DispatchQueue.main,
                block
            )
        }

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        defaultInputListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.readCurrentInputDevice()
                self?.notifyStateChanged()
            }
        }
        if let block = defaultInputListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                DispatchQueue.main,
                block
            )
        }

        var devicesListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        devicesListListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshOutputDevices()
                self?.refreshInputDevices()
                self?.readCurrentOutputDevice()
                self?.readCurrentInputDevice()
                self?.notifyStateChanged()
            }
        }
        if let block = devicesListListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesListAddress,
                DispatchQueue.main,
                block
            )
        }
    }

    private func registerVolumeListener(for deviceID: AudioDeviceID) {
        if volumeListenerDeviceID == deviceID, volumeListenerBlock != nil {
            return
        }

        removeVolumeListener()

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &volumeAddress) else { return }

        volumeListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.readCurrentVolume()
                self?.notifyStateChanged()
            }
        }

        if let block = volumeListenerBlock {
            AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)
            volumeListenerDeviceID = deviceID
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &muteAddress) {
            muteListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    self?.readCurrentVolume()
                    self?.notifyStateChanged()
                }
            }

            if let block = muteListenerBlock {
                AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
            }
        }
    }

    private func removeVolumeListener() {
        guard let deviceID = volumeListenerDeviceID else { return }

        if let block = volumeListenerBlock {
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)
            volumeListenerBlock = nil
        }

        if let block = muteListenerBlock {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
            muteListenerBlock = nil
        }

        volumeListenerDeviceID = nil
    }

    private func removeListeners() {
        removeVolumeListener()

        if let block = defaultOutputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            defaultOutputListenerBlock = nil
        }

        if let block = defaultInputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            defaultInputListenerBlock = nil
        }

        if let block = devicesListListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            devicesListListenerBlock = nil
        }
    }

    // MARK: - Read State

    private func refreshOutputDevices() {
        outputDevices = getAvailableOutputDevices()
            .map { AudioDevice(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshInputDevices() {
        inputDevices = getAvailableInputDevices()
            .map { AudioDevice(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readCurrentOutputDevice() {
        guard let deviceID = getDefaultOutputDevice(),
              let name = getDeviceName(for: deviceID)
        else { return }

        selectedOutputDeviceID = deviceID
        if !outputDevices.contains(where: { $0.id == deviceID }) {
            outputDevices.append(AudioDevice(id: deviceID, name: name))
            outputDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        registerVolumeListener(for: deviceID)
    }

    private func readCurrentInputDevice() {
        guard let deviceID = getDefaultInputDevice(),
              let name = getDeviceName(for: deviceID)
        else { return }

        selectedInputDeviceID = deviceID
        if !inputDevices.contains(where: { $0.id == deviceID }) {
            inputDevices.append(AudioDevice(id: deviceID, name: name))
            inputDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func readCurrentVolume() {
        guard let deviceID = effectiveOutputDeviceID() else { return }

        if isOutputMuted(deviceID: deviceID) {
            volume = 0
            return
        }

        if let leftVolume = getChannelVolume(deviceID: deviceID, channel: 1),
           let rightVolume = getChannelVolume(deviceID: deviceID, channel: 2) {
            volume = Double((leftVolume + rightVolume) / 2.0) * 100.0
            return
        }

        if let leftVolume = getChannelVolume(deviceID: deviceID, channel: 1) {
            volume = Double(leftVolume) * 100.0
            return
        }

        if let masterVolume = getMasterVolume(deviceID: deviceID) {
            volume = Double(masterVolume) * 100.0
        }
    }

    private func readCurrentBalance() {
        guard let deviceID = effectiveOutputDeviceID() else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStereoPan,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &address) {
            var pan: Float32 = 0.5
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &pan)
            if status == noErr {
                balance = Double(pan) * 100.0 - 50.0
                return
            }
        }

        if let leftVolume = getChannelVolume(deviceID: deviceID, channel: 1),
           let rightVolume = getChannelVolume(deviceID: deviceID, channel: 2) {
            balance = Double(rightVolume - leftVolume) * 50.0
        }
    }

    // MARK: - Volume / Balance Helpers

    private func effectiveOutputDeviceID() -> AudioDeviceID? {
        if let selectedOutputDeviceID { return selectedOutputDeviceID }
        return getDefaultOutputDevice()
    }

    @discardableResult
    private func setMasterVolume(deviceID: AudioDeviceID, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return false }

        var volumeValue = volume
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &volumeValue
        ) == noErr
    }

    @discardableResult
    private func setChannelVolume(deviceID: AudioDeviceID, channel: UInt32, volume: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return false }

        var volumeValue = volume
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &volumeValue
        ) == noErr
    }

    private func getChannelVolume(deviceID: AudioDeviceID, channel: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return volume
    }

    private func getMasterVolume(deviceID: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return volume
    }

    private func setAllChannelVolumes(deviceID: AudioDeviceID, volume: Float32) {
        let channels = max(Int(outputChannelCount(for: deviceID)), 2)
        for channel in 1...min(channels, 32) {
            _ = setChannelVolume(deviceID: deviceID, channel: UInt32(channel), volume: volume)
        }
    }

    @discardableResult
    private func setOutputMute(deviceID: AudioDeviceID, muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return false }

        var muteValue: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &muteValue
        ) == noErr
    }

    private func isOutputMuted(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue) == noErr else {
            return false
        }
        return muteValue != 0
    }

    @discardableResult
    private func applyStereoPan(deviceID: AudioDeviceID, balance: Double) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStereoPan,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return false }

        var pan = Float32((balance + 50.0) / 100.0)
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &pan
        ) == noErr
    }

    private func applyChannelVolumes(deviceID: AudioDeviceID, leftVolume: Float32, rightVolume: Float32) {
        let masterVolume = getMasterVolume(deviceID: deviceID) ?? 1.0
        _ = setChannelVolume(deviceID: deviceID, channel: 1, volume: leftVolume * masterVolume)
        _ = setChannelVolume(deviceID: deviceID, channel: 2, volume: rightVolume * masterVolume)
    }

    // MARK: - Device Discovery

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        readDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func getDefaultInputDevice() -> AudioDeviceID? {
        readDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private func readDefaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        return deviceID
    }

    private func getAvailableOutputDevices() -> [(id: AudioDeviceID, name: String)] {
        enumerateDevices { deviceID in
            guard outputChannelCount(for: deviceID) > 0 else { return nil }
            guard let name = getDeviceName(for: deviceID) else { return nil }
            return (deviceID, name)
        }
    }

    private func getAvailableInputDevices() -> [(id: AudioDeviceID, name: String)] {
        enumerateDevices { deviceID in
            guard inputChannelCount(for: deviceID) > 0 else { return nil }
            guard let name = getDeviceName(for: deviceID) else { return nil }
            return (deviceID, name)
        }
    }

    private func enumerateDevices(
        _ transform: (AudioDeviceID) -> (id: AudioDeviceID, name: String)?
    ) -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap(transform)
    }

    private func outputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput)
    }

    private func inputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)
    }

    private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return 0
        }

        return UnsafeMutableAudioBufferListPointer(bufferListPointer)
            .reduce(0) { $0 + $1.mNumberChannels }
    }

    private func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return nil
        }

        let namePtr = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        defer { namePtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, namePtr) == noErr,
              let unmanagedName = namePtr.pointee
        else {
            return nil
        }

        return unmanagedName.takeUnretainedValue() as String
    }

    private func notifyStateChanged() {
        onStateChanged?()
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}
