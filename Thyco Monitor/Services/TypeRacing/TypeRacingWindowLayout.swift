import AppKit
import CoreGraphics

enum TypeRacingWindowLayout {
    static let width: CGFloat = 580

    static let skyStripHeight: CGFloat = 24
    static let playBandHeight: CGFloat = 96
    static var sceneHeight: CGFloat { skyStripHeight + playBandHeight }

    static let typingHeight: CGFloat = 112
    static let outerPadding: CGFloat = 8
    static let panelHeaderTopInset: CGFloat = 8
    static let panelHeaderHeight: CGFloat = 36

    static var contentHeight: CGFloat {
        panelHeaderHeight + sceneHeight + typingHeight + outerPadding
    }

    static var contentSize: CGSize {
        CGSize(width: width, height: contentHeight)
    }

    static var typingLaneWidth: CGFloat {
        width - outerPadding * 2
    }

    static let panelCornerRadius: CGFloat = 14
    /// 中央提示卡片圆角
    static let messageCardCornerRadius: CGFloat = 8

    /// 游戏主内容区左下、右下圆角（与面板外框协调）
    static let contentBottomCornerRadius: CGFloat = 8

    /// 与主监控面板之间的水平间距
    static let gapBesideMonitorPanel: CGFloat = 12

    static func centeredFrame(on screen: NSRect) -> NSRect {
        frame(size: contentSize, origin: CGPoint(
            x: screen.midX - contentSize.width / 2,
            y: screen.midY - contentSize.height / 2
        ))
    }

    /// 测速与小游戏共用：贴在主面板左侧；主面板还没有有效尺寸时居中。
    static func frame(beside monitorPanel: NSWindow?) -> NSRect {
        let screenFrame = (monitorPanel?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        guard let monitorPanel else {
            return centeredFrame(on: screenFrame)
        }

        let anchor = monitorPanel.frame
        guard anchor.width > 1, anchor.height > 1 else {
            return centeredFrame(on: screenFrame)
        }

        return frameToLeft(of: anchor, on: screenFrame)
    }

    /// 落在主 NSPanel 左侧，垂直与主面板居中对齐
    static func frameToLeft(of monitorPanelFrame: NSRect, on screen: NSRect) -> NSRect {
        let size = contentSize
        var originX = monitorPanelFrame.minX - size.width - gapBesideMonitorPanel
        var originY = monitorPanelFrame.midY - size.height / 2

        let margin: CGFloat = 8
        originX = max(screen.minX + margin, originX)
        originY = max(screen.minY + margin, min(originY, screen.maxY - size.height - margin))

        return frame(size: size, origin: CGPoint(x: originX, y: originY))
    }

    private static func frame(size: CGSize, origin: CGPoint) -> NSRect {
        NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}
