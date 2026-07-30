import CoreText
import HoursCore
import SwiftUI
import UIKit

struct ProceduralHourWheelView: View, Animatable {
    var rotationDegrees: Double
    var selectedHour: OfficeHour

    @Environment(\.colorScheme) private var colorScheme

    init(
        rotationDegrees: Double,
        selectedHour: OfficeHour? = nil
    ) {
        self.rotationDegrees = rotationDegrees
        self.selectedHour = selectedHour
            ?? HourDialMath.nearestHour(for: rotationDegrees)
    }

    var animatableData: Double {
        get { rotationDegrees }
        set { rotationDegrees = newValue }
    }

    var body: some View {
        let appearance = HourWheelAppearance(colorScheme: colorScheme)

        HourWheelDrawingView(
            rotationDegrees: rotationDegrees,
            selectedHour: selectedHour,
            appearance: appearance,
            fillBlend: appearance.fillBlend
        )
        .animation(
            .easeInOut(duration: HourWheelAppearanceTransition.duration),
            value: appearance
        )
    }
}

private struct HourWheelDrawingView: View, Animatable {
    var rotationDegrees: Double
    var selectedHour: OfficeHour
    var appearance: HourWheelAppearance
    var fillBlend: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotationDegrees, fillBlend) }
        set {
            rotationDegrees = newValue.first
            fillBlend = newValue.second
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if HourWheelGeometry.canRender(size: geometry.size) {
                HourWheelUIKitView(
                    selectedHour: selectedHour,
                    appearance: appearance,
                    fillBlend: fillBlend
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            }
        }
        .rotationEffect(.degrees(rotationDegrees))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HourWheelUIKitView: UIViewRepresentable {
    let selectedHour: OfficeHour
    let appearance: HourWheelAppearance
    let fillBlend: Double

    func makeUIView(context: Context) -> HourWheelUIView {
        HourWheelUIView()
    }

    func updateUIView(
        _ uiView: HourWheelUIView,
        context: Context
    ) {
        uiView.update(
            selectedHour: selectedHour,
            appearance: appearance,
            fillBlend: fillBlend
        )
    }
}

private final class HourWheelUIView: UIView {
    private var selectedHour = OfficeHour.matins
    private var appearance = HourWheelAppearance.light
    private var fillBlend = 0.0

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(
        selectedHour: OfficeHour,
        appearance: HourWheelAppearance,
        fillBlend: Double
    ) {
        guard self.selectedHour != selectedHour
                || self.appearance != appearance
                || self.fillBlend != fillBlend else {
            return
        }

        self.selectedHour = selectedHour
        self.appearance = appearance
        self.fillBlend = fillBlend
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard HourWheelGeometry.canRender(size: bounds.size),
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        HourWheelCoreGraphicsRenderer.draw(
            in: context,
            size: bounds.size,
            selectedHour: selectedHour,
            appearance: appearance,
            fillBlend: fillBlend
        )
    }
}

enum HourWheelAppearance: Hashable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var fillBlend: Double {
        self == .dark ? 1 : 0
    }
}

struct HourWheelPalette: Equatable {
    let foreground: SIMD3<Float>
    let mutedBorder: SIMD3<Float>
    let timeRingFill: SIMD3<Float>
    let timeRingNumeral: SIMD3<Float>
    let selectedLabel: SIMD3<Float>

    var jerusalemCrossFill: SIMD3<Float> {
        timeRingFill
    }

    var jerusalemCrossForeground: SIMD3<Float> {
        timeRingNumeral
    }

    static func colors(for appearance: HourWheelAppearance) -> Self {
        switch appearance {
        case .light:
            Self(
                foreground: SIMD3<Float>(repeating: 0.06),
                mutedBorder: SIMD3<Float>(repeating: 0.42),
                timeRingFill: SIMD3<Float>(repeating: 0.06),
                timeRingNumeral: SIMD3<Float>(repeating: 0.92),
                selectedLabel: SIMD3<Float>(0.68, 0.12, 0.09)
            )
        case .dark:
            Self(
                foreground: SIMD3<Float>(repeating: 0.92),
                mutedBorder: SIMD3<Float>(repeating: 0.58),
                timeRingFill: SIMD3<Float>(repeating: 0.04),
                timeRingNumeral: SIMD3<Float>(repeating: 0.92),
                selectedLabel: SIMD3<Float>(0.68, 0.12, 0.09)
            )
        }
    }

