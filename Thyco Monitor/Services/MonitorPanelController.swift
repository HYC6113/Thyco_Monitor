import AppKit
import SwiftUI

// MARK: - 监控面板定位计算策略

/// 独立于控制器的定位计算策略，负责菜单栏对齐与屏幕工作区约束，方便后续扩展不同的对齐方式和多屏布局。
enum MonitorPanelPositioner {
    @MainActor
    static func calculateOrigin(
        for panelSize: NSSize,
        relativeTo button: NSStatusBarButton?
    ) -> NSPoint? {
        guard let button,
              let buttonWindow = button.window,
              let buttonRect = StatusItemGeometry.screenFrame(of: button) else {
            return nil
        }

        var panelX = buttonRect.midX - panelSize.width / 2
        guard let screen = buttonWindow.screen ?? NSScreen.main else {
            return NSPoint(x: panelX, y: buttonRect.minY - panelSize.height)
        }
        let visibleFrame = screen.visibleFrame
        panelX = max(visibleFrame.minX + 8, min(panelX, visibleFrame.maxX - panelSize.width - 8))
        let panelY = visibleFrame.maxY - panelSize.height
        return NSPoint(x: panelX, y: panelY)
    }
}

// MARK: - 主监控面板控制器

/// 主监控 NSPanel 的创建、显隐动画、定位与点外关闭。
@MainActor
final class MonitorPanelController {
    // MARK: - 动画与配置常量（方便后期优化微调）

    private enum AnimationConfig {
        static let duration: TimeInterval = 0.16
        static let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    }

    // MARK: - 生命周期状态机

    private enum PresentationState: Equatable {
        case hidden
        case presenting
        case visible
        case dismissing
    }

    // MARK: - 依赖与属性

    private let viewModel: SystemMonitorViewModel
    private let statusItemButton: () -> NSStatusBarButton?

    private(set) var panel: FloatingPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?

    private var presentationState: PresentationState = .hidden
    /// 动画事务代次，用于识别并废弃已被打断的旧动画完成回调
    private var animationToken: UInt = 0

