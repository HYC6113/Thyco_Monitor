import AppKit
import SwiftUI

/// 测速 NSPanel。尺寸与 Type Racing 面板一致，并同样贴在主监控面板左侧。
@MainActor
final class SpeedTestPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var model: SpeedTestModel?
    private var escMonitor: Any?

    func present(
        colorScheme: ColorScheme,
        language: AppLanguage,
        beside monitorPanel: NSWindow?
    ) {
        let panelFrame = TypeRacingWindowLayout.frame(beside: monitorPanel)

        if let panel {
            panel.setFrame(panelFrame, display: true)
            bringPanelToFront(panel)
            return
        }

        let contentSize = TypeRacingWindowLayout.contentSize
        let panel = FloatingPanel(role: .speedTest, contentRect: panelFrame)
        panel.delegate = self

        let model = SpeedTestModel()
        self.model = model
        let rootView = SpeedTestPanelView(
            language: language,
            colorScheme: colorScheme,
            model: model
        ) { [weak self] in
            self?.dismiss()
        }
        .frame(width: contentSize.width, height: contentSize.height)

        let hostingController = NSHostingController(rootView: rootView)
        // 尺寸已由 contentRect 固定。空 sizingOptions 避免测速刷新时反复回传 preferredContentSize。
        hostingController.sizingOptions = []
        hostingController.view.setFrameSize(NSSize(width: contentSize.width, height: contentSize.height))

        panel.contentViewController = hostingController
        self.panel = panel
        installEscMonitor()
        model.loadIdentity()
        bringPanelToFront(panel)
    }

    func dismiss() {
        guard let panel else { return }
        // 窗口关闭时同步取消任务，不依赖 NSHostingController 的 onDisappear 时机。
        model?.shutdown()
        model = nil
        removeEscMonitor()
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.delegate = nil
        self.panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }

    private func bringPanelToFront(_ panel: FloatingPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let self, self.panel?.isKeyWindow == true else { return event }
            self.dismiss()
            return nil
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
