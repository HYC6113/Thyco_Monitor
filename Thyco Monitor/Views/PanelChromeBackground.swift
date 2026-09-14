import SwiftUI

/// 面板静态铬层：毛玻璃 + 实色叠层 + sheen + 描边。
/// 独立 View 只依赖 `colorScheme`，避免指标每秒刷新时重建材质栈。
struct PanelChromeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MonitorTheme.panelShape
            .fill(.thinMaterial)
            .overlay(
                MonitorTheme.panelShape
                    .fill(
                        panelBackground.opacity(
                            colorScheme == .dark
                                ? MonitorDarkPalette.panelOverlayOpacity
                                : MonitorLightPalette.panelOverlayOpacity
                        )
                    )
            )
            .overlay(
                MonitorTheme.panelShape
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(MonitorDarkPalette.panelSheenOpacity)
                            : Color.white.opacity(MonitorLightPalette.panelSheenOpacity)
                    )
            )
            .overlay(
                MonitorTheme.panelShape
                    .strokeBorder(
                        MonitorTheme.panelBorderGradient(for: colorScheme),
                        lineWidth: MonitorTheme.borderLineWidth
                    )
            )
            .ignoresSafeArea()
    }

    private var panelBackground: Color {
        colorScheme == .dark ? MonitorDarkPalette.panelBase : MonitorLightPalette.panelBase
    }
}