    static func interpolatedTimeRingFill(
        at blend: Double
    ) -> SIMD3<Float> {
        let progress = Float(min(max(blend, 0), 1))
        let light = colors(for: .light).timeRingFill
        let dark = colors(for: .dark).timeRingFill
        return light + (dark - light) * progress
    }
}

enum HourWheelAppearanceTransition {
    static let duration: TimeInterval = 0.72
}

enum HourWheelTimePeriod: String, Equatable {
    case daylight
    case night
}

struct HourWheelTimeMarker: Equatable {
    let period: HourWheelTimePeriod
    let numeral: String
    let dialAngle: Double
}

struct HourWheelTextureLayout: Equatable {
    let width: Float
    let height: Float
    let centerY: Float
}

enum HourWheelGeometry {
    static let wheelRadius: Float = 0.5
    static let timeRingInnerRadius: Float = 0.458
    static let labelRadius: Float = 0.520
    static let texturedSectorOuterRadius: Float = timeRingInnerRadius
    static let numeralRadius: Float = 0.476
    static let centerBorderRadius: Float = 0.086
    static let centerOutlineWidth: Float = 0.002
    static let centerOpeningRadius: Float =
        centerBorderRadius - centerOutlineWidth
    static let textureDividerWidth: Float = 0.003
    static let canvasArtworkExtent: CGFloat = 0.555

    static func canRender(size: CGSize) -> Bool {
        size.width >= 1
            && size.height >= 1
            && size.width.isFinite
            && size.height.isFinite
    }

    static let ancientTimeMarkers: [HourWheelTimeMarker] = [
        HourWheelTimeMarker(
            period: .night, numeral: "VII", dialAngle: 7.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "VIII", dialAngle: 22.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "IX", dialAngle: 37.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "X", dialAngle: 52.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "XI", dialAngle: 67.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "XII", dialAngle: 82.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "I", dialAngle: 97.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "II", dialAngle: 112.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "III", dialAngle: 127.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "IV", dialAngle: 142.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "V", dialAngle: 157.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "VI", dialAngle: 172.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "VII", dialAngle: 187.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "VIII", dialAngle: 202.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "IX", dialAngle: 217.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "X", dialAngle: 232.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "XI", dialAngle: 247.5
        ),
        HourWheelTimeMarker(
            period: .daylight, numeral: "XII", dialAngle: 262.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "I", dialAngle: 277.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "II", dialAngle: 292.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "III", dialAngle: 307.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "IV", dialAngle: 322.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "V", dialAngle: 337.5
        ),
        HourWheelTimeMarker(
            period: .night, numeral: "VI", dialAngle: 352.5
        ),
    ]

    static func worldAngle(forDialDegrees degrees: Double) -> Float {
        Float(.pi / 2 - degrees * .pi / 180)
    }

    static func worldRotationRadians(
        forDisplayedDegrees degrees: Double
    ) -> Float {
        Float(-degrees * .pi / 180)
    }

    static func worldSectorAngles(
        for hour: OfficeHour
    ) -> ClosedRange<Float> {
        let dialRange = HourDialMath.sectorAngleRange(for: hour)
        let lower = worldAngle(
            forDialDegrees: dialRange.upperBound
        )
        let upper = worldAngle(
            forDialDegrees: dialRange.lowerBound
        )
        return lower...upper
    }

    static var textureDividerAngles: [Float] {
        HourDialMath.sectors.map {
            worldSectorAngles(for: $0.hour).lowerBound
        }
    }

    static func position(
        for hour: OfficeHour,
        radius: Float
    ) -> SIMD2<Float> {
        position(
            forDialAngle: HourDialMath.labelAngle(for: hour),
            radius: radius
        )
    }

    static func position(
        forDialAngle dialAngle: Double,
        radius: Float
    ) -> SIMD2<Float> {
        let angle = Float(dialAngle * .pi / 180)
        return SIMD2<Float>(
            radius * sin(angle),
            radius * cos(angle)
        )
    }

    static func selectedRotationRadians(
        for hour: OfficeHour
    ) -> Float {
        worldRotationRadians(
            forDisplayedDegrees: HourDialMath.targetRotation(
                for: hour,
                near: 0
            )
        )
    }

