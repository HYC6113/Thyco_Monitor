import CoreGraphics
import SwiftUI

/// 「凹」字形闭环外框（外框矩形 + 顶部中央内凹缺口），拐角圆角
struct TypeRacingCircuitTrack {
    let trackRect: CGRect
    let cornerRadius: CGFloat
    let points: [CGPoint]
    private let segmentLengths: [CGFloat]
    let totalLength: CGFloat

    let trackPath: Path

    /// 右侧预留给里程 HUD 的宽度
    static let hudReserveWidth: CGFloat = 92

    private static let sampleCount = 140
    private static let pathFlatness: CGFloat = 0.35

    init(size: CGSize) {
        let rect = Self.layoutRect(in: size)
        trackRect = rect
        cornerRadius = min(rect.width, rect.height) * 0.07

        let corners = Self.normalizedOutline().map { point in
            CGPoint(
                x: rect.minX + point.x * rect.width,
                y: rect.minY + point.y * rect.height
            )
        }

        let path = Self.roundedPath(corners: corners, radius: cornerRadius)
        self.trackPath = path
        points = Self.equidistantSamples(along: path, count: Self.sampleCount)

        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        let count = points.count
        for index in 0..<count {
            let next = points[(index + 1) % count]
            let segment = hypot(next.x - points[index].x, next.y - points[index].y)
            total += segment
            lengths.append(segment)
        }
        segmentLengths = lengths
        totalLength = total
    }

