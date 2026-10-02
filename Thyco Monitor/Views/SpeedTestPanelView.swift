import AppKit
import SwiftUI

/// 与 Type Racing 同尺寸的测速面板：左侧表盘，右侧当前网络身份。
struct SpeedTestPanelView: View {
    let language: AppLanguage
    let colorScheme: ColorScheme
    let model: SpeedTestModel
    let onClose: () -> Void

    @State private var isGaugeHovering = false
    @State private var isCloseHovering = false
    @State private var isRefreshHovering = false
    @State private var isClearHistoryHovering = false
    @State private var isIPAddressVisible = false
    @State private var isIPVisibilityHovering = false

    private var strings: MonitorStrings { MonitorStrings(language: language) }
    private var palette: MonitorPalette { .of(colorScheme) }

    private var downloadColor: Color {
        palette.batteryCharging
    }

    private var uploadColor: Color {
        colorScheme == .dark ? Color(hex: 0xBF5AF2) : Color(hex: 0xAF52DE)
    }

    private static let headerCapsuleHeight: CGFloat = 20
    private static let headerCapsuleStroke: CGFloat = 0.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelChrome

            VStack(spacing: 0) {
                header
                HStack(alignment: .top, spacing: TypeRacingWindowLayout.outerPadding) {
                    speedCard
                    identityCard
                }
                // 顶栏底边到两栏顶边，补上 Type Racing 追车屏幕相对内容区的 6pt 内缩，
                // 使胶囊底边到两栏顶边的距离与胶囊底边到屏幕顶边一致。
                .padding(.top, 6)
                .padding(.horizontal, TypeRacingWindowLayout.outerPadding)
                .padding(.bottom, TypeRacingWindowLayout.outerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: TypeRacingWindowLayout.width, height: TypeRacingWindowLayout.contentHeight)
        .clipShape(
            RoundedRectangle(
                cornerRadius: TypeRacingWindowLayout.panelCornerRadius,
                style: .continuous
            )
        )
        .preferredColorScheme(colorScheme)
    }

    /// 外框圆角与 Type Racing 相同：连续圆角 14。
    private var panelChrome: some View {
        let shape = RoundedRectangle(
            cornerRadius: TypeRacingWindowLayout.panelCornerRadius,
            style: .continuous
        )
        let panelBackground = colorScheme == .dark ? MonitorDarkPalette.panelBase : MonitorLightPalette.panelBase
        return shape
            .fill(.thinMaterial)
            .overlay(
                shape.fill(
                    panelBackground.opacity(
                        colorScheme == .dark
                            ? MonitorDarkPalette.panelOverlayOpacity
                            : MonitorLightPalette.panelOverlayOpacity
                    )
                )
            )
            .overlay(
                shape.fill(
                    colorScheme == .dark
                        ? Color.white.opacity(MonitorDarkPalette.panelSheenOpacity)
                        : Color.white.opacity(MonitorLightPalette.panelSheenOpacity)
                )
            )
            .overlay(
                shape.strokeBorder(
                    MonitorTheme.panelBorderGradient(for: colorScheme),
                    lineWidth: MonitorTheme.borderLineWidth
                )
            )
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            escCloseCapsule
            SpeedTestWindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            clearHistoryControl
            identityHeader
        }
        .padding(.top, TypeRacingWindowLayout.panelHeaderTopInset)
        .padding(.horizontal, 14)
        .frame(height: TypeRacingWindowLayout.panelHeaderHeight, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    /// 与 Type Racing 左上角 ESC 胶囊同一尺寸，颜色跟测速面板走。
    private var escCloseCapsule: some View {
        let tint = palette.primaryText
        return Button(action: onClose) {
            Text(strings.cleanModeExitKey)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(isCloseHovering ? 0.95 : 0.72))
                .frame(height: Self.headerCapsuleHeight)
                .padding(.horizontal, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isCloseHovering ? 0.14 : 0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            tint.opacity(isCloseHovering ? 0.45 : 0.28),
                            lineWidth: Self.headerCapsuleStroke
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(height: Self.headerCapsuleHeight)
        .contentShape(Capsule())
        .onHover { isCloseHovering = $0 }
        .accessibilityLabel(strings.speedTestClose)
    }

    /// 与 Type Racing 右上角清除胶囊同一形态：悬停时左侧浮出说明，颜色跟测速面板走。
    private var clearHistoryControl: some View {
        let tint = palette.primaryText
        return HStack(spacing: 6) {
            if isClearHistoryHovering {
                Text(strings.speedTestClearServerHistory)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity)
            }
            Button {
                model.clearServerHistory()
            } label: {
                Image(systemName: TypeRacingGameView.clearDataSymbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        tint.opacity(isClearHistoryHovering ? 0.95 : 0.72),
                        tint.opacity(isClearHistoryHovering ? 0.55 : 0.42)
                    )
                    .imageScale(.medium)
                    .frame(width: 28, height: Self.headerCapsuleHeight)
                    .background(
                        Capsule(style: .continuous)
                            .fill(tint.opacity(isClearHistoryHovering ? 0.14 : 0.08))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                tint.opacity(isClearHistoryHovering ? 0.45 : 0.28),
                                lineWidth: Self.headerCapsuleStroke
                            )
                    )
            }
            .buttonStyle(.plain)
            .frame(height: Self.headerCapsuleHeight)
            .contentShape(Capsule())
            .accessibilityLabel(strings.speedTestClearServerHistory)
        }
        .animation(.easeOut(duration: 0.15), value: isClearHistoryHovering)
        .onHover { isClearHistoryHovering = $0 }
    }

