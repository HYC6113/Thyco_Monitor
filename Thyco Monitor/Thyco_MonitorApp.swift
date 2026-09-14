//
//  Thyco_MonitorApp.swift
//  Thyco Monitor
//
//  Created by Thyco.
//

import AppKit
import SwiftUI

enum PreviewEnvironment {
    static var isRunning: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

@main
struct Thyco_MonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 纯菜单栏应用：不创建 WindowGroup，界面仅由 AppDelegate 中的 NSPanel 提供。
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusBarClickMonitor: Any?
    private let monitorViewModel = SystemMonitorViewModel()
    private let screenCleanController = ScreenCleanController()
    private let typeRacingGameController = TypeRacingGameController()
    private lazy var panelController = MonitorPanelController(
        viewModel: monitorViewModel,
        statusItemButton: { [weak self] in self?.statusItem?.button }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewEnvironment.isRunning else { return }

        MonitorPreferencesService.applySavedAppearance()
        NSApp.setActivationPolicy(.accessory)
        hideDefaultSwiftUIWindows()
        panelController.configure()
        configureStatusItem()
        configureScreenClean()
        configureTypeRacing()

        // 监听应用失去焦点事件（如 Cmd+Tab 切换到其他应用），自动关闭面板
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidResignActive() {
        panelController.close()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        tearDownStatusBarClickMonitor()
        MainActor.assumeIsolated {
            typeRacingGameController.dismiss()
            panelController.closeImmediately()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    private func hideDefaultSwiftUIWindows() {
        for window in NSApp.windows where window !== panelController.panel {
            window.orderOut(nil)
        }
    }

    private func configureTypeRacing() {
        monitorViewModel.onPresentTypeRacing = { [weak self] in
            guard let self else { return }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let scheme: ColorScheme = isDark ? .dark : .light
            self.typeRacingGameController.present(
                colorScheme: scheme,
                language: self.monitorViewModel.appLanguage,
                beside: self.panelController.panel
            )
        }
    }

    private func configureScreenClean() {
        screenCleanController.onDismiss = { [weak self] in
            self?.monitorViewModel.dismissCleanMode()
        }
        monitorViewModel.onCleanModeChange = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.panelController.close()
            }
            self.screenCleanController.setActive(enabled, language: self.monitorViewModel.appLanguage)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.statusBarVisionProImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = nil
            // 不绑定 target/action，改由本地事件监听触发，避免系统按钮的按下高亮。
            if let cell = button.cell as? NSButtonCell {
                cell.highlightsBy = []
            }
        }
        statusItem = item
        installStatusBarClickMonitor()
    }

    /// 拦截菜单栏图标的鼠标按下事件，手动触发面板开关并吞掉事件，从而禁用系统高亮反馈。
    private func installStatusBarClickMonitor() {
        tearDownStatusBarClickMonitor()

        statusBarClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            guard StatusItemGeometry.screenFrame(of: self.statusItem?.button)?.contains(NSEvent.mouseLocation) == true else {
                return event
            }

            self.panelController.toggle()
            return nil
        }
    }

    private func tearDownStatusBarClickMonitor() {
        if let statusBarClickMonitor {
            NSEvent.removeMonitor(statusBarClickMonitor)
            self.statusBarClickMonitor = nil
        }
    }

    private static func statusBarVisionProImage() -> NSImage? {
        let symbolPointSize: CGFloat = 14
        let canvasHeight: CGFloat = 18
        let horizontalPadding: CGFloat = 1.5
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .heavy)
        guard let symbol = NSImage(systemSymbolName: "visionpro", accessibilityDescription: "Thyco Monitor")?
            .withSymbolConfiguration(configuration) else {
            return nil
        }

        let canvasWidth = symbol.size.width + horizontalPadding * 2
        let drawRect = NSRect(
            x: horizontalPadding,
            y: (canvasHeight - symbol.size.height) / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )

        let image = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight), flipped: false) { _ in
            symbol.draw(in: drawRect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
