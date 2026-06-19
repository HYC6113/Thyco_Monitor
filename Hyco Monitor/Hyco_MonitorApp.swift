//
//  Hyco_MonitorApp.swift
//  Hyco Monitor
//
//  Created by 陈彦杭 on 2026/3/22.
//

import AppKit
import SwiftUI

enum PreviewEnvironment {
    static var isRunning: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

@main
struct Hyco_MonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 纯菜单栏应用：不创建 WindowGroup，界面仅由 AppDelegate 中的 NSPanel 提供。
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Floating Panel

/// 无边框、透明背景、可成为 key 的浮动面板。
/// 主监控面板与小游戏面板共用，差异化配置由 `makeBorderless` 之后各自调整。
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// 创建一个应用了共享默认配置的无边框浮动面板。
    static func makeBorderless(contentRect: NSRect) -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PanelAnimation {
        static let duration: TimeInterval = 0.16
        static let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }

    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var statusBarClickMonitor: Any?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var isPanelClosing = false
    /// 每次发起关闭动画递增；完成回调仅在同代次时执行 orderOut，避免取消关闭后仍被隐藏。
    private var closeAnimationGeneration: UInt = 0
    private let monitorViewModel = SystemMonitorViewModel()
    private let screenCleanController = ScreenCleanController()
    private let typeRacingGameController = TypeRacingGameController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewEnvironment.isRunning else { return }

        MonitorPreferencesService.applySavedAppearance()
        NSApp.setActivationPolicy(.accessory)
        hideDefaultSwiftUIWindows()
        configurePanel()
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
        closePanel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        tearDownEventMonitors()
        MainActor.assumeIsolated {
            typeRacingGameController.dismiss()
            closePanelImmediately()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    private func hideDefaultSwiftUIWindows() {
        for window in NSApp.windows where window !== panel {
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
                beside: self.panel
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
                self.closePanel()
            }
            self.screenCleanController.setActive(enabled, language: self.monitorViewModel.appLanguage)
        }
    }

    private func configurePanel() {
        let rootView = ContentView(viewModel: monitorViewModel)
            .frame(width: MonitorPanelLayout.panelWidth, height: MonitorPanelLayout.panelHeight)
            .clipShape(MonitorTheme.scaledPanelShape)

        let panel = FloatingPanel.makeBorderless(
            contentRect: NSRect(
                x: 0, y: 0,
                width: MonitorPanelLayout.panelWidth,
                height: MonitorPanelLayout.panelHeight
            )
        )
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = NSHostingController(rootView: rootView)

        self.panel = panel
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
        if let statusBarClickMonitor {
            NSEvent.removeMonitor(statusBarClickMonitor)
            self.statusBarClickMonitor = nil
        }

        statusBarClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            guard self.statusItemButtonScreenFrame()?.contains(NSEvent.mouseLocation) == true else {
                return event
            }

            self.togglePanel(nil)
            return nil
        }
    }

    private static func statusBarVisionProImage() -> NSImage? {
        let symbolPointSize: CGFloat = 14
        let canvasHeight: CGFloat = 18
        let horizontalPadding: CGFloat = 1.5
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .heavy)
        guard let symbol = NSImage(systemSymbolName: "visionpro", accessibilityDescription: "Hyco Monitor")?
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

    @objc private func togglePanel(_ sender: AnyObject?) {
        guard let panel else { return }
        if isPanelClosing {
            cancelPanelCloseIfNeeded()
            return
        }
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let button = statusItem?.button else { return }
        guard let origin = panelOrigin(for: button) else { return }

        cancelPanelCloseIfNeeded()

        // 仅在面板可见期间轮询系统指标，隐藏时彻底停掉以降低功耗。
        monitorViewModel.startMonitoring()

        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelAnimation.duration
            context.timingFunction = PanelAnimation.timingFunction
            panel.animator().alphaValue = 1
        }

        installClickOutsideMonitors()
    }

    private func closePanel() {
        guard let panel, panel.isVisible, !isPanelClosing else { return }

        isPanelClosing = true
        removeClickOutsideMonitors()
        let generation = closeAnimationGeneration &+ 1
        closeAnimationGeneration = generation

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = PanelAnimation.duration
            context.timingFunction = PanelAnimation.timingFunction
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.completePanelCloseIfNeeded(generation: generation)
            }
        })
    }

    @MainActor
    private func completePanelCloseIfNeeded(generation: UInt) {
        guard let panel, closeAnimationGeneration == generation else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        isPanelClosing = false
        monitorViewModel.stopMonitoring()
    }

    /// 退出或终止时跳过动画，直接隐藏并停止轮询。
    @MainActor
    private func closePanelImmediately() {
        closeAnimationGeneration &+= 1
        isPanelClosing = false
        removeClickOutsideMonitors()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        monitorViewModel.stopMonitoring()
    }

    /// 关闭动画进行中再次点击菜单栏图标时，取消淡出并保持面板可见。
    private func cancelPanelCloseIfNeeded() {
        guard isPanelClosing else { return }
        closeAnimationGeneration &+= 1
        isPanelClosing = false
        panel?.alphaValue = 1
        if panel?.isVisible == true {
            installClickOutsideMonitors()
        }
    }

    /// 面板上边缘对齐菜单栏下边缘，水平方向相对状态栏图标居中并限制在可见区域内。
    private func panelOrigin(for button: NSStatusBarButton) -> NSPoint? {
        guard let buttonWindow = button.window else { return nil }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var panelX = buttonRect.midX - MonitorPanelLayout.panelWidth / 2
        guard let screen = buttonWindow.screen ?? NSScreen.main else {
            return NSPoint(x: panelX, y: buttonRect.minY - MonitorPanelLayout.panelHeight)
        }
        let visibleFrame = screen.visibleFrame
        panelX = max(visibleFrame.minX + 8, min(panelX, visibleFrame.maxX - MonitorPanelLayout.panelWidth - 8))
        let panelY = visibleFrame.maxY - MonitorPanelLayout.panelHeight
        return NSPoint(x: panelX, y: panelY)
    }

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanelIfClickOutside()
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown where event.keyCode == 53: // Esc：仅主监控面板持有焦点时关闭，避免抢走小游戏 Esc
                guard let panel = self.panel, panel.isKeyWindow else { return event }
                self.closePanel()
                return nil
            case .leftMouseDown, .rightMouseDown:
                self.closePanelIfClickOutside()
            default:
                break
            }
            return event
        }
    }

    private func removeClickOutsideMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func tearDownEventMonitors() {
        removeClickOutsideMonitors()
        if let statusBarClickMonitor {
            NSEvent.removeMonitor(statusBarClickMonitor)
            self.statusBarClickMonitor = nil
        }
    }

    private func closePanelIfClickOutside() {
        guard let panel, panel.isVisible, !isPanelClosing else { return }

        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) { return }
        if statusItemButtonScreenFrame()?.contains(location) == true { return }

        closePanel()
    }

    private func statusItemButtonScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return nil }
        return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
