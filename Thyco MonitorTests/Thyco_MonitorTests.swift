//
//  Thyco_MonitorTests.swift
//  Thyco MonitorTests
//
//  Created by Thyco.
//

import AppKit
import Darwin
import Testing
@testable import Thyco_Monitor

@MainActor
@Suite(.serialized)
struct Thyco_MonitorTests {
    @Test func configureReusesPanel() {
        let controller = MonitorPanelController(
            viewModel: SystemMonitorViewModel(isPreview: true),
            statusItemButton: { nil }
        )
        controller.configure()
        let panel = controller.panel
        controller.configure()

        #expect(controller.panel === panel)
        #expect(panel?.frame.size == NSSize(
            width: MonitorPanelLayout.panelWidth,
            height: MonitorPanelLayout.panelHeight
        ))
    }

    @Test func reopeningDuringDismissalIgnoresOldCompletion() async throws {
        let item = NSStatusBar.system.statusItem(withLength: 24)
        let controller = makeController(for: item)
        defer {
            controller.closeImmediately()
            NSStatusBar.system.removeStatusItem(item)
        }

        controller.show()
        let panel = try #require(controller.panel)
        #expect(panel.isVisible)
        controller.close()
        controller.show()
        try await Task.sleep(for: .milliseconds(350))

        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
    }

    @Test func immediateCloseInvalidatesPresentationCompletion() async throws {
        let item = NSStatusBar.system.statusItem(withLength: 24)
        let controller = makeController(for: item)
        defer {
            controller.closeImmediately()
            NSStatusBar.system.removeStatusItem(item)
        }

        controller.show()
        let panel = try #require(controller.panel)
        #expect(panel.isVisible)
        controller.closeImmediately()
        try await Task.sleep(for: .milliseconds(350))

        #expect(!panel.isVisible)
        // 如果过期的展开回调把状态写回 visible，这次 show() 会被提前返回。
        controller.show()
        #expect(panel.isVisible)
    }

    @Test func shutdownCancelsPendingSpeedTest() async throws {
        let model = SpeedTestModel()
        model.toggle()
        #expect(model.isRunning)
        // 在主线程让出执行权前取消，测试不发起真实网络请求。
        model.shutdown()
        #expect(!model.isRunning)
        #expect(model.phase == .idle)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .idle)
        #expect(model.failureReason == nil)
    }

    @Test func cpuUsageHandlesIndividualCounterWraparound() {
        var sampler = CPUUsageSampler()
        #expect(sampler.sample(user: 100, system: 200, idle: .max - 5, nice: 0) == 0)
        // idle 回绕后增加 10，忙碌计数增加 30，CPU 应为 75%。
        #expect(sampler.sample(user: 120, system: 210, idle: 4, nice: 0) == 75)
        #expect(sampler.sample(user: 120, system: 210, idle: 4, nice: 0) == 0)
    }

    @Test func cpuUsageHandlesAllCounterWraparound() {
        var sampler = CPUUsageSampler()
        _ = sampler.sample(user: .max - 10, system: .max - 10, idle: .max - 10, nice: .max - 10)
        #expect(sampler.sample(user: 5, system: 5, idle: 5, nice: 5) == 75)
    }

    @Test func failedNetworkReadDoesNotCreateLifetimeThroughputSpike() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(interfaces: [0: (upload: 1_000_000, download: 2_000_000)], timestamp: 1)
        let live = sampler.sample(interfaces: [0: (upload: 1_000_100, download: 2_000_200)], timestamp: 2)
        #expect(live.upload == 100 && live.download == 200)
        let failed = sampler.sample(interfaces: nil, timestamp: 3)
        #expect(failed.upload == 0 && failed.download == 0)
        let recovered = sampler.sample(interfaces: [0: (upload: 1_000_300, download: 2_000_600)], timestamp: 4)
        #expect(recovered.upload == 0 && recovered.download == 0)
        let next = sampler.sample(interfaces: [0: (upload: 1_000_400, download: 2_000_800)], timestamp: 5)
        #expect(next.upload == 100 && next.download == 200)
    }

    @Test func networkCountersCanResetWithoutUnderflow() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(interfaces: [0: (upload: 10_000, download: 20_000)], timestamp: 1)
        let reset = sampler.sample(interfaces: [0: (upload: 100, download: 200)], timestamp: 2)
        #expect(reset.upload == 0 && reset.download == 0)
        let next = sampler.sample(interfaces: [0: (upload: 300, download: 600)], timestamp: 4)
        #expect(next.upload == 100 && next.download == 200)
    }

    @Test func kernelNetworkCountersPreserveBytesAcrossFourGiB() throws {
        var sampler = NetworkRateSampler()
        let before = UInt64(UInt32.max) - 100_000_000
        let first = try #require(networkMessage(index: 4, bytes: before).withUnsafeBytes(NetworkInterfaceReader.decode))
        let second = try #require(networkMessage(index: 4, bytes: before + 125_000_000).withUnsafeBytes(NetworkInterfaceReader.decode))
        #expect(second[4]?.download == before + 125_000_000)
        _ = sampler.sample(interfaces: first, timestamp: 1)
        let rate = sampler.sample(interfaces: second, timestamp: 2)
        #expect(rate.upload == 125_000_000 && rate.download == 125_000_000)
    }

    @Test func kernelNetworkParserRejectsTruncatedMessages() {
        let message = networkMessage(index: 4, bytes: 1)
        for length in [1, MemoryLayout<if_msghdr>.size - 1, message.count - 1] {
            #expect(message.prefix(length).withUnsafeBytes(NetworkInterfaceReader.decode) == nil)
        }
    }

    @Test func kernelNetworkParserSkipsAddressMessagesBetweenInterfaces() throws {
        var address = ifa_msghdr()
        address.ifam_msglen = UInt16(MemoryLayout<ifa_msghdr>.stride)
        address.ifam_type = UInt8(RTM_NEWADDR)
        var messages = networkMessage(index: 4, bytes: 100)
        withUnsafeBytes(of: &address) { messages.append(contentsOf: $0) }
        messages.append(networkMessage(index: 5, bytes: 200))
        let counters = try #require(messages.withUnsafeBytes(NetworkInterfaceReader.decode))
        #expect(counters[4]?.download == 100)
        #expect(counters[5]?.download == 200)
    }

    @Test func disappearingNetworkInterfaceDoesNotEraseOtherTraffic() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(interfaces: [4: (100, 200), 5: (9_000, 9_000)], timestamp: 1)
        let rate = sampler.sample(interfaces: [4: (200, 400), 6: (30_000, 30_000)], timestamp: 2)
        #expect(rate.upload == 100 && rate.download == 200)
    }

    @Test func typeRacingVisibleCharactersMatchOnScreenStream() throws {
        let laneWidth: CGFloat = 500
        let engine = TypeRacingGameEngine()
        engine.prepare(language: .eng)
        engine.configureLaneWidth(laneWidth)
        engine.handleInput(" ")
        // 约 25 秒：滚动距离超过起始位置，最早打过的字符已滚出左缘。
        for frame in 0..<1_500 {
            if frame.isMultiple(of: 25) {
                engine.handleInput(String(engine.streamText[engine.streamIndex]))
            }
            engine.tick(delta: 1.0 / 60.0)
        }
        try #require(engine.phase == .playing)

        let width = TypeRacingGameEngine.charWidth
        let expected = engine.streamText.indices.filter { index in
            let x = laneWidth * 0.68 + CGFloat(index) * width - engine.streamOffset
            return x > -width && x < laneWidth + width * 2
        }
        let visible = engine.visibleCharacters()
        #expect((expected.first ?? 0) > 0)
        #expect(visible.map(\.index) == expected)
        #expect(visible.first { $0.state == .current }?.index == engine.streamIndex)
    }

    private func networkMessage(index: UInt16, bytes: UInt64) -> Data {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.stride + MemoryLayout<sockaddr_dl>.stride)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = index
        header.ifm_data.ifi_ibytes = bytes
        header.ifm_data.ifi_obytes = bytes
        var address = sockaddr_dl()
        address.sdl_family = UInt8(AF_LINK)
        address.sdl_nlen = 3
        address.sdl_data.0 = CChar(UInt8(ascii: "e"))
        address.sdl_data.1 = CChar(UInt8(ascii: "n"))
        address.sdl_data.2 = CChar(UInt8(ascii: "0"))
        var data = withUnsafeBytes(of: &header) { Data($0) }
        withUnsafeBytes(of: &address) { data.append(contentsOf: $0) }
        return data
    }

    private func makeController(for item: NSStatusItem) -> MonitorPanelController {
        let controller = MonitorPanelController(
            viewModel: SystemMonitorViewModel(isPreview: true),
            statusItemButton: { item.button }
        )
        controller.configure()
        return controller
    }
}