    init(
        viewModel: SystemMonitorViewModel,
        statusItemButton: @escaping () -> NSStatusBarButton?
    ) {
        self.viewModel = viewModel
        self.statusItemButton = statusItemButton
        registerScreenProfileObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            self.removeClickOutsideMonitors()
            if let screenParametersObserver = self.screenParametersObserver {
                NotificationCenter.default.removeObserver(screenParametersObserver)
            }
        }
    }

    // MARK: - 初始化配置

    func configure() {
        guard panel == nil else { return }

        let panelSize = NSSize(
            width: MonitorPanelLayout.panelWidth,
            height: MonitorPanelLayout.panelHeight
        )

        let panel = FloatingPanel(
            role: .monitor,
            contentRect: NSRect(origin: .zero, size: panelSize)
        )

        let hostingController = NSHostingController(rootView: ContentView(viewModel: viewModel))
        // 关键性能优化：设置 sizingOptions 为空，阻止 SwiftUI 每次数据刷新向父级发送 preferredContentSize 测量请求
        hostingController.sizingOptions = []
        hostingController.view.frame = NSRect(origin: .zero, size: panelSize)
        hostingController.view.wantsLayer = true

        panel.contentViewController = hostingController
        self.panel = panel
    }

    // MARK: - 显隐控制接口

    func toggle() {
        guard panel != nil else { return }
        switch presentationState {
        case .hidden:
            show()
        case .presenting:
            // 正在展开过程中再次触发，直接反转为关闭
            close()
        case .visible:
            close()
        case .dismissing:
            // 正在收起过程中再次点击，打断收起并重新展开
            show()
        }
    }

    func show() {
        guard let panel else { return }
        guard presentationState != .visible else { return }
        guard let origin = currentPanelOrigin() else { return }

        animationToken &+= 1
        let currentToken = animationToken

        // 仅在面板可见期间轮询系统指标，隐藏时彻底停掉以降低功耗
        viewModel.willPresentPanel()
        viewModel.startMonitoring()

        panel.setFrameOrigin(origin)

        let startAlpha = panel.alphaValue
        if presentationState == .hidden {
            panel.alphaValue = 0
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }

        presentationState = .presenting
        installClickOutsideMonitors()

        // 依据当前实际透明度计算剩余动画时长，支持平滑打断动画
        let targetAlpha: CGFloat = 1.0
        let remainingDistance = Double(abs(targetAlpha - startAlpha))
        let duration = max(0.04, AnimationConfig.duration * remainingDistance)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = AnimationConfig.timingFunction
            panel.animator().alphaValue = targetAlpha
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationToken == currentToken else { return }
                self.presentationState = .visible
                self.panel?.alphaValue = targetAlpha
                // 固化无边框窗口阴影缓存，避免后续每秒指标刷新时重复探测
                self.panel?.invalidateShadow()
            }
        })
    }

    func close() {
        guard let panel, panel.isVisible, presentationState != .hidden, presentationState != .dismissing else {
            return
        }

        // 立即移除点外监视器，防止动画过渡期重复接收外部事件
        removeClickOutsideMonitors()

        animationToken &+= 1
        let currentToken = animationToken
        presentationState = .dismissing

        let startAlpha = panel.alphaValue
        let remainingDistance = Double(startAlpha)
        let duration = max(0.04, AnimationConfig.duration * remainingDistance)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = AnimationConfig.timingFunction
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationToken == currentToken else { return }
                self.completeClose(panel: panel)
            }
        })
    }

    /// 退出或终止时跳过动画，直接隐藏并停止轮询
    func closeImmediately() {
        animationToken &+= 1
        presentationState = .hidden
        removeClickOutsideMonitors()
        guard let panel, panel.isVisible else {
            viewModel.stopMonitoring()
            return
        }
        completeClose(panel: panel)
    }

    private func completeClose(panel: FloatingPanel) {
        panel.orderOut(nil)
        panel.alphaValue = 1
        presentationState = .hidden
        viewModel.stopMonitoring()
    }

    // MARK: - 坐标与屏幕环境

    private func currentPanelOrigin() -> NSPoint? {
        let size = NSSize(
            width: MonitorPanelLayout.panelWidth,
            height: MonitorPanelLayout.panelHeight
        )
        return MonitorPanelPositioner.calculateOrigin(for: size, relativeTo: statusItemButton())
    }

    private func registerScreenProfileObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if let newOrigin = self.currentPanelOrigin() {
                    panel.setFrameOrigin(newOrigin)
                }
            }
        }
    }

    // MARK: - 事件监听与点外关闭优化

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

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()

        // 全局监视器：在其他应用程序中发生点击时触发
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleGlobalMouseDown()
        }

        // 本地监视器：在本应用程序内发生的点击和按键
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown where event.keyCode == 53: // Esc
                // 仅主面板处于关键窗口或可见且无其他窗口接管焦点时关闭，避免抢走小游戏 Esc
                guard let panel = self.panel, panel.isKeyWindow else { return event }
                self.close()
                return nil
            case .leftMouseDown, .rightMouseDown:
                // 核心性能优化：若点击在监控面板本身，瞬间放行，无需进行任何跨进程或全局坐标计算
                if event.window === self.panel {
                    return event
                }
                self.handleLocalMouseDownOutsidePanel()
            default:
                break
            }
            return event
        }
    }

    private func handleGlobalMouseDown() {
        guard let panel, panel.isVisible, presentationState != .hidden, presentationState != .dismissing else { return }

        let mouseLocation = NSEvent.mouseLocation
        if panel.frame.contains(mouseLocation) { return }
        // 若点击在自身的状态栏图标上，放行给状态栏点击逻辑处理，不在此处重复关闭
        if StatusItemGeometry.screenFrame(of: statusItemButton())?.contains(mouseLocation) == true { return }

        close()
    }

    private func handleLocalMouseDownOutsidePanel() {
        guard let panel, panel.isVisible, presentationState != .hidden, presentationState != .dismissing else { return }

        let mouseLocation = NSEvent.mouseLocation
        // 若点击在状态栏图标区域内，交给状态栏处理，避免重复竞争
        if StatusItemGeometry.screenFrame(of: statusItemButton())?.contains(mouseLocation) == true { return }

        close()
    }
}
