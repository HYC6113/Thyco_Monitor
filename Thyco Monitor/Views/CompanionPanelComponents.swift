import AppKit
import SwiftUI

// MARK: - 伴随面板（小游戏、测速）共用组件

enum CompanionPanelSymbols {
    /// 顶栏「清除记录」按钮的图标；选用当前系统实际存在的 SF Symbol。
    static let clearData: String = {
        let candidates = ["broom", "broom.fill", "eraser.fill"]
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "trash"
    }()
}

/// 顶栏空白处的拖动区域。
struct PanelWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelWindowDragNSView {
        PanelWindowDragNSView()
    }

    func updateNSView(_ nsView: PanelWindowDragNSView, context: Context) {}
}

final class PanelWindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // borderless + nonactivatingPanel 上 performDrag 经常被 SwiftUI hosting view 吃掉，
        // 这里按屏幕坐标自己跟踪拖动。
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            if next.type == .leftMouseUp { break }
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(
                x: startOrigin.x + mouse.x - startMouse.x,
                y: startOrigin.y + mouse.y - startMouse.y
            ))
        }
    }
}
