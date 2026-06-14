import AppKit
import SwiftUI

@MainActor
final class ScreenCleanController {
    var onDismiss: (() -> Void)?

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var overlayLanguage: AppLanguage = .chs

    var isActive: Bool { !windows.isEmpty }

    func setActive(_ active: Bool, language: AppLanguage = .chs) {
        overlayLanguage = language
        if active {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard windows.isEmpty else { return }

        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(
                rootView: ScreenCleanOverlayView(language: overlayLanguage) { [weak self] in
                    self?.dismiss()
                }
            )
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        windows.first?.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }
    }

    private func dismiss() {
        hide()
        onDismiss?()
    }

    private func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
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
        .onHover { isEscHovering = $0 }
    }
}
