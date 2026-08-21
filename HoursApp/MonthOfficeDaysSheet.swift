import HoursCore
import SwiftUI

struct MonthOfficeDaysSheet: View {
    let days: [LiturgicalDay]
    @Binding var selection: Date
    let availableRange: ClosedRange<Date>
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppTourCoordinator.self) private var tour
    @State private var displayedMonth: Date
    @State private var monthTransition: MonthNavigationDirection?
    @State private var scrollEdges = MonthScrollEdges()
    @State private var dragStartEdges: MonthScrollEdges?
    @State private var isListGestureActive = false

    private let calendar = Calendar.hoursGregorian
    private static let monthOverscrollThreshold: CGFloat = 64

    init(
        days: [LiturgicalDay],
        selection: Binding<Date>,
        availableRange: ClosedRange<Date>,
        onClose: @escaping () -> Void
    ) {
        let calendar = Calendar.hoursGregorian
        self.days = days
        _selection = selection
        self.availableRange = availableRange
        self.onClose = onClose
        _displayedMonth = State(
            initialValue: OfficeCalendarMath.startOfMonth(
                containing: selection.wrappedValue,
                calendar: calendar
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    List {
                        scrollPadding(
                            for: geometry.size.height
                        )

                        ForEach(monthDays) { day in
                            dayButton(day)
                                .id(day.date)
                        }

                        scrollPadding(
                            for: geometry.size.height
                        )
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("month-days-list")
                    .accessibilityHint(
                        "Pull past the top or bottom to move between months"
                    )
                    .onScrollGeometryChange(
                        for: MonthScrollEdges.self
                    ) { geometry in
                        MonthScrollEdges(
                            isAtTop:
                                geometry.visibleRect.minY <= 1,
                            isAtBottom:
                                geometry.visibleRect.maxY
                                    >= geometry.contentSize.height - 1
                        )
                    } action: { _, newEdges in
                        scrollEdges = newEdges
                    }
                    .simultaneousGesture(monthOverscrollGesture)
                    .task(id: displayedMonth) {
                        await Task.yield()
                        try? await Task.sleep(
                            for: .milliseconds(120)
                        )
                        if monthDays.contains(
                            where: { $0.date == selectedLocalDay }
                        ) {
                            proxy.scrollTo(
                                selectedLocalDay,
                                anchor: .center
                            )
                        } else if monthTransition == .previous,
                                  let lastDay = monthDays.last {
                            proxy.scrollTo(
                                lastDay.date,
                                anchor: .bottom
                            )
                        } else if let firstDay = monthDays.first {
                            proxy.scrollTo(
                                firstDay.date,
                                anchor: .top
                            )
                        }
                        monthTransition = nil
                    }
                }
            }
            .navigationTitle(monthTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(monthTitle)
                        .font(.headline)
                        .accessibilityIdentifier(
                            "month-days-visible-month"
                        )
                }

                ToolbarItem(placement: .cancellationAction) {
                    NavigationLink {
                        OfficeCalendarView(
                            selection: $selection,
                            in: availableRange,
                            isNavigationEmbedded: true,
                            onClose: onClose
                        )
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Calendar")
                    .accessibilityHint(
                        "Opens the calendar to choose another month or day"
                    )
                    .accessibilityIdentifier("month-days-calendar")
                    .appTourTarget(.calendarIcon)
                }

                ToolbarItem(placement: .confirmationAction) {
                    SheetCloseButton(
                        accessibilityLabel: "Close Calendar",
                        accessibilityIdentifier: "month-days-close",
                        action: onClose
                    )
                }
            }
        }
        .onChange(of: selection) {
            monthTransition = nil
            displayedMonth = OfficeCalendarMath.startOfMonth(
                containing: selection,
                calendar: calendar
            )
        }
        .interactiveDismissDisabled(isListGestureActive)
        .accessibilityIdentifier("month-days-sheet")
    }

    private var selectedLocalDay: LocalDay {
        LocalDay(selection, calendar: calendar)
    }

    private var monthDays: [LiturgicalDay] {
        MonthOfficeDays.days(
            containing: displayedMonth,
            from: days,
            calendar: calendar
        )
    }

    private var monthTitle: String {
        displayedMonth.formatted(
            .dateTime.month(.wide).year()
        )
    }

    private func adjacentMonth(
        byAdding offset: Int
    ) -> Date? {
        guard let month = calendar.date(
            byAdding: .month,
            value: offset,
            to: displayedMonth
        ),
        !MonthOfficeDays.days(
            containing: month,
            from: days,
            calendar: calendar
        ).isEmpty else {
            return nil
        }
        return month
    }

    private var monthOverscrollGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { _ in
                isListGestureActive = true
                if dragStartEdges == nil {
                    dragStartEdges = scrollEdges
                }
            }
            .onEnded { value in
                defer {
                    dragStartEdges = nil
                    releaseListGestureProtection()
                }
                guard let dragStartEdges else { return }

                if dragStartEdges.isAtBottom,
                   value.translation.height
                    <= -Self.monthOverscrollThreshold {
                    navigateMonth(.next)
                } else if dragStartEdges.isAtTop,
                          value.translation.height
                            >= Self.monthOverscrollThreshold {
                    navigateMonth(.previous)
                }
            }
    }

    private func releaseListGestureProtection() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            isListGestureActive = false
        }
    }

    private func navigateMonth(
        _ direction: MonthNavigationDirection
    ) {
        let offset = direction == .next ? 1 : -1
        guard let month = adjacentMonth(
            byAdding: offset
        ) else {
            return
        }
        monthTransition = direction
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = month
        }
        if direction == .next {
            tour.receive(.calendarMonthAdvanced)
        }
    }

    private func dayButton(
        _ day: LiturgicalDay
    ) -> some View {
        let isSelected = day.date == selectedLocalDay
        let isToday = day.date == todayLocalDay
        return Button {
            guard let date = day.date.date(in: calendar) else {
                return
            }
            selection = date
            onClose()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 1) {
                    Text(
                        date(for: day).formatted(
                            .dateTime.weekday(.abbreviated)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        dayMarkerForeground(
                            isSelected: isSelected,
                            isToday: isToday,
                            defaultColor: .secondary
                        )
                    )

                    Text("\(day.date.day)")
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(
                            dayMarkerForeground(
                                isSelected: isSelected,
                                isToday: isToday,
                                defaultColor: .hoursPrimaryText
                            )
                        )
                }
                .frame(width: 46, height: 46)
                .background {
                    if isToday {
                        Rectangle()
                            .fill(hourWheelTimeRingFill)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let rank = day.rank {
                        Text(rank.displayName)
                            .font(
                                .custom(
                                    "EBGaramond-Regular",
                                    size: 15,
                                    relativeTo: .caption
                                )
                            )
                            .foregroundStyle(
                                isSelected
                                    ? Color.hoursTodayAccent
                                    : Color.secondary
                            )
                    }

                    Text(day.titleLatin)
                        .font(
                            .custom(
                                "EBGaramond-Regular",
                                size: 21,
                                relativeTo: .body
                            )
                        )
                        .foregroundStyle(Color.hoursPrimaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 54,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityLabel(accessibilityLabel(for: day))
        .accessibilityValue(
            accessibilityValue(
                isSelected: isSelected,
                isToday: isToday
            )
        )
        .accessibilityHint("Selects this office date")
        .accessibilityIdentifier("month-day-\(day.date)")
    }

    private func scrollPadding(
        for availableHeight: CGFloat
    ) -> some View {
        Color.clear
            .frame(height: max(0, availableHeight / 2 - 44))
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
    }

    private func date(for day: LiturgicalDay) -> Date {
        day.date.date(in: calendar) ?? selection
    }

    private var todayLocalDay: LocalDay {
        LocalDay(Date(), calendar: calendar)
    }

    private var hourWheelPalette: HourWheelPalette {
        HourWheelPalette.colors(
            for: HourWheelAppearance(colorScheme: colorScheme)
        )
    }

    private var hourWheelTimeRingFill: Color {
        color(hourWheelPalette.timeRingFill)
    }

    private var hourWheelTimeRingNumeral: Color {
        color(hourWheelPalette.timeRingNumeral)
    }

    private func dayMarkerForeground(
        isSelected: Bool,
        isToday: Bool,
        defaultColor: Color
    ) -> Color {
        if isToday {
            return hourWheelTimeRingNumeral
        }
        if isSelected {
            return .hoursTodayAccent
        }
        return defaultColor
    }

    private func color(
        _ components: SIMD3<Float>
    ) -> Color {
        Color(
            red: Double(components.x),
            green: Double(components.y),
            blue: Double(components.z)
        )
    }

    private func accessibilityValue(
        isSelected: Bool,
        isToday: Bool
    ) -> String {
        [
            isSelected ? "Selected" : nil,
            isToday ? "Today" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func accessibilityLabel(
        for day: LiturgicalDay
    ) -> String {
        [
            date(for: day).formatted(
                .dateTime.weekday(.wide).month(.wide).day()
            ),
            day.rank?.displayName,
            day.titleLatin,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct MonthScrollEdges: Equatable {
    var isAtTop = false
    var isAtBottom = false
}

private enum MonthNavigationDirection {
    case previous
    case next
}

enum MonthOfficeDays {
    static func days(
        containing selection: Date,
        from days: [LiturgicalDay],
        calendar: Calendar = .hoursGregorian
    ) -> [LiturgicalDay] {
        days.filter { day in
            guard let date = day.date.date(in: calendar) else {
                return false
            }
            return calendar.isDate(
                date,
                equalTo: selection,
                toGranularity: .month
            )
        }
    }
}
