import HoursCore
import SwiftUI

struct CanonicalHourSundialView: View {
    @Binding var selection: OfficeHour
    @Binding var followsLocalTime: Bool
    let showsShadow: Bool
    let onOpenOffice: (OfficeHour) -> Void

    @Environment(\.scenePhase) private var scenePhase

    private static let idealAspectRatio: CGFloat = 0.74
    fileprivate static let selectionAnimation =
        Animation.easeInOut(duration: 0.72)
    fileprivate static let initialShadowAnimation =
        Animation.easeInOut(duration: 2)
    private static let initialShadowAnimationDuration =
        Duration.seconds(2)

    @State private var initialAnimationStage =
        SundialInitialAnimationStage.waiting
    @State private var initialPresentation =
        SundialPresentation.matins
    @State private var initialAnimationProgress = 0.0

    var body: some View {
        TimelineView(
            .periodic(
                from: .now,
                by: SundialRefreshPolicy.liveInterval
            )
        ) { context in
            GeometryReader { proxy in
                let layout = SundialLayout(size: proxy.size)
                let liveHour = OfficeHour.current(at: context.date)
                let livePresentation =
                    SundialPresentation.live(for: liveHour)
                let usesInitialPresentation =
                    followsLocalTime
                        && initialAnimationStage != .complete
                let displayedShadow = usesInitialPresentation
                    ? initialPresentation.shadow
                    : followsLocalTime
                    ? livePresentation.shadow
                    : SundialTimeMath.shadow(for: selection)
                let displayedSky = followsLocalTime
                    ? SundialTimeMath.ambientSky(at: context.date)
                    : SundialTimeMath.ambientSky(for: selection)
                let shadowStrength = showsShadow
                    ? usesInitialPresentation
                        ? initialPresentation.strength
                            * initialAnimationProgress
                        : followsLocalTime
                            ? livePresentation.strength
                            : displayedSky.shadowStrength
                    : 0

                ZStack {
                    sundialFace(
                        layout: layout,
                        shadow: displayedShadow,
                        strength: shadowStrength,
                        launchProgress: usesInitialPresentation
                            ? initialAnimationProgress
                            : 1
                    )

                    ForEach(OfficeHour.allCases, id: \.self) { hour in
                        hourButton(
                            hour,
                            at: layout.labelPosition(for: hour)
                        )
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .contentShape(Rectangle())
                .highPriorityGesture(hourSwipeGesture)
                .animation(
                    scenePhase == .active
                        ? initialAnimationStage.animation
                        : nil,
                    value: displayedShadow
                )
                .animation(
                    .easeInOut(duration: 0.24),
                    value: followsLocalTime
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Canonical hours")
                .accessibilityValue(
                    followsLocalTime
                        ? "Current local time \(context.date.formatted(date: .omitted, time: .shortened))"
                        : "\(selection.englishTitle) selected manually"
                )
                .accessibilityIdentifier("canonical-hour-sundial")
                .accessibilityHint(
                    followsLocalTime
                        ? "Tap an hour or swipe toward another hour."
                        : "Tap Reset to return the shadow to local time."
                )
                .accessibilityAdjustableAction { direction in
                    adjustSelection(direction)
                }
                .onChange(of: liveHour) { _, newHour in
                    guard followsLocalTime else { return }
                    selection = newHour
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                finishInitialShadowAnimation()
                return
            }
            await runInitialShadowAnimation()
        }
    }

    static func idealHeight(for width: CGFloat) -> CGFloat {
        max(
            width / idealAspectRatio,
            minimumHeight
        )
    }

    static var minimumHeight: CGFloat {
        SundialLayout.minimumHeight
    }

    private func sundialFace(
        layout: SundialLayout,
        shadow: SundialTimeMath.Shadow,
        strength: Double,
        launchProgress: Double
    ) -> some View {
        return ZStack {
            ProjectedSundialShadow(
                verticalProgress: shadow.verticalProgress,
                length: shadow.length,
                launchProgress: launchProgress
            )
            .fill(
                Color.hoursPrimaryText.opacity(
                    0.13 * strength
                )
            )
            .blur(radius: layout.shadowOuterBlurRadius)

            ProjectedSundialShadow(
                verticalProgress: shadow.verticalProgress,
                length: shadow.length,
                launchProgress: launchProgress
            )
            .fill(
                LinearGradient(
                    stops: [
                        .init(
                            color: Color.hoursPrimaryText.opacity(
                                0.34 * strength
                            ),
                            location: 0
                        ),
                        .init(
                            color: Color.hoursPrimaryText.opacity(
                                0.20 * strength
                            ),
                            location: 0.58
                        ),
                        .init(
                            color: Color.hoursPrimaryText.opacity(
                                0.07 * strength
                            ),
                            location: 1
                        ),
                    ],
                    startPoint: layout.shadowStartUnitPoint(
                        for: shadow
                    ),
                    endPoint: layout.shadowTipUnitPoint(for: shadow)
                )
            )
            .blur(radius: layout.shadowInnerBlurRadius)
        }
        .accessibilityHidden(true)
    }

    private func hourButton(
        _ hour: OfficeHour,
        at position: CGPoint
    ) -> some View {
        let showsSelectionChevron =
            selection == hour
                && SundialAffordance.showsSelectionChevron(
                    for: hour,
                    shadowsEnabled: showsShadow
                )

        return Button {
            if selection == hour {
                onOpenOffice(hour)
            } else {
                select(hour)
            }
        } label: {
            HStack(spacing: SundialLayout.disclosureSpacing) {
                Text(hour.latinName)
                    .font(
                        .custom(
                            "EBGaramond-Regular",
                            size: 21,
                            relativeTo: .body
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(
                        selection == hour
                            ? Color.hoursPrimaryText
                            : Color.hoursPrimaryText.opacity(0.42)
                    )
                    .frame(
                        width: SundialLayout.hourLabelWidth,
                        height: 44,
                        alignment: .trailing
                    )

                ZStack {
                    if showsSelectionChevron {
                        Image(systemName: "chevron.right")
                            .font(
                                .system(
                                    size: 14,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                Color.hoursPrimaryText
                            )
                            .transition(.opacity)
                    }
                }
                .frame(
                    width: SundialLayout.disclosureWidth,
                    height: 44,
                    alignment: .center
                )
                .animation(
                    Self.selectionAnimation,
                    value: showsSelectionChevron
                )
                .accessibilityHidden(true)
            }
            .frame(
                width: SundialLayout.hourRowWidth,
                height: 44,
                alignment: .trailing
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(position)
        .transaction { transaction in
            transaction.animation = nil
        }
        .transition(.opacity)
        .accessibilityLabel(
            "\(hour.latinName), \(hour.englishTitle)"
        )
        .accessibilityValue(
            selection == hour
                ? "Selected, \(hour.customaryTimeRange)"
                : hour.customaryTimeRange
        )
        .accessibilityHint(
            selection == hour
                ? "Opens this office"
                : "Focuses this hour"
        )
        .accessibilityIdentifier("hour-\(hour.rawValue)")
    }

    private func adjustSelection(
        _ direction: AccessibilityAdjustmentDirection
    ) {
        switch direction {
        case .increment:
            selectAdjacentHour(by: 1)
        case .decrement:
            selectAdjacentHour(by: -1)
        @unknown default:
            return
        }
    }

    private var hourSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height

                if abs(verticalDistance) >= 24,
                   abs(verticalDistance) > abs(horizontalDistance) {
                    selectAdjacentHour(
                        by: verticalDistance < 0 ? 1 : -1
                    )
                } else if abs(horizontalDistance) >= 40 {
                    selectAdjacentHour(
                        by: horizontalDistance < 0 ? 1 : -1
                    )
                }
            }
    }

    private func selectAdjacentHour(by offset: Int) {
        let hours = OfficeHour.allCases
        let currentIndex = hours.firstIndex(of: selection) ?? 0
        let nextIndex = (currentIndex + offset + hours.count) % hours.count
        select(hours[nextIndex])
    }

    private func select(_ hour: OfficeHour) {
        withAnimation(Self.selectionAnimation) {
            initialAnimationStage = .complete
            followsLocalTime = false
            selection = hour
        }
    }

    private func runInitialShadowAnimation() async {
        guard initialAnimationStage == .waiting else { return }

        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled, followsLocalTime else {
            finishInitialShadowAnimation()
            return
        }

        guard let presentation =
                SundialInitialAnimationPlan.presentation(at: Date()) else {
            finishInitialShadowAnimation()
            return
        }

        var setupTransaction = Transaction()
        setupTransaction.disablesAnimations = true
        withTransaction(setupTransaction) {
            initialPresentation = presentation
        }

        await Task.yield()
        guard !Task.isCancelled, followsLocalTime else {
            finishInitialShadowAnimation()
            return
        }

        withAnimation(Self.initialShadowAnimation) {
            initialAnimationStage = .animating
            initialAnimationProgress = 1
        }

        try? await Task.sleep(for: Self.initialShadowAnimationDuration)
        guard !Task.isCancelled else { return }
        finishInitialShadowAnimation()
    }

    private func finishInitialShadowAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            initialAnimationStage = .complete
        }
    }
}

nonisolated enum SundialRefreshPolicy {
    static let liveInterval: TimeInterval = 5 * 60
}

private enum SundialInitialAnimationStage {
    case waiting
    case animating
    case complete

    var animation: Animation? {
        switch self {
        case .waiting:
            nil
        case .animating:
            CanonicalHourSundialView.initialShadowAnimation
        case .complete:
            CanonicalHourSundialView.selectionAnimation
        }
    }
}

nonisolated struct SundialPresentation: Equatable {
    let shadow: SundialTimeMath.Shadow
    let strength: Double

    static let matins = SundialPresentation(
        shadow: SundialTimeMath.shadow(for: .matins),
        strength: 0
    )

    static let lauds = SundialPresentation(
        shadow: SundialTimeMath.shadow(for: .lauds),
        strength: SundialTimeMath.ambientSky(for: .lauds).shadowStrength
    )

    static func live(
        for hour: OfficeHour
    ) -> SundialPresentation {
        return SundialPresentation(
            shadow: SundialTimeMath.shadow(for: hour),
            strength:
                SundialTimeMath.ambientSky(for: hour).shadowStrength
        )
    }
}

nonisolated enum SundialInitialAnimationPlan {
    static func presentation(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SundialPresentation? {
        let hour = OfficeHour.current(at: date, calendar: calendar)

        guard hour != .matins else { return nil }
        return .live(for: hour)
    }
}

nonisolated enum SundialAffordance {
    static func showsSelectionChevron(
        for hour: OfficeHour,
        shadowsEnabled: Bool
    ) -> Bool {
        !shadowsEnabled
            || SundialTimeMath.prefersDarkAppearance(for: hour)
    }
}

nonisolated struct SundialLayout {
    static let minimumHourRowSpacing: CGFloat = 50
    static let hourLabelWidth: CGFloat = 120
    static let disclosureSpacing: CGFloat = 12
    static let disclosureWidth: CGFloat = 16
    static let hourRowWidth =
        hourLabelWidth + disclosureSpacing + disclosureWidth
    static let minimumHeight =
        CGFloat(OfficeHour.allCases.count - 1)
            * minimumHourRowSpacing
            + 88

    let size: CGSize

    private var labelTrailingPadding: CGFloat {
        max(16, min(24, size.width * 0.05))
    }

    private var hourRowLeadingEdge: CGFloat {
        max(
            0,
            size.width - Self.hourRowWidth - labelTrailingPadding
        )
    }

    private var topRowY: CGFloat {
        22
    }

    private var bottomHourRowY: CGFloat {
        max(topRowY, size.height - 66)
    }

    private var rowSpacing: CGFloat {
        max(
            Self.minimumHourRowSpacing,
            (bottomHourRowY - topRowY)
                / CGFloat(max(OfficeHour.allCases.count - 1, 1))
        )
    }

    private var shadowOrigin: CGPoint {
        CGPoint(
            x: -max(18, size.width * 0.045),
            y: topRowY + rowSpacing * 3.5
        )
    }

    func shadowStartUnitPoint(
        for _: SundialTimeMath.Shadow
    ) -> UnitPoint {
        return UnitPoint(
            x: size.width > 0 ? shadowOrigin.x / size.width : 0,
            y: size.height > 0 ? shadowOrigin.y / size.height : 0.5
        )
    }

    var shadowOuterBlurRadius: CGFloat {
        max(2.6, min(5, size.width * 0.011))
    }

    var shadowInnerBlurRadius: CGFloat {
        max(1, min(2, size.width * 0.004))
    }

    func labelPosition(for hour: OfficeHour) -> CGPoint {
        let index = OfficeHour.allCases.firstIndex(of: hour) ?? 0
        return CGPoint(
            x: hourRowLeadingEdge + Self.hourRowWidth / 2,
            y: topRowY + CGFloat(index) * rowSpacing
        )
    }

    func shadowPath(for shadow: SundialTimeMath.Shadow) -> Path {
        let entranceProgress = min(max(shadow.length, 0), 1)
        let isEntrance =
            shadow.verticalProgress <= laudsProgress + 0.000_1
        guard isEntrance || shadow.length > 0.001 else {
            return Path()
        }

        let fullSourceHalfHeight =
            max(8, min(14, size.height * 0.024))
        let sourceHalfHeight = isEntrance
            ? interpolate(
                from: 0.75,
                to: fullSourceHalfHeight,
                progress: smoothstep(entranceProgress)
            )
            : fullSourceHalfHeight * shadow.length
        let tip = shadowTip(for: shadow)

        var path = Path()
        path.move(
            to: CGPoint(
                x: shadowOrigin.x,
                y: shadowOrigin.y - sourceHalfHeight
            )
        )
        path.addLine(to: tip)
        path.addLine(
            to: CGPoint(
                x: shadowOrigin.x,
                y: shadowOrigin.y + sourceHalfHeight
            )
        )
        path.closeSubpath()
        return path
    }

    func shadowTip(
        for shadow: SundialTimeMath.Shadow
    ) -> CGPoint {
        guard shadow.verticalProgress <= laudsProgress else {
            return shadowTarget(
                verticalProgress: shadow.verticalProgress
            )
        }

        return entranceTip(
            progress: min(max(shadow.length, 0), 1)
        )
    }

    func shadowTipUnitPoint(
        for shadow: SundialTimeMath.Shadow
    ) -> UnitPoint {
        let tip = shadowTip(for: shadow)
        return UnitPoint(
            x: size.width > 0 ? tip.x / size.width : 0.5,
            y: size.height > 0 ? tip.y / size.height : 0
        )
    }

    func shadowSource(
        for _: SundialTimeMath.Shadow
    ) -> CGPoint {
        shadowOrigin
    }

    private func shadowTarget(
        verticalProgress: Double
    ) -> CGPoint {
        let progress = CGFloat(
            min(max(verticalProgress, 0), 1)
        )
        return CGPoint(
            x: hourRowLeadingEdge + Self.hourLabelWidth * 0.42,
            y: topRowY
                + (bottomHourRowY - topRowY) * progress
        )
    }

    private var laudsProgress: Double {
        1.0 / Double(OfficeHour.allCases.count - 1)
    }

    private func entranceTip(progress: Double) -> CGPoint {
        let start = CGPoint(
            x: max(4, size.width * 0.025),
            y: -max(8, size.height * 0.02)
        )
        let end = shadowTarget(
            verticalProgress: laudsProgress
        )
        let control1 = CGPoint(
            x: start.x + size.width * 0.025,
            y: start.y + size.height * 0.04
        )
        let control2 = CGPoint(
            x: end.x * 0.52,
            y: end.y * 0.42
        )
        let inverse = 1 - progress
        let startWeight = inverse * inverse * inverse
        let control1Weight =
            3 * inverse * inverse * progress
        let control2Weight =
            3 * inverse * progress * progress
        let endWeight = progress * progress * progress
        return CGPoint(
            x: start.x * startWeight
                + control1.x * control1Weight
                + control2.x * control2Weight
                + end.x * endWeight,
            y: start.y * startWeight
                + control1.y * control1Weight
                + control2.y * control2Weight
                + end.y * endWeight
        )
    }

    private func interpolate(
        from start: CGFloat,
        to end: CGFloat,
        progress: Double
    ) -> CGFloat {
        start + (end - start) * progress
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

private struct ProjectedSundialShadow: Shape {
    var verticalProgress: Double
    var length: Double
    var launchProgress: Double

    var animatableData:
        AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get {
            AnimatablePair(
                AnimatablePair(
                    verticalProgress,
                    length
                ),
                launchProgress
            )
        }
        set {
            verticalProgress = newValue.first.first
            length = newValue.first.second
            launchProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shadow = SundialLaunchProjection.shadow(
            toward: SundialTimeMath.Shadow(
                angleDegrees: 0,
                length: length,
                centerlineDepth: 0,
                verticalProgress: verticalProgress
            ),
            progress: launchProgress
        )
        return SundialLayout(size: rect.size).shadowPath(
            for: shadow
        )
    }
}

nonisolated enum SundialLaunchProjection {
    static let entranceFraction = 0.45

    static func shadow(
        toward target: SundialTimeMath.Shadow,
        progress: Double
    ) -> SundialTimeMath.Shadow {
        let progress = min(max(progress, 0), 1)
        let lauds = SundialTimeMath.shadow(for: .lauds)

        guard progress < 1 else { return target }

        if progress <= entranceFraction {
            let entranceProgress = progress / entranceFraction
            return SundialTimeMath.Shadow(
                angleDegrees: -90,
                length: entranceProgress,
                centerlineDepth:
                    lauds.centerlineDepth * entranceProgress,
                verticalProgress:
                    lauds.verticalProgress * entranceProgress
            )
        }

        let travelProgress =
            (progress - entranceFraction) / (1 - entranceFraction)
        return SundialTimeMath.Shadow(
            angleDegrees: lauds.angleDegrees
                + (
                    target.angleDegrees - lauds.angleDegrees
                ) * travelProgress,
            length: lauds.length
                + (target.length - lauds.length) * travelProgress,
            centerlineDepth: lauds.centerlineDepth
                + (
                    target.centerlineDepth - lauds.centerlineDepth
                ) * travelProgress,
            verticalProgress: lauds.verticalProgress
                + (
                    target.verticalProgress - lauds.verticalProgress
                ) * travelProgress
        )
    }
}

nonisolated enum SundialTimeMath {
    struct Shadow: Equatable {
        let angleDegrees: Double
        let length: Double
        let centerlineDepth: Double
        let verticalProgress: Double
    }

    struct AmbientSky: Equatable, Sendable {
        let backgroundRed: Double
        let backgroundGreen: Double
        let backgroundBlue: Double
        let upperRed: Double
        let upperGreen: Double
        let upperBlue: Double
        let lowerRed: Double
        let lowerGreen: Double
        let lowerBlue: Double
        let darkness: Double
        let accentStrength: Double
        let shadowStrength: Double
    }

    static func angle(for hour: OfficeHour) -> Double {
        switch hour {
        case .matins, .lauds: -90
        case .prime: -60
        case .terce: -30
        case .sext: 0
        case .none: 30
        case .vespers: 60
        case .compline: 90
        @unknown default: 0
        }
    }

    static func shadow(for hour: OfficeHour) -> Shadow {
        shadow(
            secondsAfterMidnight: canonicalSeconds(for: hour)
        )
    }

    static func ambientSky(
        for hour: OfficeHour
    ) -> AmbientSky {
        ambientSky(
            secondsAfterMidnight: canonicalSeconds(for: hour)
        )
    }

    static func prefersDarkAppearance(
        for hour: OfficeHour
    ) -> Bool {
        switch hour {
        case .matins, .compline:
            true
        default:
            false
        }
    }

    static func shadow(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Shadow {
        shadow(
            secondsAfterMidnight: localSeconds(
                at: date,
                calendar: calendar
            )
        )
    }

    static func ambientSky(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> AmbientSky {
        ambientSky(
            secondsAfterMidnight: localSeconds(
                at: date,
                calendar: calendar
            )
        )
    }

    static func displayedAmbientSky(
        for selection: OfficeHour
    ) -> AmbientSky {
        ambientSky(for: selection)
    }

    static func ambientSky(
        secondsAfterMidnight seconds: Double
    ) -> AmbientSky {
        let day = 24.0 * 3_600
        let normalized = (
            seconds.truncatingRemainder(dividingBy: day) + day
        ).truncatingRemainder(dividingBy: day)
        let segmentDuration = 3.0 * 3_600
        let segment = Int(normalized / segmentDuration)
        let nextSegment =
            (segment + 1) % ambientSkyKeyframes.count
        let rawProgress = (
            normalized
                - Double(segment) * segmentDuration
        ) / segmentDuration
        return interpolate(
            from: ambientSkyKeyframes[segment],
            to: ambientSkyKeyframes[nextSegment],
            progress: smoothstep(rawProgress)
        )
    }

    private static func localSeconds(
        at date: Date,
        calendar: Calendar
    ) -> Double {
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        let seconds = Double(components.hour ?? 0) * 3_600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        return seconds
    }

    static func shadow(secondsAfterMidnight seconds: Double) -> Shadow {
        let day = 24.0 * 3_600
        let threeHours = 3.0 * 3_600
        let normalized = (
            seconds.truncatingRemainder(dividingBy: day) + day
        ).truncatingRemainder(dividingBy: day)
        let complineStart = 21.0 * 3_600

        if normalized < threeHours {
            return projectedShadow(
                angleDegrees: -90,
                length: normalized / threeHours,
                verticalProgress:
                    normalized / complineStart
            )
        }

        let vespersStart = 18.0 * 3_600

        if normalized <= vespersStart {
            let progress = (
                normalized - threeHours
            ) / (vespersStart - threeHours)
            return projectedShadow(
                angleDegrees: -90 + 150 * progress,
                length: 1,
                verticalProgress:
                    normalized / complineStart
            )
        }

        if normalized < complineStart {
            let progress = (
                normalized - vespersStart
            ) / threeHours
            return projectedShadow(
                angleDegrees: 60 + 30 * progress,
                length: 1 - smoothstep(progress),
                verticalProgress:
                    normalized / complineStart
            )
        }

        return projectedShadow(
            angleDegrees: 90,
            length: 0,
            verticalProgress: 1
        )
    }

    private static func projectedShadow(
        angleDegrees: Double,
        length: Double,
        verticalProgress: Double
    ) -> Shadow {
        let radians = angleDegrees * .pi / 180
        let elevationProjection = max(cos(radians), 0)
        let fullCenterlineDepth = 0.035
            + 0.28 * pow(elevationProjection, 1.2)

        return Shadow(
            angleDegrees: angleDegrees,
            length: length,
            centerlineDepth: length * fullCenterlineDepth,
            verticalProgress: verticalProgress
        )
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func interpolate(
        from start: AmbientSky,
        to end: AmbientSky,
        progress: Double
    ) -> AmbientSky {
        func channel(
            _ startValue: Double,
            _ endValue: Double
        ) -> Double {
            startValue
                + (endValue - startValue) * progress
        }

        return AmbientSky(
            backgroundRed: channel(
                start.backgroundRed,
                end.backgroundRed
            ),
            backgroundGreen: channel(
                start.backgroundGreen,
                end.backgroundGreen
            ),
            backgroundBlue: channel(
                start.backgroundBlue,
                end.backgroundBlue
            ),
            upperRed: channel(start.upperRed, end.upperRed),
            upperGreen: channel(
                start.upperGreen,
                end.upperGreen
            ),
            upperBlue: channel(start.upperBlue, end.upperBlue),
            lowerRed: channel(start.lowerRed, end.lowerRed),
            lowerGreen: channel(
                start.lowerGreen,
                end.lowerGreen
            ),
            lowerBlue: channel(start.lowerBlue, end.lowerBlue),
            darkness: channel(start.darkness, end.darkness),
            accentStrength: channel(
                start.accentStrength,
                end.accentStrength
            ),
            shadowStrength: channel(
                start.shadowStrength,
                end.shadowStrength
            )
        )
    }

    private static let ambientSkyKeyframes: [AmbientSky] = [
        AmbientSky(
            backgroundRed: 0.025,
            backgroundGreen: 0.030,
            backgroundBlue: 0.055,
            upperRed: 0.05,
            upperGreen: 0.09,
            upperBlue: 0.22,
            lowerRed: 0.12,
            lowerGreen: 0.17,
            lowerBlue: 0.33,
            darkness: 1,
            accentStrength: 0.54,
            shadowStrength: 0
        ),
        AmbientSky(
            backgroundRed: 0.93,
            backgroundGreen: 0.92,
            backgroundBlue: 0.91,
            upperRed: 0.26,
            upperGreen: 0.30,
            upperBlue: 0.56,
            lowerRed: 0.83,
            lowerGreen: 0.49,
            lowerBlue: 0.34,
            darkness: 0.24,
            accentStrength: 0.72,
            shadowStrength: 0.26
        ),
        AmbientSky(
            backgroundRed: 0.96,
            backgroundGreen: 0.97,
            backgroundBlue: 0.98,
            upperRed: 0.28,
            upperGreen: 0.56,
            upperBlue: 0.86,
            lowerRed: 0.68,
            lowerGreen: 0.76,
            lowerBlue: 0.82,
            darkness: 0.12,
            accentStrength: 0.82,
            shadowStrength: 0.76
        ),
        AmbientSky(
            backgroundRed: 0.985,
            backgroundGreen: 0.99,
            backgroundBlue: 1,
            upperRed: 0.20,
            upperGreen: 0.57,
            upperBlue: 0.91,
            lowerRed: 0.50,
            lowerGreen: 0.74,
            lowerBlue: 0.89,
            darkness: 0,
            accentStrength: 0.78,
            shadowStrength: 0.92
        ),
        AmbientSky(
            backgroundRed: 1,
            backgroundGreen: 1,
            backgroundBlue: 1,
            upperRed: 0.16,
            upperGreen: 0.58,
            upperBlue: 0.94,
            lowerRed: 0.57,
            lowerGreen: 0.78,
            lowerBlue: 0.92,
            darkness: 0,
            accentStrength: 0.82,
            shadowStrength: 1
        ),
        AmbientSky(
            backgroundRed: 0.98,
            backgroundGreen: 0.97,
            backgroundBlue: 0.94,
            upperRed: 0.28,
            upperGreen: 0.57,
            upperBlue: 0.86,
            lowerRed: 0.66,
            lowerGreen: 0.72,
            lowerBlue: 0.79,
            darkness: 0.04,
            accentStrength: 0.76,
            shadowStrength: 0.84
        ),
        AmbientSky(
            backgroundRed: 0.93,
            backgroundGreen: 0.91,
            backgroundBlue: 0.90,
            upperRed: 0.32,
            upperGreen: 0.28,
            upperBlue: 0.54,
            lowerRed: 0.86,
            lowerGreen: 0.39,
            lowerBlue: 0.27,
            darkness: 0.18,
            accentStrength: 0.70,
            shadowStrength: 0.30
        ),
        AmbientSky(
            backgroundRed: 0.025,
            backgroundGreen: 0.030,
            backgroundBlue: 0.055,
            upperRed: 0.05,
            upperGreen: 0.09,
            upperBlue: 0.22,
            lowerRed: 0.12,
            lowerGreen: 0.17,
            lowerBlue: 0.33,
            darkness: 1,
            accentStrength: 0.54,
            shadowStrength: 0
        ),
    ]

    private static func canonicalSeconds(
        for hour: OfficeHour
    ) -> Double {
        let index = OfficeHour.allCases.firstIndex(of: hour) ?? 0
        return Double(index) * 3 * 3_600
    }
}