    // MARK: - 测速

    private var speedCard: some View {
        MonitorCard(colorScheme: colorScheme) {
            VStack(spacing: 0) {
                gauge
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: 8)
                statsRow
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gauge: some View {
        GeometryReader { geometry in
            let layout = min(geometry.size.width, geometry.size.height)
            let diameter = max(layout - 8, 0)
            ZStack {
                gaugeArc(diameter: diameter)
                gaugeScale(diameter: diameter)
                gaugeButton(diameter: diameter)
            }
            .frame(width: layout, height: layout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct GaugeMarkItem: Sendable {
        let text: String
        let cosRad: CGFloat
        let sinRad: CGFloat
        let extent: CGFloat
    }

    private static let anchorExtent: CGFloat = markRadialExtent("0", degrees: arcStart * 360 + 90)

    private static let scaleItems: [GaugeMarkItem] = {
        let marks = SpeedTestMath.gaugeMarks
        let steps = Double(marks.count - 1)
        return marks.enumerated().map { index, mark in
            let text = String(Int(mark))
            let fraction = Double(index) / steps
            let degrees = (arcStart + arcSpan * fraction) * 360 + 90
            let radians = degrees * .pi / 180
            return GaugeMarkItem(
                text: text,
                cosRad: cos(radians),
                sinRad: sin(radians),
                extent: markRadialExtent(text, degrees: degrees)
            )
        }
    }()

    /// 刻度数字放在进度弧内侧，文字保持正放。0 在左下起点，100 在右下终点。
    /// 以「0」的外缘为基准，较宽的数字往圆心收，避免右侧「100」贴到弧上。
    private func gaugeScale(diameter: CGFloat) -> some View {
        let anchorRadius = diameter / 2 - Self.arcLineWidth / 2 - 8
        let outerRadius = anchorRadius + Self.anchorExtent
        return ZStack {
            ForEach(Array(Self.scaleItems.enumerated()), id: \.offset) { _, item in
                let radius = outerRadius - item.extent
                Text(item.text)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .monospacedDigit()
                    .fixedSize()
                    .offset(x: item.cosRad * radius, y: item.sinRad * radius)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// 文字外接矩形沿半径朝外伸出的距离。宽数字在左右两侧会伸得更远。
    private static func markRadialExtent(_ text: String, degrees: Double) -> CGFloat {
        let base = NSFont.systemFont(ofSize: 8, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 8) } ?? base
        let size = (text as NSString).size(withAttributes: [.font: font])
        let radians = degrees * .pi / 180
        return size.width / 2 * abs(cos(radians)) + size.height / 2 * abs(sin(radians))
    }

    private func gaugeArc(diameter: CGFloat) -> some View {
        let lineWidth = Self.arcLineWidth
        return ZStack {
            Circle()
                .trim(from: Self.arcStart, to: Self.arcStart + Self.arcSpan)
                .stroke(
                    palette.cardBorder,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: Self.arcStart, to: Self.arcStart + Self.arcSpan * arcFraction)
                .stroke(
                    arcColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: arcColor.opacity(arcFraction > 0.02 ? 0.16 : 0), radius: 2, y: 0)
                .animation(.easeOut(duration: 0.25), value: arcFraction)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    /// 只有这块圆钮响应悬浮和点击。
    private func gaugeButton(diameter: CGFloat) -> some View {
        let side = max(diameter - Self.innerCircleInset * 2, 0)
        return Button {
            model.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(palette.controlBackground))
                    .overlay(Circle().fill(Color.primary.opacity(isGaugeHovering ? 0.05 : 0)))
                Circle()
                    .strokeBorder(palette.cardBorder, lineWidth: MonitorTheme.borderLineWidth)
                gaugeCenter
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isGaugeHovering = $0 }
        .accessibilityLabel(strings.speedTestTitle)
        .accessibilityValue(captionText)
    }

    private var gaugeCenter: some View {
        VStack(spacing: 1) {
            if showsConnectionSpinner {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else {
                Text(heroText)
                    .font(.system(size: heroIsNumeric ? 20 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(heroColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let unit = heroUnit {
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    /// 已开始、还没有延迟读数：选服和首包到达之前。下载、上传出速度前仍用三个点。
    private var showsConnectionSpinner: Bool {
        model.phase == .latency && model.livePing == nil
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(
                label: strings.speedTestPing,
                value: SpeedTestMath.formatMilliseconds(model.pingMilliseconds),
                unit: strings.speedTestUnitMs,
                valueColor: palette.primaryText
            )
            statCell(
                label: strings.speedTestJitter,
                value: SpeedTestMath.formatMilliseconds(model.jitterMilliseconds),
                unit: strings.speedTestUnitMs,
                valueColor: palette.primaryText
            )
            statCell(
                label: strings.speedTestDownload,
                value: downloadStat.value,
                unit: downloadStat.unit,
                valueColor: downloadStatColor
            )
            statCell(
                label: strings.speedTestUpload,
                value: uploadStat.value,
                unit: uploadStat.unit,
                valueColor: uploadStatColor
            )
        }
        .frame(height: 46)
    }

    private func statCell(label: String, value: String, unit: String, valueColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 网络身份

    private var identityCard: some View {
        MonitorCard(colorScheme: colorScheme) {
            identityBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identityHeader: some View {
        let tint = palette.primaryText
        return Button {
            model.loadIdentity()
        } label: {
            HStack(spacing: 4) {
                Text(strings.ipInfoTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Group {
                    if model.isRefreshingIdentity {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .frame(width: 12, height: 12)
            }
            .foregroundStyle(tint.opacity(isRefreshHovering ? 0.95 : 0.72))
            .frame(height: Self.headerCapsuleHeight)
            .padding(.horizontal, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(isRefreshHovering ? 0.14 : 0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        tint.opacity(isRefreshHovering ? 0.45 : 0.28),
                        lineWidth: Self.headerCapsuleStroke
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshingIdentity)
        .frame(height: Self.headerCapsuleHeight)
        .contentShape(Capsule())
        .onHover { isRefreshHovering = $0 }
        .accessibilityLabel(strings.ipRefresh)
    }

    @ViewBuilder
    private var identityBody: some View {
        if let info = model.info {
            let rows = infoRows(info)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    identityRow(row, showsDivider: index < rows.count - 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.identityState == .failed {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(strings.ipUnavailable)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Button(strings.ipRefresh) {
                    model.loadIdentity()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                ProgressView()
                    .controlSize(.small)
                Text(strings.ipLoading)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func identityRow(_ row: IdentityRow, showsDivider: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(row.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 48, alignment: .leading)
            Text(row.value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if row.canReveal {
                Button {
                    isIPAddressVisible.toggle()
                } label: {
                    Image(systemName: isIPAddressVisible ? "eye.slash" : "eye")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText.opacity(isIPVisibilityHovering ? 1 : 0.72))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isIPVisibilityHovering = $0 }
                .accessibilityLabel(isIPAddressVisible ? strings.ipHide : strings.ipShow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(palette.cardBorder)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - 文案

    private var heroText: String {
        switch model.phase {
        case .latency:
            if let livePing = model.livePing {
                return SpeedTestMath.formatMilliseconds(livePing)
            }
            return "…"
        case .download, .upload:
            return liveSpeedText.value
        case .failed:
            return failureText
        case .idle, .finished:
            return strings.speedTestStart
        }
    }

    private var heroIsNumeric: Bool {
        switch model.phase {
        case .download, .upload: true
        case .latency: model.livePing != nil
        case .idle, .finished, .failed: false
        }
    }

    private var heroColor: Color {
        switch model.phase {
        case .download:
            return downloadColor
        case .upload:
            return uploadColor
        default:
            return palette.primaryText
        }
    }

    private var heroUnit: String? {
        switch model.phase {
        case .latency where model.livePing != nil:
            return strings.speedTestUnitMs
        case .download, .upload:
            guard model.hasLiveSpeedSample else { return nil }
            return liveSpeedText.unit
        default:
            return nil
        }
    }

    private var captionText: String {
        if isGaugeHovering, model.isRunning {
            return strings.speedTestTapToStop
        }
        switch model.phase {
        case .idle:
            return strings.speedTestHint
        case .latency:
            return strings.speedTestPhaseLatency
        case .download:
            return strings.speedTestPhaseDownload
        case .upload:
            return strings.speedTestPhaseUpload
        case .finished:
            return strings.speedTestPhaseDone
        case .failed:
            return failureText
        }
    }

    private var failureText: String {
        switch model.failureReason {
        case .offline:
            return strings.speedTestOffline
        case .timedOut:
            return strings.speedTestTimeout
        case .generic, .none:
            return strings.speedTestGenericError
        }
    }

    private var arcFraction: Double {
        switch model.phase {
        case .download, .upload:
            return SpeedTestMath.gaugeFraction(megabits: model.gaugeMegabits)
        case .idle, .latency, .finished, .failed:
            return 0
        }
    }

    private var arcColor: Color {
        model.phase == .upload ? uploadColor : downloadColor
    }

    private var downloadStat: (value: String, unit: String) {
        if model.phase == .download {
            return liveSpeedText
        }
        return SpeedTestMath.formatByteRate(megabits: model.downloadMegabits)
    }

    private var uploadStat: (value: String, unit: String) {
        if model.phase == .upload {
            return liveSpeedText
        }
        return SpeedTestMath.formatByteRate(megabits: model.uploadMegabits)
    }

    private var liveSpeedText: (value: String, unit: String) {
        guard model.hasLiveSpeedSample else { return ("…", "MB/s") }
        return SpeedTestMath.formatByteRate(megabits: model.gaugeMegabits)
    }

    private var downloadStatColor: Color {
        switch model.phase {
        case .download, .finished: downloadColor
        default: palette.primaryText
        }
    }

    private var uploadStatColor: Color {
        switch model.phase {
        case .upload, .finished: uploadColor
        default: palette.primaryText
        }
    }

    private func infoRows(_ info: PublicNetworkInfo) -> [IdentityRow] {
        [
            IdentityRow(
                label: strings.ipAddressLabel,
                value: ipAddressText(info.ip),
                canReveal: !display(info.ip).isEmpty && display(info.ip) != "—"
            ),
            IdentityRow(label: strings.ipCountryLabel, value: countryText(info)),
            IdentityRow(label: strings.ipLocationLabel, value: locationText(info)),
            IdentityRow(label: strings.ipTimezoneLabel, value: timezoneText(info)),
            IdentityRow(label: strings.ipISPLabel, value: ispText(info)),
            IdentityRow(label: strings.ipNodeLabel, value: nodeText(info))
        ]
    }

    /// 测过速后显示实际连接的 Ookla 节点；此前只有 Cloudflare 接入点可显示。
    private func nodeText(_ info: PublicNetworkInfo) -> String {
        if let label = model.server?.label, !label.isEmpty { return label }
        return display(info.colo)
    }

    private func countryText(_ info: PublicNetworkInfo) -> String {
        let code = info.countryCode
        let chinese = code.flatMap { Locale(identifier: "zh-Hans").localizedString(forRegionCode: $0) }
        let english = code.flatMap { Locale(identifier: "en").localizedString(forRegionCode: $0) }
        if language == .chs, let chinese, !chinese.isEmpty {
            if let english, !english.isEmpty,
               english.caseInsensitiveCompare(chinese) != .orderedSame {
                return "\(chinese) \(english)"
            }
            return chinese
        }
        if let english, !english.isEmpty { return english }
        return display(info.countryName)
    }

    /// 中文界面下大陆 IP 优先用国内 IP 库的中文城市。
    private func locationText(_ info: PublicNetworkInfo) -> String {
        let candidates = if language == .chs, let chinese = info.chinese, chinese.city != nil {
            [chinese.city, chinese.province]
        } else {
            [info.city, info.region]
        }
        var parts: [String] = []
        for part in candidates {
            guard let part, !part.isEmpty else { continue }
            if parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) { continue }
            parts.append(part)
        }
        if !parts.isEmpty {
            return parts.joined(separator: language == .chs ? " · " : ", ")
        }
        if let latitude = info.latitude, let longitude = info.longitude {
            return String(format: "%.2f, %.2f", latitude, longitude)
        }
        return "—"
    }

    private func timezoneText(_ info: PublicNetworkInfo) -> String {
        guard let identifier = info.timeZoneID, let zone = TimeZone(identifier: identifier) else {
            return "—"
        }
        let locale = Locale(identifier: language == .chs ? "zh-Hans" : "en")
        let style: TimeZone.NameStyle = zone.isDaylightSavingTime() ? .daylightSaving : .standard
        let name = zone.localizedName(for: style, locale: locale) ?? identifier
        let seconds = zone.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        let utc = minutes == 0
            ? "UTC\(sign)\(hours)"
            : String(format: "UTC%@%d:%02d", sign, hours, minutes)
        return "\(name) · \(utc)"
    }

    private func ispText(_ info: PublicNetworkInfo) -> String {
        if language == .chs, let isp = info.chinese?.isp { return isp }
        if let isp = info.isp, !isp.isEmpty { return isp }
        guard let asn = info.asn, !asn.isEmpty else { return "—" }
        return asn.hasPrefix("AS") ? asn : "AS\(asn)"
    }

    private func ipAddressText(_ ip: String) -> String {
        let shown = display(ip)
        if shown == "—" || isIPAddressVisible { return shown }
        return "••••••••"
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }

    private static let arcStart = 0.12
    private static let arcSpan = 0.76
    private static let arcLineWidth: CGFloat = 5
    /// 中间圆钮相对表盘内收，给内侧刻度留出一圈空隙。
    private static let innerCircleInset: CGFloat = 28
}

private struct IdentityRow {
    let label: String
    let value: String
    var canReveal = false
}

// MARK: - 拖动标题栏

private struct SpeedTestWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> SpeedTestWindowDragNSView {
        SpeedTestWindowDragNSView()
    }

    func updateNSView(_ nsView: SpeedTestWindowDragNSView, context: Context) {}
}

private final class SpeedTestWindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
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

#Preview("Speed Test") {
    let model = SpeedTestModel()
    model.applyPreviewFixture()
    return SpeedTestPanelView(language: .chs, colorScheme: .dark, model: model, onClose: {})
}
