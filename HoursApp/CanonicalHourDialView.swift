import HoursCore
import SwiftUI

struct CanonicalHourDialView: View {
    @Binding var selection: OfficeHour
    @Binding var followsLocalTime: Bool
    var onDisplayedHourChanged: (OfficeHour) -> Void = { _ in }
    var onSelectionSettled: (OfficeHour) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var mode = Mode.live
    @State private var manualRotation = 0.0
    @State private var dragOrigin: Double?
    @State private var settlementGeneration = 0
    @State private var refreshDate = Date()
    @State private var previewHour: OfficeHour?

    private static let pointerClearance: CGFloat = 64

    static func visibleHeight(for diameter: CGFloat) -> CGFloat {
        diameter / 2 + pointerClearance
    }

    var body: some View {
        let pointerForeground = HourWheelPalette.colors(
            for: HourWheelAppearance(colorScheme: colorScheme)
        ).foreground
        let refreshPolicy = HourDialRefreshPolicy.resolve(
            isSpinning: mode.isSpinning,
            isLive: mode.isLive,
            isSceneActive: scenePhase == .active
        )

        TimelineView(
            .animation(
                minimumInterval:
                    HourDialRefreshPolicy.animationMinimumInterval,
                paused: !refreshPolicy.usesDisplayLink
            )
        ) { context in
            let presentationDate = refreshPolicy.usesDisplayLink
                ? context.date
                : refreshDate

            GeometryReader { proxy in
                let diameter = proxy.size.width
                let liveRotation = mode.isLive
                    ? HourDialMath.liveRotation(at: presentationDate)
                    : 0
                let displayedRotation = rotation(
                    liveRotation: liveRotation,
                    at: presentationDate
                )
                let currentHour = mode.isLive
                    ? OfficeHour.current(at: presentationDate)
                    : displayedSelection
                let displayedHour = mode.isSpinning
                    ? HourDialMath.nearestHour(for: displayedRotation)
                    : displayedSelection
                let spinHasFinished = mode.spin?.hasFinished(
                    at: presentationDate
                ) ?? false

                ZStack(alignment: .top) {
                    dialFace(
                        diameter: diameter,
                        rotation: displayedRotation,
                        selectedHour: displayedHour
                    )
                    .offset(y: Self.pointerClearance)

                    Image("HourDialPointer")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(
                            Color(
                                red: Double(pointerForeground.x),
                                green: Double(pointerForeground.y),
                                blue: Double(pointerForeground.z)
                            )
                        )
                        .aspectRatio(161.36 / 249.77, contentMode: .fit)
                        .frame(width: 40, height: 60)
                        .padding(.top, 3)
                        .shadow(
                            color: .black.opacity(0.7),
                            radius: 2,
                            y: 1
                        )
                }
                .frame(
                    width: diameter,
                    height: Self.visibleHeight(for: diameter),
                    alignment: .top
                )
                .contentShape(Rectangle())
                .clipped()
                .highPriorityGesture(
                    dragGesture(
                        diameter: diameter,
                        displayedRotation: displayedRotation
                    )
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Canonical hours")
                .accessibilityIdentifier("canonical-hour-dial")
                .accessibilityHint(
                    "Swipe the dial or choose an hour, then use the Pray button."
                )
                .accessibilityAdjustableAction { direction in
                    adjust(
                        direction,
                        from: displayedRotation
                    )
                }
                .onChange(of: currentHour) { _, newHour in
                    guard mode.isLive else { return }
                    commitSelection(newHour)
                }
                .onChange(
                    of: displayedHour,
                    initial: true
                ) { _, newHour in
                    if mode.isSpinning {
                        previewHour = newHour
                    }
                    onDisplayedHourChanged(newHour)
                }
                .onChange(of: spinHasFinished) { _, hasFinished in
                    guard hasFinished else { return }
                    finishSpin()
                }
            }
        }
        .task(id: refreshPolicy) {
            await runRefreshLoop(for: refreshPolicy)
        }
        .sensoryFeedback(.selection, trigger: displayedSelection)
        .onAppear {
            if followsLocalTime {
                resumeLiveTime()
            } else {
                showManualSelection()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, followsLocalTime else { return }
            resumeLiveTime()
        }
        .onChange(of: followsLocalTime) { _, followsLocalTime in
            if followsLocalTime {
                guard !mode.isLive else { return }
                resumeLiveTime()
            } else if mode.isLive {
                showManualSelection()
            }
        }
    }

    private func runRefreshLoop(
        for policy: HourDialRefreshPolicy
    ) async {
        guard case .periodic(let interval) = policy else { return }

        while !Task.isCancelled {
            refreshDate = Date()

            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
        }
    }

    private func dialFace(
        diameter: CGFloat,
        rotation: Double,
        selectedHour: OfficeHour
    ) -> some View {
        ZStack {
            ProceduralHourWheelView(
                rotationDegrees: rotation,
                selectedHour: selectedHour
            )

            ZStack {
                ForEach(OfficeHour.allCases, id: \.self) { hour in
                    hourButton(
                        hour,
                        diameter: diameter,
                        displayedRotation: rotation,
                        selectedHour: selectedHour
                    )
                }
            }
            .rotationEffect(.degrees(rotation))
        }
        .frame(width: diameter, height: diameter)
    }

    private func hourButton(
        _ hour: OfficeHour,
        diameter: CGFloat,
        displayedRotation: Double,
        selectedHour: OfficeHour
    ) -> some View {
        let sector = HourDialMath.sectorAngleRange(for: hour)
        let labelAngle = HourDialMath.labelAngle(for: hour)
        let angularMargin = min(
            labelAngle - sector.lowerBound,
            sector.upperBound - labelAngle
        )
        let availableRadians = 2 * angularMargin * .pi / 180
        let availableWidth =
            diameter * 0.405 * CGFloat(availableRadians) * 0.78

        return Button {
            select(hour, from: displayedRotation)
        } label: {
            Color.white.opacity(0.001)
                .frame(
                    width: min(
                        diameter * 0.27,
                        max(44, availableWidth)
                    ),
                    height: diameter * 0.105
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: -diameter * 0.405)
        .rotationEffect(
            .degrees(labelAngle)
        )
        .accessibilityLabel(hour.englishTitle)
        .accessibilityValue(
            selectedHour == hour
                ? "Selected, \(hour.customaryTimeRange)"
                : hour.customaryTimeRange
        )
        .accessibilityHint(
            selectedHour == hour
                ? "Selected hour"
                : "Selects and centers this hour"
        )
        .accessibilityIdentifier(
            selectedHour == hour
                ? "hour-\(hour.rawValue)"
                : "hour-option-\(hour.rawValue)"
        )
    }

    private func rotation(
        liveRotation: Double,
        at date: Date
    ) -> Double {
        switch mode {
        case .live:
            if reduceMotion {
                return HourDialMath.targetRotation(
                    for: OfficeHour.current(at: date),
                    near: liveRotation
                )
            }
            return liveRotation
        case .manual:
            return manualRotation
        case .spinning(let spin):
            return spin.rotation(at: date)
        }
    }

    private func dragGesture(
        diameter: CGFloat,
        displayedRotation: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard HourDialDragIntent.shouldRotateWheel(
                    translation: value.translation
                ) else {
                    return
                }

                if dragOrigin == nil {
                    let origin = displayedRotation
                    settlementGeneration &+= 1
                    mode = .manual
                    manualRotation = origin
                    dragOrigin = origin
                }

                guard let dragOrigin else { return }
                manualRotation = dragOrigin + HourDialMath.dragRotation(
                    translation: value.translation.width,
                    diameter: diameter
                )
                previewHour = HourDialMath.nearestHour(
                    for: manualRotation
                )
            }
            .onEnded { value in
                guard let dragOrigin else { return }

                let releasedRotation = dragOrigin + HourDialMath.dragRotation(
                    translation: value.translation.width,
                    diameter: diameter
                )
                let angularVelocity = HourDialMath.angularVelocity(
                    actual: value.translation.width,
                    predicted: value.predictedEndTranslation.width,
                    diameter: diameter
                )

                self.dragOrigin = nil
                // A system gesture can cancel after `onChanged`, such as the
                // swipe used to leave the app. Only a completed wheel drag is
                // an intentional switch from automatic to manual selection.
                followsLocalTime = false
                manualRotation = releasedRotation

                if reduceMotion
                    || abs(angularVelocity) < HourDialMath.minimumCoastVelocity {
                    snap(from: releasedRotation)
                } else {
                    mode = .spinning(
                        InertialSpin(
                            startRotation: releasedRotation,
                            initialVelocity: angularVelocity,
                            startDate: Date()
                        )
                    )
                }
            }
    }

    private func select(
        _ hour: OfficeHour,
        from displayedRotation: Double
    ) {
        followsLocalTime = false
        mode = .manual
        manualRotation = displayedRotation
        previewHour = hour
        let target = HourDialMath.targetRotation(
            for: hour,
            near: displayedRotation
        )
        settle(
            on: hour,
            at: target,
            dampingFraction: 0.76
        )
    }

    private func adjust(
        _ direction: AccessibilityAdjustmentDirection,
        from displayedRotation: Double
    ) {
        let offset: Int
        switch direction {
        case .increment:
            offset = 1
        case .decrement:
            offset = -1
        @unknown default:
            return
        }

        let hours = OfficeHour.allCases
        let currentIndex = hours.firstIndex(of: displayedSelection) ?? 0
        let nextIndex = (currentIndex + offset + hours.count) % hours.count
        let next = hours[nextIndex]

        followsLocalTime = false
        mode = .manual
        manualRotation = displayedRotation
        previewHour = next
        let target = HourDialMath.targetRotation(
            for: next,
            near: displayedRotation
        )
        settle(
            on: next,
            at: target,
            dampingFraction: 0.76
        )
    }

    private func finishSpin() {
        guard let spin = mode.spin else { return }
        snap(from: spin.endRotation)
    }

    private func snap(from rotation: Double) {
        let target = HourDialMath.nearestDetent(to: rotation)
        mode = .manual
        manualRotation = rotation
        let hour = HourDialMath.nearestHour(for: target)
        previewHour = hour
        settle(
            on: hour,
            at: target,
            dampingFraction: 0.72
        )
    }

    private func settle(
        on hour: OfficeHour,
        at targetRotation: Double,
        dampingFraction: Double
    ) {
        settlementGeneration &+= 1
        let generation = settlementGeneration

        guard !reduceMotion else {
            manualRotation = targetRotation
            commitSelection(hour)
            return
        }

        withAnimation(
            .spring(
                response: 0.48,
                dampingFraction: dampingFraction
            ),
            completionCriteria: .logicallyComplete
        ) {
            manualRotation = targetRotation
        } completion: {
            guard settlementGeneration == generation else { return }
            commitSelection(hour)
        }
    }

    private func resumeLiveTime() {
        settlementGeneration &+= 1
        dragOrigin = nil
        previewHour = nil
        mode = .live
        let currentHour = OfficeHour.current()
        followsLocalTime = true
        commitSelection(currentHour)
    }

    private func showManualSelection() {
        settlementGeneration &+= 1
        dragOrigin = nil
        previewHour = nil
        mode = .manual
        manualRotation = HourDialMath.targetRotation(
            for: selection,
            near: HourDialMath.liveRotation(at: Date())
        )
    }

    private var displayedSelection: OfficeHour {
        previewHour ?? selection
    }

    private func commitSelection(_ hour: OfficeHour) {
        previewHour = nil
        if selection != hour {
            selection = hour
        }
        onSelectionSettled(hour)
    }

    private enum Mode {
        case live
        case manual
        case spinning(InertialSpin)

        var spin: InertialSpin? {
            guard case .spinning(let spin) = self else { return nil }
            return spin
        }

        var isSpinning: Bool {
            spin != nil
        }

        var isLive: Bool {
            guard case .live = self else { return false }
            return true
        }
    }

    private struct InertialSpin {
        let startRotation: Double
        let initialVelocity: Double
        let startDate: Date
        let duration: TimeInterval

        init(
            startRotation: Double,
            initialVelocity: Double,
            startDate: Date
        ) {
            self.startRotation = startRotation
            self.initialVelocity = initialVelocity
            self.startDate = startDate
            duration = HourDialMath.coastDuration(
                for: initialVelocity
            )
        }

        var endRotation: Double {
            HourDialMath.coastRotation(
                start: startRotation,
                initialVelocity: initialVelocity,
                elapsed: duration,
                duration: duration
            )
        }

        func rotation(at date: Date) -> Double {
            HourDialMath.coastRotation(
                start: startRotation,
                initialVelocity: initialVelocity,
                elapsed: date.timeIntervalSince(startDate),
                duration: duration
            )
        }

        func hasFinished(at date: Date) -> Bool {
            date.timeIntervalSince(startDate) >= duration
        }
    }
}

nonisolated enum HourDialDragIntent {
    static func shouldRotateWheel(translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }
}

nonisolated enum HourDialRefreshPolicy: Hashable {
    case displayLink
    case periodic(TimeInterval)
    case stationary

    static let animationMinimumInterval = 1.0 / 120.0
    static let liveInterval: TimeInterval = 15

    static func resolve(
        isSpinning: Bool,
        isLive: Bool,
        isSceneActive: Bool
    ) -> Self {
        guard isSceneActive else { return .stationary }
        if isSpinning {
            return .displayLink
        }
        if isLive {
            return .periodic(liveInterval)
        }
        return .stationary
    }

    var usesDisplayLink: Bool {
        self == .displayLink
    }
}

enum HourDialMath {
    static let minimumCoastVelocity = 40.0
    static let sectors: [HourDialSector] = [
        HourDialSector(
            hour: .matins,
            angleRange: 0...60,
            textureAssetName: "MatutinumTexture"
        ),
        HourDialSector(
            hour: .lauds,
            angleRange: 60...90,
            textureAssetName: "LaudesTexture"
        ),
        HourDialSector(
            hour: .prime,
            angleRange: 90...120,
            textureAssetName: "PrimaTexture"
        ),
        HourDialSector(
            hour: .terce,
            angleRange: 120...150,
            textureAssetName: "TertiaTexture"
        ),
        HourDialSector(
            hour: .sext,
            angleRange: 150...195,
            textureAssetName: "SextaTexture"
        ),
        HourDialSector(
            hour: .none,
            angleRange: 195...240,
            textureAssetName: "NonaTexture"
        ),
        HourDialSector(
            hour: .vespers,
            angleRange: 240...300,
            textureAssetName: "VesperaeTexture"
        ),
        HourDialSector(
            hour: .compline,
            angleRange: 300...360,
            textureAssetName: "CompletoriumTexture"
        ),
    ]
    private static let sectorByHour = Dictionary(
        uniqueKeysWithValues: sectors.map { ($0.hour, $0) }
    )

    static func labelAngle(for hour: OfficeHour) -> Double {
        let range = sectorAngleRange(for: hour)
        return (range.lowerBound + range.upperBound) / 2
    }

    static func liveRotation(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Double {
        let components = calendar.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        let seconds = Double(components.hour ?? 0) * 3_600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
        return -(seconds / (24 * 60 * 60) * 360)
    }

    static func sectorAngleRange(
        for hour: OfficeHour
    ) -> ClosedRange<Double> {
        sectorByHour[hour]?.angleRange ?? -30...30
    }

    static func nearestHour(for rotation: Double) -> OfficeHour {
        let dialAngle = -rotation
        var nearestHour = OfficeHour.matins
        var nearestDistance = Double.infinity
        var containingHour: OfficeHour?
        var containingDistance = Double.infinity

        for hour in OfficeHour.allCases {
            let target = targetRotation(for: hour, near: rotation)
            let distance = abs(target - rotation)
            if distance < nearestDistance {
                nearestHour = hour
                nearestDistance = distance
            }

            let center = labelAngle(for: hour)
            let revolutions = ((center - dialAngle) / 360).rounded()
            let adjustedAngle = dialAngle + revolutions * 360
            if sectorAngleRange(for: hour).contains(adjustedAngle),
               distance < containingDistance {
                containingHour = hour
                containingDistance = distance
            }
        }

        return containingHour ?? nearestHour
    }

    static func nearestDetent(to rotation: Double) -> Double {
        let hour = nearestHour(for: rotation)
        return targetRotation(for: hour, near: rotation)
    }

    static func targetRotation(
        for hour: OfficeHour,
        near reference: Double
    ) -> Double {
        let canonical = -labelAngle(for: hour)
        let revolutions = ((reference - canonical) / 360).rounded()
        return canonical + revolutions * 360
    }

    static func dragRotation(
        translation: CGFloat,
        diameter: CGFloat
    ) -> Double {
        guard diameter > 0 else { return 0 }
        return Double(translation / diameter) * (360 / .pi)
    }

    static func angularVelocity(
        actual: CGFloat,
        predicted: CGFloat,
        diameter: CGFloat
    ) -> Double {
        let predictedExtra = predicted - actual
        let predictedHorizon = 0.22
        let velocity = dragRotation(
            translation: predictedExtra,
            diameter: diameter
        ) / predictedHorizon
        return min(max(velocity, -420), 420)
    }

    static func coastDuration(for initialVelocity: Double) -> TimeInterval {
        min(
            max(abs(initialVelocity) / 170, 0.6),
            2.8
        )
    }

    static func coastRotation(
        start: Double,
        initialVelocity: Double,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return start }
        let time = min(max(elapsed, 0), duration)
        let progress = time / duration
        let distance = initialVelocity
            * duration
            * (progress - 0.5 * progress * progress)
        return start + distance
    }
}

struct HourDialSector: Equatable {
    let hour: OfficeHour
    let angleRange: ClosedRange<Double>
    let textureAssetName: String
}
