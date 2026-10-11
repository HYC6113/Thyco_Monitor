import SwiftUI

/// 面板静态铬层：毛玻璃 + 实色叠层 + sheen + 描边。主监控面板与测速面板共用，仅外形不同。
/// 独立 View 只依赖 `colorScheme`，避免指标每秒刷新时重建材质栈。
struct PanelChromeBackground<S: InsettableShape>: View {
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        shape
            .fill(.thinMaterial)
            .overlay(
                shape
                    .fill(
                        panelBackground.opacity(
                            colorScheme == .dark
                                ? MonitorDarkPalette.panelOverlayOpacity
                                : MonitorLightPalette.panelOverlayOpacity
                        )
                    )
            )
            .overlay(
                shape
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(MonitorDarkPalette.panelSheenOpacity)
                            : Color.white.opacity(MonitorLightPalette.panelSheenOpacity)
                    )
            )
            .overlay(
                shape
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

extension PanelChromeBackground where S == RoundedRectangle {
    init() {
        self.init(shape: MonitorTheme.panelShape)
    }
}