    func point(at phase: CGFloat) -> CGPoint {
        guard totalLength > 0, !points.isEmpty else { return .zero }

        var distance = phase.truncatingRemainder(dividingBy: 1) * totalLength
        if distance < 0 { distance += totalLength }

        let count = points.count
        for index in 0..<count {
            let segment = segmentLengths[index]
            if distance > segment {
                distance -= segment
                continue
            }

            let nextIndex = (index + 1) % count
            let start = points[index]
            let end = points[nextIndex]
            let t = segment > 0 ? distance / segment : 0
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
        return points[0]
    }

    // MARK: - 凹字形

    private static func normalizedOutline() -> [CGPoint] {
        let notchLeft: CGFloat = 0.30
        let notchRight: CGFloat = 0.70
        let notchDepth: CGFloat = 0.40

        // 顺时针：左上 → 缺口左缘 → 缺口底 → 缺口右缘 → 右上 → 右下 → 左下
        return [
            CGPoint(x: 0, y: 0),
            CGPoint(x: notchLeft, y: 0),
            CGPoint(x: notchLeft, y: notchDepth),
            CGPoint(x: notchRight, y: notchDepth),
            CGPoint(x: notchRight, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
    }

    private static func layoutRect(in size: CGSize) -> CGRect {
        let insetTop: CGFloat = 12
        let insetLeft = insetTop
        let insetBottom = insetTop
        return CGRect(
            x: insetLeft,
            y: insetTop,
            width: max(100, size.width - insetLeft - hudReserveWidth),
            height: max(72, size.height - insetTop - insetBottom)
        )
    }

    // MARK: - 圆角路径

    private static func roundedPath(corners: [CGPoint], radius: CGFloat) -> Path {
        guard corners.count >= 3 else { return Path() }

        let count = corners.count
        let start = filletEntryPoint(
            prev: corners[count - 1],
            corner: corners[0],
            next: corners[1],
            radius: radius
        )

        var path = Path()
        path.move(to: start)
        for index in 0..<count {
            path.addArc(
                tangent1End: corners[index],
                tangent2End: corners[(index + 1) % count],
                radius: radius
            )
        }
        // 补最后一条直边（如左侧竖边）；勿用 closeSubpath()，否则会连回尖角顶点产生突线
        path.addLine(to: start)
        return path
    }

    /// 圆角弧在「进入角点」的切线起点（落在邻边上，而非尖角顶点）
    private static func filletEntryPoint(
        prev: CGPoint,
        corner: CGPoint,
        next: CGPoint,
        radius: CGFloat
    ) -> CGPoint {
        let v1x = corner.x - prev.x
        let v1y = corner.y - prev.y
        let len1 = hypot(v1x, v1y)
        guard len1 > 0.001 else { return corner }

        let r = min(radius, len1 * 0.48)
        return CGPoint(x: corner.x - v1x / len1 * r, y: corner.y - v1y / len1 * r)
    }

    /// 沿 `roundedPath` 等距取点，与描边圆角完全一致（含缺口内凹角）
    private static func equidistantSamples(along path: Path, count: Int) -> [CGPoint] {
        let polyline = flattenToPolyline(path.cgPath, flatness: pathFlatness)
        return resampleOutline(polyline, count: count)
    }

    private static func flattenToPolyline(_ cgPath: CGPath, flatness: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        cgPath.applyWithBlock { element in
            let type = element.pointee.type
            let elementPoints = element.pointee.points

            switch type {
            case .moveToPoint:
                current = elementPoints[0]
                subpathStart = current
                points.append(current)
            case .addLineToPoint:
                current = elementPoints[0]
                points.append(current)
            case .addQuadCurveToPoint:
                let control = elementPoints[0]
                let end = elementPoints[1]
                points.append(contentsOf: flattenQuadratic(
                    from: current,
                    control: control,
                    to: end,
                    flatness: flatness
                ))
                current = end
            case .addCurveToPoint:
                let control1 = elementPoints[0]
                let control2 = elementPoints[1]
                let end = elementPoints[2]
                points.append(contentsOf: flattenCubic(
                    from: current,
                    control1: control1,
                    control2: control2,
                    to: end,
                    flatness: flatness
                ))
                current = end
            case .closeSubpath:
                if hypot(current.x - subpathStart.x, current.y - subpathStart.y) > 0.001 {
                    points.append(subpathStart)
                    current = subpathStart
                }
            @unknown default:
                break
            }
        }

        return points
    }

    private static func flattenQuadratic(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        flatness: CGFloat,
        depth: Int = 0
    ) -> [CGPoint] {
        if depth > 10 {
            return [end]
        }

        let deviation = distancePointToSegment(control, start: start, end: end)
        if deviation <= flatness {
            return [end]
        }

        let startControl = midpoint(start, control)
        let controlEnd = midpoint(control, end)
        let mid = midpoint(startControl, controlEnd)

        return flattenQuadratic(from: start, control: startControl, to: mid, flatness: flatness, depth: depth + 1)
            + flattenQuadratic(from: mid, control: controlEnd, to: end, flatness: flatness, depth: depth + 1)
    }

    private static func flattenCubic(
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint,
        flatness: CGFloat,
        depth: Int = 0
    ) -> [CGPoint] {
        if depth > 10 {
            return [end]
        }

        let d1 = distancePointToSegment(control1, start: start, end: end)
        let d2 = distancePointToSegment(control2, start: start, end: end)
        if d1 + d2 <= flatness {
            return [end]
        }

        let startC1 = midpoint(start, control1)
        let c1c2 = midpoint(control1, control2)
        let c2End = midpoint(control2, end)
        let midA = midpoint(startC1, c1c2)
        let midB = midpoint(c1c2, c2End)
        let mid = midpoint(midA, midB)

        return flattenCubic(from: start, control1: startC1, control2: midA, to: mid, flatness: flatness, depth: depth + 1)
            + flattenCubic(from: mid, control1: midB, control2: c2End, to: end, flatness: flatness, depth: depth + 1)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    private static func distancePointToSegment(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projectionX = start.x + dx * t
        let projectionY = start.y + dy * t
        return hypot(point.x - projectionX, point.y - projectionY)
    }

    private static func resampleOutline(_ outline: [CGPoint], count: Int) -> [CGPoint] {
        guard outline.count >= 2, count > 0 else { return outline }

        var segmentLengths: [CGFloat] = []
        var total: CGFloat = 0
        for index in 0..<outline.count {
            let next = outline[(index + 1) % outline.count]
            let length = hypot(next.x - outline[index].x, next.y - outline[index].y)
            segmentLengths.append(length)
            total += length
        }

        guard total > 0 else { return outline }

        return (0..<count).map { sample in
            var target = (CGFloat(sample) / CGFloat(count)) * total
            for index in 0..<outline.count {
                let length = segmentLengths[index]
                if target > length {
                    target -= length
                    continue
                }
                let next = outline[(index + 1) % outline.count]
                let start = outline[index]
                let t = length > 0 ? target / length : 0
                return CGPoint(
                    x: start.x + (next.x - start.x) * t,
                    y: start.y + (next.y - start.y) * t
                )
            }
            return outline[0]
        }
    }
}
