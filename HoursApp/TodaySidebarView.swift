import HoursCore
import SwiftUI

struct TodaySidebarView: View {
    @Binding var displayMode: AppDisplayMode
    @Binding var hourSelectionView: HourSelectionViewMode
    @Binding var displayedHour: OfficeHour
    let onOpenOffice: (OfficeHour) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wheelSettledHour = OfficeHour.current()
    @State private var showsMonthDays = false
    @State private var showsSettings = false
    @State private var appeared = false
    @State private var isNavigatingDay = false
    @State private var daySwipeOffset: CGFloat = 0
    @State private var incomingDay: LiturgicalDay?
    @State private var incomingDayOffset = 0

    var body: some View {
        ZStack {
            Color.hoursBackground
                .ignoresSafeArea()

            if displayMode.showsAmbientSky {
                AmbientSkyView(
                    selection: displayedHour
                )
                .ignoresSafeArea()
            }

            if model.isLoading && model.selectedDay == nil {
                ProgressView()
            } else {
                GeometryReader { geometry in
                    if hourSelectionView == .sunDial {
                        sundialLayout(in: geometry)
                    } else {
                        wheelLayout(in: geometry)
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .opacity(appeared ? 1 : 0)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.86))
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home-settings")
                .accessibilityHint("Choose display and hour selection options")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsMonthDays) {
            monthDaysSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showsSettings) {
            HomeSettingsView(
                displayMode: $displayMode,
                hourSelectionView: $hourSelectionView,
                isAtLocalTime: isShowingLocalDate
                    && model.automaticallySelectsCurrentOffice,
                onAutomaticHourSelectionChanged:
                    setAutomaticHourSelection
            )
            .presentationDetents([.large])
            .presentationBackground(Color.hoursBackground)
        }
        .onAppear {
            guard !appeared else { return }
            if model.automaticallySelectsCurrentOffice {
                resetToLocalTime()
            } else {
                wheelSettledHour = model.selectedHour
            }
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
        }
        .onChange(of: hourSelectionView) {
            wheelSettledHour = model.selectedHour
        }
    }

    private var selectedHour: OfficeHour {
        model.selectedHour
    }

    private var selectedHourBinding: Binding<OfficeHour> {
        Binding(
            get: { model.selectedHour },
            set: { hour in
                model.selectedHour = hour
                Task {
                    if model.automaticallySelectsCurrentOffice {
                        await model.selectCurrentOffice()
                    } else {
                        await model.select(hour: hour)
                    }
                }
            }
        )
    }

    private var followsLocalTimeBinding: Binding<Bool> {
        Binding(
            get: { model.automaticallySelectsCurrentOffice },
            set: { model.setAutomaticOfficeSelection($0) }
        )
    }

    private var immediateHourBinding: Binding<OfficeHour> {
        Binding(
            get: { model.selectedHour },
            set: { model.selectedHour = $0 }
        )
    }

    private func sundialLayout(
        in geometry: GeometryProxy
    ) -> some View {
        let contentWidth = min(
            max(0, geometry.size.width - 32),
            620
        )
        let sundialWidth = geometry.size.width
        let idealSundialHeight =
            CanonicalHourSundialView.idealHeight(
                for: sundialWidth
            )
        let availableSundialHeight = max(
            220,
            geometry.size.height
                - geometry.safeAreaInsets.top
                - geometry.safeAreaInsets.bottom
                - 220
        )
        let sundialHeight = max(
            geometry.size.width <= 500
                ? CanonicalHourSundialView.minimumHeight
                : min(
                    idealSundialHeight,
                    availableSundialHeight
                ),
            CanonicalHourSundialView.minimumHeight
        )
        let sundialBottomPadding: CGFloat = 14
        let headerBottomPadding: CGFloat = 34
        let headerRegionHeight = max(
            0,
            geometry.size.height
                - sundialHeight
                - sundialBottomPadding
        )

        return ZStack(alignment: .top) {
            CanonicalHourSundialView(
                selection: selectedHourBinding,
                followsLocalTime: followsLocalTimeBinding,
                showsShadow: AppDisplayMode.showsSundialShadow(
                    in: colorScheme
                ),
                onOpenOffice: { hour in
                    onOpenOffice(hour)
                }
            )
            .frame(
                width: sundialWidth,
                height: sundialHeight
            )
            .padding(.bottom, sundialBottomPadding)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .bottomTrailing
            )

            daySwipeRegion(
                contentWidth: contentWidth,
                containerWidth: geometry.size.width,
                height: headerRegionHeight,
                bottomPadding: headerBottomPadding
            )
        }
        .frame(
            width: geometry.size.width,
            height: geometry.size.height,
            alignment: .top
        )
    }

