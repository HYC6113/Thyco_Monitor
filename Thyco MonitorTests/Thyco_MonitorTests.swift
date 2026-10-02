//
//  Thyco_MonitorTests.swift
//  Thyco MonitorTests
//
//  Created by 陈彦杭 on 2026/3/22.
//

import AppKit
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
        _ = sampler.sample(totals: (1_000_000, 2_000_000), timestamp: 1)
        let live = sampler.sample(totals: (1_000_100, 2_000_200), timestamp: 2)
        #expect(live.upload == 100 && live.download == 200)
        let failed = sampler.sample(totals: nil, timestamp: 3)
        #expect(failed.upload == 0 && failed.download == 0)
        let recovered = sampler.sample(totals: (1_000_300, 2_000_600), timestamp: 4)
        #expect(recovered.upload == 0 && recovered.download == 0)
        let next = sampler.sample(totals: (1_000_400, 2_000_800), timestamp: 5)
        #expect(next.upload == 100 && next.download == 200)
    }

    @Test func networkCountersCanResetWithoutUnderflow() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample(totals: (10_000, 20_000), timestamp: 1)
        let reset = sampler.sample(totals: (100, 200), timestamp: 2)
        #expect(reset.upload == 0 && reset.download == 0)
        let next = sampler.sample(totals: (300, 600), timestamp: 4)
        #expect(next.upload == 100 && next.download == 200)
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