    static func textureLayout(
        for hour: OfficeHour,
        textureAspectRatio: Float = 1
    ) -> HourWheelTextureLayout {
        precondition(textureAspectRatio > 0)
        let angleRange = worldSectorAngles(for: hour)
        let halfAngle =
            (angleRange.upperBound - angleRange.lowerBound) / 2
        let textureWidth =
            2 * texturedSectorOuterRadius * sin(halfAngle)
        let minimumSelectedY =
            centerBorderRadius * cos(halfAngle)
        let visibleHeight =
            texturedSectorOuterRadius - minimumSelectedY
        let height = max(
            textureWidth / textureAspectRatio,
            visibleHeight
        )

        return HourWheelTextureLayout(
            width: height * textureAspectRatio,
            height: height,
            centerY:
                (texturedSectorOuterRadius + minimumSelectedY) / 2
        )
    }

    static func textureCoordinate(
        forWheelPoint point: SIMD2<Float>,
        in hour: OfficeHour,
        textureAspectRatio: Float = 1
    ) -> SIMD2<Float> {
        let layout = textureLayout(
            for: hour,
            textureAspectRatio: textureAspectRatio
        )
        let selectedPoint = point.rotated(
            by: selectedRotationRadians(for: hour)
        )

        return SIMD2<Float>(
            0.5 - selectedPoint.x / layout.width,
            0.5
                + (selectedPoint.y - layout.centerY)
                / layout.height
        )
    }
}

@MainActor
enum HourWheelCanvasArtwork {
    static let textureAssetNamesByHour: [OfficeHour: String] =
        Dictionary(
            uniqueKeysWithValues: HourDialMath.sectors.map {
                ($0.hour, $0.textureAssetName)
            }
        )

    static let labelPaths: [OfficeHour: Path] = {
        Dictionary(
            uniqueKeysWithValues: OfficeHour.allCases.compactMap { hour in
                guard let path = try? curvedTextPath(
                    hour.latinName,
                    centerAngle: HourWheelGeometry.worldAngle(
                        forDialDegrees: HourDialMath.labelAngle(for: hour)
                    ),
                    maximumArcWidth: maximumLabelArcWidth(for: hour)
                ) else {
                    return nil
                }
                return (hour, path)
            }
        )
    }()

    static let numeralPath: Path = {
        let font = labelFont(size: 0.027)
        let combinedPath = CGMutablePath()

        for marker in HourWheelGeometry.ancientTimeMarkers {
            guard let path = try? centeredTextPath(
                marker.numeral,
                font: font
            ) else {
                continue
            }
            let center = HourWheelGeometry.position(
                forDialAngle: marker.dialAngle,
                radius: HourWheelGeometry.numeralRadius
            )
            let angle = CGFloat(-marker.dialAngle * .pi / 180)
            combinedPath.addPath(
                path.cgPath,
                transform: CGAffineTransform(
                    a: cos(angle),
                    b: sin(angle),
                    c: -sin(angle),
                    d: cos(angle),
                    tx: CGFloat(center.x),
                    ty: CGFloat(center.y)
                )
            )
        }

        return Path(combinedPath)
    }()

    static let sectorPaths: [OfficeHour: Path] = Dictionary(
        uniqueKeysWithValues: OfficeHour.allCases.map {
            ($0, makeSectorPath(for: $0))
        }
    )

    static func sectorPath(for hour: OfficeHour) -> Path {
        sectorPaths[hour] ?? Path()
    }

    static let textureImagesByHour: [OfficeHour: UIImage] = Dictionary(
        uniqueKeysWithValues: OfficeHour.allCases.compactMap { hour in
            guard let assetName = textureAssetNamesByHour[hour],
                  let image = UIImage(
                      named: assetName,
                      in: .main,
                      compatibleWith: nil
                  ) else {
                return nil
            }
            return (hour, image)
        }
    )

    static let annularRingPath: Path = {
        var path = Path()
        let outer = CGFloat(HourWheelGeometry.wheelRadius)
        let inner = CGFloat(HourWheelGeometry.timeRingInnerRadius)
        path.addEllipse(
            in: CGRect(
                x: -outer,
                y: -outer,
                width: 2 * outer,
                height: 2 * outer
            )
        )
        path.addEllipse(
            in: CGRect(
                x: -inner,
                y: -inner,
                width: 2 * inner,
                height: 2 * inner
            )
        )
        return path
    }()

