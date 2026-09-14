import AppKit

// MARK: - 浮层窗口角色
//
// 层级（从低到高）：
//   主监控面板  `.popUpMenu`   — 菜单栏弹出，无系统动画干扰、可作为 key 响应快捷键
//   小游戏面板  `.floating`    — 可拖动、始终可成为 key
//   清屏覆盖层  `.screenSaver` — 全屏遮罩，独立 NSWindow（见 ScreenCleanController）

enum PanelWindowRole {
    case monitor
    case game

    /// 应用角色对应的窗口语义（层级、key 策略、拖动、动画行为）。
    func apply(to panel: FloatingPanel) {
        switch self {
        case .monitor:
            panel.level = .popUpMenu
            // 主监控面板由 CoreAnimation (NSAnimationContext) 接管高精度淡入淡出，
            // 禁用系统 utilityWindow 动画，避免双重动画冲突与多余图层合成开销。
            panel.animationBehavior = .none
            panel.becomesKeyOnlyIfNeeded = false
            panel.isMovableByWindowBackground = false
        case .game:
            panel.level = .floating
            panel.animationBehavior = .utilityWindow
            panel.isMovableByWindowBackground = true
            panel.becomesKeyOnlyIfNeeded = false
        }
    }
}

// MARK: - Floating Panel

/// 无边框、透明背景、可成为 key 的浮动面板。
/// 主监控面板与小游戏面板共用，差异化配置由 `PanelWindowRole` 负责。
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 便利初始化：基于角色和内容矩形一步完成配置，消除多阶段重复配置与属性遗漏。
    convenience init(role: PanelWindowRole, contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureCommonProperties()
        role.apply(to: self)
    }

    private func configureCommonProperties() {
        isFloatingPanel = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true
        contentView?.wantsLayer = true
    }
}

// MARK: - 状态栏几何计算辅助

enum StatusItemGeometry {
    @MainActor
    static func screenFrame(of button: NSStatusBarButton?) -> NSRect? {
        guard let button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
