import HoursCore
import OSLog
import SwiftUI
import WidgetKit

private struct HoursEntry: TimelineEntry {
    let date: Date
    let appearanceMode: String
    let liturgicalDay: HoursLiturgicalDaySummary?

    var hour: OfficeHour {
        OfficeHour.current(at: date)
    }

    static let previewLiturgicalDay = HoursLiturgicalDaySummary(
        date: LocalDay(year: 2026, month: 8, day: 6),
        titleLatin: "In Transfiguratione Domini Nostri Jesu Christi",
        rank: .secondClass
    )
}

private struct HoursTimelineProvider: TimelineProvider {
    private static let logger = Logger(
        subsystem: "com.matthewmccarty.hours.widgets",
        category: "CalendarSnapshot"
    )

    func placeholder(in context: Context) -> HoursEntry {
        HoursEntry(
            date: Date(),
            appearanceMode:
                HoursSharedPreferences.defaultAppearanceMode,
            liturgicalDay: HoursEntry.previewLiturgicalDay
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (HoursEntry) -> Void
    ) {
        if context.isPreview {
            completion(
                HoursEntry(
                    date: Date(),
                    appearanceMode:
                        HoursSharedPreferences.defaultAppearanceMode,
                    liturgicalDay: HoursEntry.previewLiturgicalDay
                )
            )
            return
        }

        completion(entry(at: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HoursEntry>) -> Void
    ) {
        let now = Date()
        let calendarSnapshot = Self.loadCalendarSnapshot()
        let transitionDates = Self.transitionDates(
            after: now,
            calendar: .autoupdatingCurrent
        )
        let entries = ([now] + transitionDates).map {
            entry(at: $0, calendarSnapshot: calendarSnapshot)
        }
        let officeDay = LocalDay.currentOfficeDay(at: now)
        let retryDate =
            HoursLiturgicalCalendarRefreshSchedule.retryDate(
                for: calendarSnapshot,
                officeDay: officeDay,
                now: now
            )
        let policy: TimelineReloadPolicy = retryDate.map {
            .after($0)
        } ?? .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }

    private func entry(at date: Date) -> HoursEntry {
        entry(
            at: date,
            calendarSnapshot: Self.loadCalendarSnapshot()
        )
    }

    private static func loadCalendarSnapshot()
        -> HoursLiturgicalCalendarSnapshot? {
        do {
            return try HoursLiturgicalCalendarSnapshotStore.shared.load()
        } catch {
            let message = error.localizedDescription
            logger.error(
                "Unable to load calendar snapshot: \(message, privacy: .public)"
            )
            return nil
        }
    }

    private func entry(
        at date: Date,
        calendarSnapshot: HoursLiturgicalCalendarSnapshot?
    ) -> HoursEntry {
        let officeDay = LocalDay.currentOfficeDay(at: date)
        return HoursEntry(
            date: date,
            appearanceMode:
                HoursSharedPreferences.appearanceModeRawValue,
            liturgicalDay: calendarSnapshot?.day(on: officeDay)
        )
    }

    static func transitionDates(
        after date: Date,
        calendar: Calendar
    ) -> [Date] {
        let transitionHours = [0, 4, 6, 8, 10, 13, 16, 20]
        let searchEnd =
            calendar.date(byAdding: .day, value: 2, to: date)
                ?? date.addingTimeInterval(48 * 60 * 60)

        return transitionHours.compactMap { hour in
            calendar.nextDate(
                after: date,
                matching: DateComponents(
                    hour: hour,
                    minute: 0,
                    second: 0
                ),
                matchingPolicy: .nextTime
            )
        }
        .filter { $0 <= searchEnd }
        .sorted()
    }
}

private struct HoursWidgetView: View {
    let entry: HoursEntry

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .foregroundStyle(palette.foreground)
        .environment(\.colorScheme, effectiveColorScheme)
        .containerBackground(for: .widget) {
            palette.background
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabel
        )
        .accessibilityValue(entry.hour.customaryTimeRange)
        .unredacted()
    }

    private var smallLayout: some View {
        GeometryReader { proxy in
            let diameter = proxy.size.width * 1.37
            let wheelTop = proxy.size.height + 10 - diameter / 2

            ZStack {
                CanonicalHourWidgetWheel(
                    selectedHour: entry.hour,
                    palette: palette,
                    usesMediumLabelRing: true
                )
                .frame(width: diameter, height: diameter)
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height + 10
                )

                liturgicalHeader(
                    titleSize: 13,
                    rankSize: 10,
                    availableHeight: wheelTop,
                    horizontalPadding: 8
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var mediumLayout: some View {
        GeometryReader { proxy in
            let diameter = min(
                proxy.size.width * 1.02,
                proxy.size.height * 2
            )
            let wheelCenter =
                proxy.size.height / 2 + diameter * 0.46
            let wheelTop = wheelCenter - diameter / 2

            ZStack {
                CanonicalHourWidgetWheel(
                    selectedHour: entry.hour,
                    palette: palette,
                    usesMediumLabelRing: true
                )
                .frame(width: diameter, height: diameter)
                .position(
                    x: proxy.size.width / 2,
                    y: wheelCenter
                )

                liturgicalHeader(
                    titleSize: 16,
                    rankSize: 11,
                    availableHeight: wheelTop,
                    horizontalPadding: 18
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func liturgicalHeader(
        titleSize: CGFloat,
        rankSize: CGFloat,
        availableHeight: CGFloat,
        horizontalPadding: CGFloat
    ) -> some View {
        VStack(spacing: 1) {
            if let rank = entry.liturgicalDay?.rank {
                Text(rank.displayName)
                    .font(.system(size: rankSize, design: .serif))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
            }

            if let title = entry.liturgicalDay?.titleLatin {
                Text(title)
                    .font(.system(size: titleSize, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: max(0, availableHeight), alignment: .center)
    }

    private var accessibilityLabel: String {
        [
            entry.liturgicalDay?.rank?.displayName,
            entry.liturgicalDay?.titleLatin,
            "Current canonical hour, \(entry.hour.englishTitle)",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private var effectiveColorScheme: ColorScheme {
        guard entry.appearanceMode != "system" else {
            return systemColorScheme
        }

        switch entry.hour {
        case .matins, .compline:
            return .dark
        default:
            return .light
        }
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme: effectiveColorScheme)
    }
}

private struct WidgetPalette: Equatable {
    let isDark: Bool
    let background: Color
    let foreground: Color
    let secondary: Color
    let ring: Color
    let ringText: Color
    let divider: Color
    let accent: Color

    init(colorScheme: ColorScheme) {
        isDark = colorScheme == .dark
        accent = Color(
            red: colorScheme == .dark ? 0.95 : 0.68,
            green: colorScheme == .dark ? 0.45 : 0.12,
            blue: colorScheme == .dark ? 0.38 : 0.09
        )

        if colorScheme == .dark {
            background = .black
            foreground = Color(
                red: 0.85,
                green: 0.84,
                blue: 0.82
            )
            secondary = foreground.opacity(0.68)
            ring = Color(white: 0.035)
            ringText = Color(white: 0.90)
            divider = Color(white: 0.30)
        } else {
            background = .white
            foreground = Color(white: 0.06)
            secondary = foreground.opacity(0.62)
            ring = Color(white: 0.06)
            ringText = Color(white: 0.92)
            divider = Color(white: 0.55)
        }
    }
}

private struct CanonicalHourWidgetWheel: View {
    let selectedHour: OfficeHour
    let palette: WidgetPalette
    let usesMediumLabelRing: Bool

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .widgetAccentedRenderingMode(.desaturated)
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private var assetName: String {
        let hourName =
            selectedHour.rawValue.prefix(1).uppercased()
            + String(selectedHour.rawValue.dropFirst())
        return "WidgetWheel\(hourName)"
            + (usesMediumLabelRing ? "Medium" : "")
            + (palette.isDark ? "Dark" : "Light")
    }
}

private struct LegacyCanonicalHourWidgetWheel: View {
    let selectedHour: OfficeHour
    let palette: WidgetPalette

    private static let sectors: [WidgetHourSector] = [
        WidgetHourSector(
            hour: .matins,
            startDegrees: 0,
            endDegrees: 60,
            textureName: "MatutinumTexture"
        ),
        WidgetHourSector(
            hour: .lauds,
            startDegrees: 60,
            endDegrees: 90,
            textureName: "LaudesTexture"
        ),
        WidgetHourSector(
            hour: .prime,
            startDegrees: 90,
            endDegrees: 120,
            textureName: "PrimaTexture"
        ),
        WidgetHourSector(
            hour: .terce,
            startDegrees: 120,
            endDegrees: 150,
            textureName: "TertiaTexture"
        ),
        WidgetHourSector(
            hour: .sext,
            startDegrees: 150,
            endDegrees: 195,
            textureName: "SextaTexture"
        ),
        WidgetHourSector(
            hour: .none,
            startDegrees: 195,
            endDegrees: 240,
            textureName: "NonaTexture"
        ),
        WidgetHourSector(
            hour: .vespers,
            startDegrees: 240,
            endDegrees: 300,
            textureName: "VesperaeTexture"
        ),
        WidgetHourSector(
            hour: .compline,
            startDegrees: 300,
            endDegrees: 360,
            textureName: "CompletoriumTexture"
        ),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                wheelCanvas

                ForEach(Self.sectors) { sector in
                    Text(sector.hour.latinName)
                        .font(
                            .system(
                                size: max(7, size * 0.039),
                                weight: sector.hour == selectedHour
                                    ? .bold
                                    : .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(
                            sector.hour == selectedHour
                                ? palette.accent
                                : palette.foreground
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(width: size * sector.labelWidth)
                        .offset(y: -size * 0.456)
                        .rotationEffect(.degrees(sector.centerDegrees))
                }
            }
            .frame(width: size, height: size)
            .rotationEffect(
                .degrees(-selectedSector.centerDegrees)
            )
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
        }
        .accessibilityHidden(true)
    }

    private var wheelCanvas: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(
                x: size.width / 2,
                y: size.height / 2
            )
            let radius = diameter * 0.45
            let innerRadius = diameter * 0.083
            let sectorRadius = diameter * 0.408
            let outerRing = Path(
                ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            context.fill(outerRing, with: .color(palette.ring))

            for sector in Self.sectors {
                let path = sectorPath(
                    sector,
                    center: center,
                    innerRadius: innerRadius,
                    outerRadius: sectorRadius
                )

                context.drawLayer { layer in
                    layer.clip(to: path)
                    let image = layer.resolve(
                        Image(sector.textureName)
                    )
                    layer.draw(
                        image,
                        in: CGRect(
                            x: center.x - sectorRadius,
                            y: center.y - sectorRadius,
                            width: sectorRadius * 2,
                            height: sectorRadius * 2
                        )
                    )

                    if sector.hour != selectedHour {
                        layer.fill(
                            path,
                            with: .color(
                                palette.background.opacity(0.18)
                            )
                        )
                    }
                }

                context.stroke(
                    path,
                    with: .color(palette.divider),
                    lineWidth: max(0.7, diameter * 0.004)
                )
            }

            for index in 0..<24 {
                let numeral = Self.romanNumeral((index % 12) + 1)
                let text = context.resolve(
                    Text(numeral)
                        .font(
                            .system(
                                size: max(5, diameter * 0.021),
                                weight: .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(palette.ringText)
                )
                let angle =
                    Double(index) / 24 * 2 * Double.pi - Double.pi / 2
                let point = CGPoint(
                    x: center.x + cos(angle) * diameter * 0.429,
                    y: center.y + sin(angle) * diameter * 0.429
                )
                context.draw(text, at: point)
            }

            let centerDisc = Path(
                ellipseIn: CGRect(
                    x: center.x - innerRadius,
                    y: center.y - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                )
            )
            context.fill(centerDisc, with: .color(palette.ring))
            context.stroke(
                centerDisc,
                with: .color(palette.divider),
                lineWidth: max(0.7, diameter * 0.004)
            )
            drawJerusalemCross(
                in: &context,
                center: center,
                size: diameter * 0.064
            )
        }
    }

    private var selectedSector: WidgetHourSector {
        Self.sectors.first { $0.hour == selectedHour }
            ?? Self.sectors[0]
    }

    private func sectorPath(
        _ sector: WidgetHourSector,
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(sector.startDegrees - 90),
            endAngle: .degrees(sector.endDegrees - 90),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(sector.endDegrees - 90),
            endAngle: .degrees(sector.startDegrees - 90),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func drawJerusalemCross(
        in context: inout GraphicsContext,
        center: CGPoint,
        size: CGFloat
    ) {
        var cross = Path()
        cross.addRect(
            CGRect(
                x: center.x - size * 0.09,
                y: center.y - size * 0.50,
                width: size * 0.18,
                height: size
            )
        )
        cross.addRect(
            CGRect(
                x: center.x - size * 0.50,
                y: center.y - size * 0.09,
                width: size,
                height: size * 0.18
            )
        )

        let satelliteOffset = size * 0.63
        for xDirection in [-1.0, 1.0] {
            for yDirection in [-1.0, 1.0] {
                let point = CGPoint(
                    x: center.x + satelliteOffset * xDirection,
                    y: center.y + satelliteOffset * yDirection
                )
                cross.addRect(
                    CGRect(
                        x: point.x - size * 0.04,
                        y: point.y - size * 0.17,
                        width: size * 0.08,
                        height: size * 0.34
                    )
                )
                cross.addRect(
                    CGRect(
                        x: point.x - size * 0.17,
                        y: point.y - size * 0.04,
                        width: size * 0.34,
                        height: size * 0.08
                    )
                )
            }
        }
        context.fill(cross, with: .color(palette.ringText))
    }

    private static func romanNumeral(_ value: Int) -> String {
        switch value {
        case 1: "I"
        case 2: "II"
        case 3: "III"
        case 4: "IV"
        case 5: "V"
        case 6: "VI"
        case 7: "VII"
        case 8: "VIII"
        case 9: "IX"
        case 10: "X"
        case 11: "XI"
        default: "XII"
        }
    }
}

private struct WidgetHourSector: Identifiable {
    let hour: OfficeHour
    let startDegrees: Double
    let endDegrees: Double
    let textureName: String

    var id: OfficeHour { hour }
    var centerDegrees: Double {
        (startDegrees + endDegrees) / 2
    }

    var labelWidth: CGFloat {
        switch hour {
        case .matins, .vespers, .compline:
            0.30
        default:
            0.22
        }
    }
}

struct HoursWidget: Widget {
    let kind = "HoursCurrentCanonicalHourV9"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: HoursTimelineProvider()
        ) { entry in
            HoursWidgetView(entry: entry)
        }
        .configurationDisplayName("Current Hour")
        .description(
            "Shows the current feast or feria and canonical hour."
        )
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct HoursWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HoursWidget()
    }
}

#Preview(
    "Small — Compline",
    as: .systemSmall
) {
    HoursWidget()
} timeline: {
    HoursEntry(
        date: Date(
            timeIntervalSince1970: 1_785_290_400
        ),
        appearanceMode: "dynamic",
        liturgicalDay: HoursEntry.previewLiturgicalDay
    )
}

#Preview(
    "Medium — Sext",
    as: .systemMedium
) {
    HoursWidget()
} timeline: {
    HoursEntry(
        date: Date(
            timeIntervalSince1970: 1_785_254_400
        ),
        appearanceMode: "dynamic",
        liturgicalDay: HoursEntry.previewLiturgicalDay
    )
}
