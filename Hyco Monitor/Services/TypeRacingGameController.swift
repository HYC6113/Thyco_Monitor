import AppKit
import SwiftUI

@MainActor
final class TypeRacingGameController: NSObject {
    private var panel: FloatingPanel?
    private let windowDelegate = TypeRacingWindowDelegate()

    var isPresented: Bool { panel != nil }

    override init() {
        super.init()
        windowDelegate.onClose = { [weak self] in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    func present(
        colorScheme: ColorScheme,
        language: AppLanguage,
        beside monitorPanel: NSWindow?
    ) {
        let screen = monitorPanel?.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero
        let panelFrame = resolvedPanelFrame(relativeTo: monitorPanel, on: screenFrame)

        if let panel {
            panel.setFrame(panelFrame, display: true)
            bringPanelToFront(panel)
            return
        }

        let contentSize = TypeRacingWindowLayout.contentSize
        let panel = FloatingPanel.makeBorderless(contentRect: panelFrame)
        applyGamePanelConfiguration(to: panel)

        let rootView = TypeRacingGameView(
            language: language,
            colorScheme: colorScheme
        ) { [weak self] in
            self?.dismiss()
        }
        .frame(width: contentSize.width, height: contentSize.height)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = .preferredContentSize
        hostingController.view.setFrameSize(NSSize(width: contentSize.width, height: contentSize.height))

        panel.contentViewController = hostingController
        self.panel = panel
        bringPanelToFront(panel)
    }

    func dismiss() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.delegate = nil
        self.panel = nil
    }

    private func bringPanelToFront(_ panel: FloatingPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func applyGamePanelConfiguration(to panel: FloatingPanel) {
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = windowDelegate
    }

    private func resolvedPanelFrame(relativeTo monitorPanel: NSWindow?, on screenFrame: NSRect) -> NSRect {
        guard let monitorPanel else {
            return TypeRacingWindowLayout.centeredFrame(on: screenFrame)
        }

        let anchor = monitorPanel.frame
        guard anchor.width > 1, anchor.height > 1 else {
            return TypeRacingWindowLayout.centeredFrame(on: screenFrame)
        }

        return TypeRacingWindowLayout.frameToLeft(of: anchor, on: screenFrame)
    }
}

private final class TypeRacingWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
