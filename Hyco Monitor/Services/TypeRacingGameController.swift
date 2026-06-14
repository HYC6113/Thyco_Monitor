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
            self?.panel = nil
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
            // 已存在则只重新定位并前置；键盘焦点由内部捕获视图自行维持，
            // 此处不强制 makeFirstResponder(contentView)，否则会抢走输入焦点。
            panel.setFrame(panelFrame, display: true)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let contentSize = TypeRacingWindowLayout.contentSize

        let panel = FloatingPanel.makeBorderless(contentRect: panelFrame)
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = windowDelegate

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
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
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
