import AppKit
import SwiftUI

@MainActor
final class ScreenCleanController {
    var onDismiss: (() -> Void)?

    private var windows: [ScreenCleanWindow] = []
    private var focusObservers: [NSObjectProtocol] = []
    private var preferredKeyWindow: ScreenCleanWindow?
    private var didRaiseActivationPolicy = false
    private var isReclaimingFocus = false
    private(set) var isActive = false
    private var overlayLanguage: AppLanguage = .chs

    func setActive(_ active: Bool, language: AppLanguage = .chs) {
        overlayLanguage = language
        if active {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard !isActive else { return }
        isActive = true

        for screen in NSScreen.screens {
            let window = ScreenCleanWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            // stationary 会让窗口像桌面一样不参与当前空间的 key window，切换桌面后按键进不来。
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let hostingView = NSHostingView(
                rootView: ScreenCleanOverlayView(language: overlayLanguage) { [weak self] in
                    self?.dismiss()
                }
            )
            // 空的 sizingOptions 避免 SwiftUI 按内容理想尺寸把全屏遮罩缩成一小块。
            hostingView.sizingOptions = []
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentView = hostingView
            window.setFrame(screen.frame, display: true)
            windows.append(window)
        }

        orderWindowsFront()
        // 菜单栏应用不属于任何一个桌面。切换桌面时系统会把键盘交给那边的前台应用，
        // 后台应用再调用 activate 也会被忽略，所以 ESC 要等到用户点击才恢复。
        // 遮罩先盖住屏幕，再临时成为普通前台应用，才能在各个桌面上保住键盘焦点。
        beginForegroundSession()
        orderWindowsFront()
        // 窗口盖住屏幕之后再吞键盘。在 sendEvent 入口截住，系统才不会把按键当成未处理并播放提示音。
        CleanModeKeyboardSilencer.shared.start { [weak self] in
            self?.dismiss()
        }
        installFocusGuard()
    }

    private func dismiss() {
        guard isActive else { return }
        hide()
        onDismiss?()
    }

    private func hide() {
        guard isActive else { return }
        isActive = false

        CleanModeKeyboardSilencer.shared.stop()
        removeFocusGuard()
        preferredKeyWindow = nil

        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows.removeAll()
        endForegroundSession()
    }

    private func beginForegroundSession() {
        if NSApp.activationPolicy() != .regular {
            didRaiseActivationPolicy = NSApp.setActivationPolicy(.regular)
        }
        activateOverFrontmostApp()
    }

    /// macOS 14 的 `NSApp.activate()` 不会从当前桌面的前台应用手里把键盘要回来。
    /// `activate(ignoringOtherApps:)` 在当前 SDK 中仍可用（仅标记为未来弃用），继续用它保持既有焦点行为。
    private func activateOverFrontmostApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func endForegroundSession() {
        guard didRaiseActivationPolicy else { return }
        didRaiseActivationPolicy = false
        NSApp.setActivationPolicy(.accessory)
    }

    /// 把鼠标所在屏幕的遮罩放到最前并设为 key，其余屏幕保持覆盖。
    private func orderWindowsFront() {
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        preferredKeyWindow = keyWindow
        for window in windows where window !== keyWindow {
            window.orderFrontRegardless()
        }
        keyWindow?.orderFrontRegardless()
        keyWindow?.makeKey()
        keyWindow?.makeMain()
    }

    /// 切换桌面不一定会让应用失活，但一定会让当前 key window 失效。两种情况都要抢回。
    private func installFocusGuard() {
        removeFocusGuard()
        let reclaim: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reclaimKeyboardFocus()
            }
        }
        focusObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main,
                using: reclaim
            )
        )
        focusObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
                using: reclaim
            )
        )
        focusObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let window = notification.object as? NSWindow else { return }
                    guard window === self.preferredKeyWindow else { return }
                    self.reclaimKeyboardFocus()
                }
            }
        )
        focusObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main,
                using: reclaim
            )
        )
    }

    private func removeFocusGuard() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
            workspaceCenter.removeObserver(observer)
        }
        focusObservers.removeAll()
    }

    private func reclaimKeyboardFocus() {
        guard isActive, !isReclaimingFocus else { return }
        isReclaimingFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isReclaimingFocus = false }
            guard self.isActive else { return }
            if !NSApp.isActive || self.preferredKeyWindow?.isKeyWindow != true {
                self.activateOverFrontmostApp()
                self.orderWindowsFront()
            }
        }
    }
}

/// 在 NSApplication 收到键盘事件时直接丢掉。
/// 本地监视器返回 nil，或把按键交回响应链，都会被系统当成未处理并播放提示音。
/// 方法交换只安装一次；清洁模式关闭时 `isEnabled` 为 false，事件原样转发。
private final class CleanModeKeyboardSilencer {
    static let shared = CleanModeKeyboardSilencer()

    private var onEscape: (() -> Void)?
    private var installed = false
    private(set) var isEnabled = false

    func start(onEscape: @escaping () -> Void) {
        guard installIfNeeded() else { return }
        self.onEscape = onEscape
        isEnabled = true
    }

    func stop() {
        isEnabled = false
        onEscape = nil
    }

    fileprivate func handleEscape() {
        let escape = onEscape
        DispatchQueue.main.async {
            escape?()
        }
    }

    private func installIfNeeded() -> Bool {
        if installed { return true }
        let applicationClass: AnyClass = type(of: NSApp)
        let original = #selector(NSApplication.sendEvent(_:))
        let swizzled = #selector(NSApplication.thycoCleanMode_sendEvent(_:))
        guard let originalMethod = class_getInstanceMethod(applicationClass, original),
              let swizzledMethod = class_getInstanceMethod(NSApplication.self, swizzled) else {
            return false
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
        installed = true
        return true
    }
}

extension NSApplication {
    @objc fileprivate func thycoCleanMode_sendEvent(_ event: NSEvent) {
        let silencer = CleanModeKeyboardSilencer.shared
        if silencer.isEnabled {
            switch event.type {
            case .keyDown, .keyUp, .flagsChanged:
                if event.type == .keyDown, event.keyCode == 53 {
                    silencer.handleEscape()
                }
                return
            default:
                break
            }
        }
        thycoCleanMode_sendEvent(event)
    }
}

/// 可成为 key 的全屏遮罩。普通无边框窗口默认不能取得键盘焦点。
/// 不使用 NSPanel：面板会把窗口限制在菜单栏和程序坞之内，盖不住整块屏幕。
private final class ScreenCleanWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private struct ScreenCleanOverlayView: View {
    let language: AppLanguage
    let onDismiss: () -> Void

    @State private var isEscHovering = false

    private var strings: MonitorStrings {
        MonitorStrings(language: language)
    }

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 18) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 64, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white.opacity(0.52))

                HStack(alignment: .center, spacing: 6) {
                    Text(strings.cleanModeExitPrefix)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                    escCapsuleButton
                    Text(strings.cleanModeExitSuffix)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var escCapsuleButton: some View {
        Button(action: onDismiss) {
            Text(strings.cleanModeExitKey)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(isEscHovering ? 0.72 : 0.52))
                .frame(width: 44, height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isEscHovering ? 0.14 : 0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isEscHovering ? 0.38 : 0.24), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isEscHovering = $0 }
    }
}