    static let centerBorderPath: Path = {
        var path = Path()
        let outer = CGFloat(HourWheelGeometry.centerBorderRadius)
        let inner = CGFloat(HourWheelGeometry.centerOpeningRadius)
        path.addEllipse(
            in: CGRect(
                x: -outer,
                y: -outer,
                width: 2 * outer,
                height: 2 * outer
            )
        )
        path.addEllipse(
            in: CGRect(
                x: -inner,
                y: -inner,
                width: 2 * inner,
                height: 2 * inner
            )
        )
        return path
    }()

    static let centerDiscPath: Path = {
        let radius = CGFloat(HourWheelGeometry.centerOpeningRadius)
        return Path(
            ellipseIn: CGRect(
                x: -radius,
                y: -radius,
                width: 2 * radius,
                height: 2 * radius
            )
        )
    }()

    private static func makeSectorPath(for hour: OfficeHour) -> Path {
        let range = HourWheelGeometry.worldSectorAngles(for: hour)
        let segmentCount = 32
        var path = Path()

        for index in 0...segmentCount {
            let progress = Float(index) / Float(segmentCount)
            let angle = range.lowerBound
                + (range.upperBound - range.lowerBound) * progress
            let point = radialPoint(
                radius: HourWheelGeometry.texturedSectorOuterRadius,
                angle: angle
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        for index in stride(
            from: segmentCount,
            through: 0,
            by: -1
        ) {
            let progress = Float(index) / Float(segmentCount)
            let angle = range.lowerBound
                + (range.upperBound - range.lowerBound) * progress
            path.addLine(
                to: radialPoint(
                    radius: HourWheelGeometry.centerBorderRadius,
                    angle: angle
                )
            )
        }
        path.closeSubpath()
        return path
    }

    static let jerusalemCrossPath: Path = {
        var path = Path()
        path.addRect(centeredRect(width: 0.010, height: 0.050))
        path.addRect(centeredRect(width: 0.050, height: 0.010))

        for x in [-0.030 as CGFloat, 0.030] {
            for y in [-0.030 as CGFloat, 0.030] {
                path.addRect(
                    centeredRect(
                        center: CGPoint(x: x, y: y),
                        width: 0.005,
                        height: 0.016
                    )
                )
                path.addRect(
                    centeredRect(
                        center: CGPoint(x: x, y: y),
                        width: 0.016,
                        height: 0.005
                    )
                )
            }
        }
        return path
    }()

    private static func maximumLabelArcWidth(
        for hour: OfficeHour
    ) -> Float {
        let sectorRange = HourDialMath.sectorAngleRange(for: hour)
        let labelAngle = HourDialMath.labelAngle(for: hour)
        let angularMargin = min(
            labelAngle - sectorRange.lowerBound,
            sectorRange.upperBound - labelAngle
        )
        return HourWheelGeometry.labelRadius
            * Float(2 * angularMargin * .pi / 180)
            * 0.79
    }

    private static func curvedTextPath(
        _ text: String,
        centerAngle: Float,
        maximumArcWidth: Float
    ) throws -> Path {
        let baseFontSize: CGFloat = 0.041
        let baseFont = labelFont(size: baseFontSize)
        let baseLine = textLine(text, font: baseFont)
        let baseWidth = CGFloat(
            CTLineGetTypographicBounds(baseLine, nil, nil, nil)
        )
        let scale = min(
            1,
            CGFloat(maximumArcWidth) / max(baseWidth, 0.001)
        )
        let font = labelFont(size: baseFontSize * scale)
        let ctFont = CTFontCreateWithName(
            font.fontName as CFString,
            font.pointSize,
            nil
        )
        let line = textLine(text, font: font)
        let lineWidth = CGFloat(
            CTLineGetTypographicBounds(line, nil, nil, nil)
        )
        let fontVisualCenter = (
            CTFontGetAscent(ctFont) - CTFontGetDescent(ctFont)
        ) / 2
        let baselineRadius = HourWheelGeometry.labelRadius
            - Float(fontVisualCenter)
        let combinedPath = CGMutablePath()

        let runs = CTLineGetGlyphRuns(line) as NSArray
        for case let run as CTRun in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            let entireRun = CFRange(location: 0, length: 0)

            glyphs.withUnsafeMutableBufferPointer {
                CTRunGetGlyphs(run, entireRun, $0.baseAddress!)
            }
            positions.withUnsafeMutableBufferPointer {
                CTRunGetPositions(run, entireRun, $0.baseAddress!)
            }
            advances.withUnsafeMutableBufferPointer {
                CTRunGetAdvances(run, entireRun, $0.baseAddress!)
            }

            for index in 0..<glyphCount {
                guard let glyphPath = CTFontCreatePathForGlyph(
                    ctFont,
                    glyphs[index],
                    nil
                ) else {
                    continue
                }

                let glyphCenter = positions[index].x
                    + advances[index].width / 2
                let angle = centerAngle
                    + Float(lineWidth / 2 - glyphCenter)
                        / baselineRadius
                let radial = SIMD2<Float>(cos(angle), sin(angle))
                let tangent = SIMD2<Float>(sin(angle), -cos(angle))
                let baselineCenter = radial * baselineRadius
                let glyphHalfAdvance = advances[index].width / 2
                let transform = CGAffineTransform(
                    a: CGFloat(tangent.x),
                    b: CGFloat(tangent.y),
                    c: CGFloat(radial.x),
                    d: CGFloat(radial.y),
                    tx: CGFloat(baselineCenter.x)
                        - CGFloat(tangent.x) * glyphHalfAdvance,
                    ty: CGFloat(baselineCenter.y)
                        - CGFloat(tangent.y) * glyphHalfAdvance
                )
                combinedPath.addPath(
                    glyphPath,
                    transform: transform
                )
            }
        }

        guard !combinedPath.isEmpty else {
            throw HourWheelArtworkError.emptyPath
        }
        return Path(combinedPath)
    }

    private static func centeredTextPath(
        _ text: String,
        font: UIFont
    ) throws -> Path {
        let ctFont = CTFontCreateWithName(
            font.fontName as CFString,
            font.pointSize,
            nil
        )
        let line = textLine(text, font: font)
        let glyphPath = CGMutablePath()

        let runs = CTLineGetGlyphRuns(line) as NSArray
        for case let run as CTRun in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            let entireRun = CFRange(location: 0, length: 0)

            glyphs.withUnsafeMutableBufferPointer {
                CTRunGetGlyphs(run, entireRun, $0.baseAddress!)
            }
            positions.withUnsafeMutableBufferPointer {
                CTRunGetPositions(run, entireRun, $0.baseAddress!)
            }

            for index in 0..<glyphCount {
                guard let letter = CTFontCreatePathForGlyph(
                    ctFont,
                    glyphs[index],
                    nil
                ) else {
                    continue
                }
                glyphPath.addPath(
                    letter,
                    transform: CGAffineTransform(
                        translationX: positions[index].x,
                        y: positions[index].y
                    )
                )
            }
        }

        guard !glyphPath.isEmpty else {
            throw HourWheelArtworkError.emptyPath
        }
        let bounds = glyphPath.boundingBoxOfPath
        var centering = CGAffineTransform(
            translationX: -bounds.midX,
            y: -bounds.midY
        )
        guard let centeredPath = glyphPath.copy(using: &centering) else {
            throw HourWheelArtworkError.emptyPath
        }
        return Path(centeredPath)
    }