    private func wheelLayout(
        in geometry: GeometryProxy
    ) -> some View {
        let dialDiameter = min(
            max(0, geometry.size.width * 1.38),
            geometry.size.height * 1.17,
            900
        )
        let dialHeight = CanonicalHourDialView.visibleHeight(
            for: dialDiameter
        )
        let headerWidth = min(
            max(0, geometry.size.width - 32),
            620
        )
        let prayButtonVerticalOffset: CGFloat = -24
        let prayButtonMinimumHeight: CGFloat = 52
        let headerBottomPadding: CGFloat = 18
        let headerRegionHeight = max(
            0,
            geometry.size.height / 2
                + prayButtonVerticalOffset
                - prayButtonMinimumHeight / 2
        )

        return ZStack(alignment: .bottom) {
            CanonicalHourDialView(
                selection: immediateHourBinding,
                followsLocalTime: followsLocalTimeBinding,
                onDisplayedHourChanged: { hour in
                    displayedHour = hour
                },
                onSelectionSettled: { hour in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        wheelSettledHour = hour
                    }
                    Task {
                        if model.automaticallySelectsCurrentOffice {
                            await model.selectCurrentOffice()
                        } else {
                            await model.select(hour: hour)
                        }
                    }
                }
            )
            .frame(
                width: dialDiameter,
                height: dialHeight
            )
            .offset(y: geometry.safeAreaInsets.bottom)
        }
        .frame(
            width: geometry.size.width,
            height: geometry.size.height,
            alignment: .bottom
        )
        .overlay(alignment: .top) {
            daySwipeRegion(
                contentWidth: headerWidth,
                containerWidth: geometry.size.width,
                height: headerRegionHeight,
                bottomPadding: headerBottomPadding
            )
        }
        .overlay {
            prayButton(for: wheelSettledHour)
                .offset(y: prayButtonVerticalOffset)
        }
    }

    private func prayButton(
        for hour: OfficeHour
    ) -> some View {
        Button {
            onOpenOffice(hour)
        } label: {
            HStack(spacing: 7) {
                Text("Pray \(hour.englishTitle)")
                    .font(
                        .custom(
                            "EBGaramond-Regular",
                            size: 23,
                            relativeTo: .title3
                        )
                    )
                    .contentTransition(.opacity)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .foregroundStyle(Color.hoursPrimaryText)
        }
        .buttonStyle(.plain)
        .animation(
            .easeInOut(duration: 0.18),
            value: hour
        )
        .accessibilityLabel(
            "Pray \(hour.englishTitle)"
        )
        .accessibilityIdentifier("pray-selected-hour")
        .accessibilityHint("Opens the selected office")
    }

    private var dayHeader: some View {
        Group {
            if let day = model.selectedDay {
                let observance = model.office?.observance
                dayHeaderLabel(
                    for: day,
                    observance: observance
                )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showsMonthDays = true
                    }
                    .background {
                        Button {
                            showsMonthDays = true
                        } label: {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Offices for this month")
                        .accessibilityValue(
                            headerAccessibilityValue(
                                for: day,
                                observance: observance
                            )
                        )
                        .accessibilityHint(
                            "Shows the feast days and classes for this month"
                        )
                        .accessibilityIdentifier("home-month-days")
                    }
            }
        }
        .frame(maxWidth: 620)
        .accessibilityHint(
            "Swipe left for the next day or right for the previous day"
        )
    }

    private func dayHeaderLabel(
        for day: LiturgicalDay,
        observance: OfficeObservance?
    ) -> some View {
        VStack(spacing: 12) {
            if let rank = observance?.rank ?? day.rank {
                Text(rank.displayName)
                    .font(
                        .custom(
                            "EBGaramond-Regular",
                            size: 18,
                            relativeTo: .body
                        )
                    )
                    .foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
                    .accessibilityIdentifier("liturgical-rank")
            }

            Text(observance?.titleLatin ?? day.titleLatin)
                .font(
                    .custom(
                        "EBGaramond-Regular",
                        size: 31,
                        relativeTo: .largeTitle
                    )
                )
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("liturgical-title")

            Text(
                headerDetail(
                    for: day,
                    observance: observance
                )
            )
                .font(
                    .custom(
                        "EBGaramond-Regular",
                        size: 15,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(
                    "liturgical-date-detail"
                )
        }
    }

    private func headerAccessibilityValue(
        for day: LiturgicalDay,
        observance: OfficeObservance?
    ) -> String {
        return [
            (observance?.rank ?? day.rank)?.displayName,
            observance?.titleLatin ?? day.titleLatin,
            headerDetail(
                for: day,
                observance: observance
            ),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private var monthDaysSheet: some View {
        return MonthOfficeDaysSheet(
            days: model.availableDays,
            selection: Binding(
                get: { model.selectedCivilDate },
                set: { civilDate in
                    model.selectedCivilDate = civilDate
                    Task {
                        await model.select(
                            civilDate: civilDate
                        )
                    }
                }
            ),
            availableRange: dateRange
        ) {
            showsMonthDays = false
        }
    }

    private func daySwipeRegion(
        contentWidth: CGFloat,
        containerWidth: CGFloat,
        height: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        ZStack(alignment: .bottom) {
            dayHeader
                .frame(width: contentWidth)
                .offset(x: daySwipeOffset)

            if let incomingDay {
                dayHeaderLabel(
                    for: incomingDay,
                    observance: nil
                )
                .frame(width: contentWidth)
                .offset(
                    x: daySwipeOffset
                        + CGFloat(incomingDayOffset)
                            * containerWidth
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .padding(.bottom, bottomPadding)
        .frame(
            width: containerWidth,
            height: height,
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            daySwipeGesture(containerWidth: containerWidth)
        )
        .clipped()
    }

    private var isShowingLocalDate: Bool {
        LocalDay(model.selectedCivilDate)
            == LocalDay.currentOfficeDay()
    }

    private func headerDetail(
        for day: LiturgicalDay,
        observance: OfficeObservance?
    ) -> String {
        let date = (day.date.date ?? model.selectedCivilDate).formatted(
            .dateTime.weekday(.wide).month(.wide).day().year()
        )
        let commemorations = observance?.commemorations
            ?? day.commemorations
        guard !commemorations.isEmpty else { return date }
        return "\(date) · \(commemorations.map(\.titleLatin).joined(separator: " · "))"
    }

    private func resetToLocalTime() {
        let now = Date()
        let currentHour = OfficeHour.current(at: now)
        model.setAutomaticOfficeSelection(true)

        withAnimation(.easeInOut(duration: 0.72)) {
            model.selectedHour = currentHour
            wheelSettledHour = model.selectedHour
        }

        Task {
            await model.selectCurrentOffice(at: now)
        }
    }

    private func setAutomaticHourSelection(_ isEnabled: Bool) {
        guard !isEnabled else {
            resetToLocalTime()
            return
        }

        model.setAutomaticOfficeSelection(false)
    }

    private func daySwipeGesture(
        containerWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isNavigatingDay else { return }

                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) > abs(verticalDistance) else {
                    return
                }

                let dayOffset = horizontalDistance < 0 ? 1 : -1
                if let targetDay = targetDay(by: dayOffset) {
                    incomingDay = targetDay
                    incomingDayOffset = dayOffset
                    daySwipeOffset = horizontalDistance
                } else {
                    incomingDay = nil
                    incomingDayOffset = 0
                    daySwipeOffset = horizontalDistance * 0.22
                }
            }
            .onEnded { value in
                guard !isNavigatingDay else { return }

                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                let threshold = min(
                    max(containerWidth * 0.18, 64),
                    112
                )

                guard abs(horizontalDistance) >= threshold,
                      abs(horizontalDistance) > abs(verticalDistance) else {
                    snapDayHeaderToCenter()
                    return
                }

                let dayOffset = horizontalDistance < 0 ? 1 : -1
                guard let targetDay = targetDay(by: dayOffset),
                      let targetDate = targetDay.date.date else {
                    snapDayHeaderToCenter()
                    return
                }

                incomingDay = targetDay
                incomingDayOffset = dayOffset
                navigateDay(
                    to: targetDate,
                    dayOffset: dayOffset,
                    containerWidth: containerWidth
                )
            }
    }

    private func targetDay(by offset: Int) -> LiturgicalDay? {
        guard let selectedDay = model.selectedDay,
              let selectedIndex = model.availableDays.firstIndex(
                  where: { $0.date == selectedDay.date }
              ),
              model.availableDays.indices.contains(selectedIndex + offset) else {
            return nil
        }
        return model.availableDays[selectedIndex + offset]
    }

    private func snapDayHeaderToCenter() {
        guard !reduceMotion else {
            daySwipeOffset = 0
            incomingDay = nil
            incomingDayOffset = 0
            return
        }

        withAnimation(
            .spring(
                response: 0.42,
                dampingFraction: 0.58
            ),
            completionCriteria: .logicallyComplete
        ) {
            daySwipeOffset = 0
        } completion: {
            guard daySwipeOffset == 0 else { return }
            incomingDay = nil
            incomingDayOffset = 0
        }
    }

    private func navigateDay(
        to targetDate: Date,
        dayOffset: Int,
        containerWidth: CGFloat
    ) {
        guard !isNavigatingDay else { return }
        isNavigatingDay = true

        guard !reduceMotion else {
            daySwipeOffset = 0
            incomingDay = nil
            incomingDayOffset = 0
            Task {
                await model.select(civilDate: targetDate)
                isNavigatingDay = false
            }
            return
        }

        let offscreenOffset =
            -CGFloat(dayOffset) * containerWidth
        withAnimation(
            .spring(
                response: 0.46,
                dampingFraction: 0.68
            ),
            completionCriteria: .logicallyComplete
        ) {
            daySwipeOffset = offscreenOffset
        } completion: {
            Task {
                await model.select(civilDate: targetDate)

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    daySwipeOffset = 0
                    incomingDay = nil
                    incomingDayOffset = 0
                    isNavigatingDay = false
                }
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        guard let first = model.availableDays.first?.date.date,
              let last = model.availableDays.last?.date.date else {
            let today = LocalDay.currentOfficeDay().date
                ?? Calendar.hoursGregorian.startOfDay(for: Date())
            return today...today
        }
        return first...last
    }
}

struct AmbientSkyView: View {
    let selection: OfficeHour

    var body: some View {
        GeometryReader { geometry in
            let sky = SundialTimeMath.displayedAmbientSky(
                for: selection
            )
            let accentHeight = min(
                320,
                max(200, geometry.size.height * 0.34)
            )
            let upperColor = Color(
                red: sky.upperRed,
                green: sky.upperGreen,
                blue: sky.upperBlue
            )
            let lowerColor = Color(
                red: sky.lowerRed,
                green: sky.lowerGreen,
                blue: sky.lowerBlue
            )
            let backgroundColor = Color(
                red: sky.backgroundRed,
                green: sky.backgroundGreen,
                blue: sky.backgroundBlue
            )
            let accentOpacity = 0.18 * sky.accentStrength
            let nightOpacity = 0.08 * sky.darkness

            ZStack(alignment: .top) {
                backgroundColor

                Color(
                    red: 0.035,
                    green: 0.055,
                    blue: 0.13
                )
                .opacity(nightOpacity)

                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: upperColor.opacity(
                                        accentOpacity
                                    ),
                                    location: 0
                                ),
                                .init(
                                    color: lowerColor.opacity(
                                        accentOpacity * 0.72
                                    ),
                                    location: 0.34
                                ),
                                .init(
                                    color: lowerColor.opacity(
                                        accentOpacity * 0.18
                                    ),
                                    location: 0.7
                                ),
                                .init(
                                    color: .clear,
                                    location: 1
                                ),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: accentHeight)
                    .blur(radius: 18)
                    .frame(
                        maxHeight: .infinity,
                        alignment: .top
                    )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .animation(
                .easeInOut(duration: 0.72),
                value: sky
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