    private static func labelFont(size: CGFloat) -> UIFont {
        UIFont(
            name: "EBGaramond-Regular",
            size: size
        ) ?? UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    private static func textLine(
        _ text: String,
        font: UIFont
    ) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: text,
                attributes: [.font: font]
            )
        )
    }

    private static func radialPoint(
        radius: Float,
        angle: Float
    ) -> CGPoint {
        CGPoint(
            x: CGFloat(radius * cos(angle)),
            y: CGFloat(radius * sin(angle))
        )
    }

    private static func centeredRect(
        center: CGPoint = .zero,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }
}

@MainActor
private enum HourWheelCoreGraphicsRenderer {
    static func draw(
        in context: CGContext,
        size: CGSize,
        selectedHour: OfficeHour,
        appearance: HourWheelAppearance,
        fillBlend: Double
    ) {
        let transform = HourWheelDrawingTransform(size: size)
        let palette = HourWheelPalette.colors(for: appearance)
        let fill = HourWheelPalette.interpolatedTimeRingFill(
            at: fillBlend
        )

        fillPath(
            transform.path(HourWheelCanvasArtwork.annularRingPath),
            color: fill,
            mode: .eoFill,
            in: context
        )

        for sector in HourDialMath.sectors {
            drawTexture(
                for: sector,
                in: context,
                transform: transform
            )
        }

        context.saveGState()
        context.beginPath()
        for angle in HourWheelGeometry.textureDividerAngles {
            context.move(
                to: transform.point(
                    radius: HourWheelGeometry.centerBorderRadius,
                    angle: angle
                )
            )
            context.addLine(
                to: transform.point(
                    radius: HourWheelGeometry.texturedSectorOuterRadius,
                    angle: angle
                )
            )
        }
        context.setStrokeColor(fill.uiColor.cgColor)
        context.setLineWidth(
            transform.length(HourWheelGeometry.textureDividerWidth)
        )
        context.strokePath()
        context.restoreGState()

        fillPath(
            transform.path(HourWheelCanvasArtwork.centerBorderPath),
            color: palette.mutedBorder,
            mode: .eoFill,
            in: context
        )
        fillPath(
            transform.path(HourWheelCanvasArtwork.centerDiscPath),
            color: fill,
            in: context
        )
        fillPath(
            transform.path(HourWheelCanvasArtwork.jerusalemCrossPath),
            color: palette.jerusalemCrossForeground,
            in: context
        )
        fillPath(
            transform.path(HourWheelCanvasArtwork.numeralPath),
            color: palette.timeRingNumeral,
            in: context
        )

        for hour in OfficeHour.allCases {
            guard let labelPath =
                HourWheelCanvasArtwork.labelPaths[hour] else {
                    continue
            }
            fillPath(
                transform.path(labelPath),
                color: hour == selectedHour
                    ? palette.selectedLabel
                    : palette.foreground,
                in: context
            )
        }
    }

    private static func fillPath(
        _ path: Path,
        color: SIMD3<Float>,
        mode: CGPathDrawingMode = .fill,
        in context: CGContext
    ) {
        context.saveGState()
        context.addPath(path.cgPath)
        context.setFillColor(color.uiColor.cgColor)
        context.drawPath(using: mode)
        context.restoreGState()
    }

    private static func drawTexture(
        for sector: HourDialSector,
        in context: CGContext,
        transform: HourWheelDrawingTransform
    ) {
        guard let image =
                HourWheelCanvasArtwork
                    .textureImagesByHour[sector.hour] else {
            return
        }

        let aspectRatio = Float(
            image.size.width / max(image.size.height, 1)
        )
        let layout = HourWheelGeometry.textureLayout(
            for: sector.hour,
            textureAspectRatio: aspectRatio
        )
        context.saveGState()
        context.addPath(
            transform.path(
                HourWheelCanvasArtwork.sectorPath(for: sector.hour)
            ).cgPath
        )
        context.clip()
        context.translateBy(
            x: transform.center.x,
            y: transform.center.y
        )
        context.rotate(
            by: CGFloat(
                HourDialMath.labelAngle(for: sector.hour) * .pi / 180
            )
        )
        context.interpolationQuality = .high

        let imageRect = CGRect(
            x: -transform.length(layout.width) / 2,
            y: -transform.length(
                layout.centerY + layout.height / 2
            ),
            width: transform.length(layout.width),
            height: transform.length(layout.height)
        )
        image.draw(in: imageRect)
        context.restoreGState()
    }
}

private struct HourWheelDrawingTransform {
    let center: CGPoint
    let scale: CGFloat

    init(size: CGSize) {
        center = CGPoint(
            x: size.width / 2,
            y: size.height / 2
        )
        scale = min(size.width, size.height)
            / (2 * HourWheelGeometry.canvasArtworkExtent)
    }

    func path(_ path: Path) -> Path {
        path.applying(
            CGAffineTransform(
                a: scale,
                b: 0,
                c: 0,
                d: -scale,
                tx: center.x,
                ty: center.y
            )
        )
    }

    func point(radius: Float, angle: Float) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(radius * cos(angle)) * scale,
            y: center.y - CGFloat(radius * sin(angle)) * scale
        )
    }

    func length(_ value: Float) -> CGFloat {
        CGFloat(value) * scale
    }
}

private enum HourWheelArtworkError: Error {
    case emptyPath
}

private extension SIMD2<Float> {
    func rotated(by angle: Float) -> Self {
        SIMD2<Float>(
            x * cos(angle) - y * sin(angle),
            x * sin(angle) + y * cos(angle)
        )
    }
}

private extension SIMD3<Float> {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(x),
            green: CGFloat(y),
            blue: CGFloat(z),
            alpha: 1
        )
    }
}
