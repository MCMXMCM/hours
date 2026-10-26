import HoursCore
import SwiftUI

struct OfficeCalendarView: View {
    @Binding var selection: Date
    let availableRange: ClosedRange<Date>
    let onClose: () -> Void

    @State private var displayedMonth: Date
    @Environment(AppTourCoordinator.self) private var tour

    private let isNavigationEmbedded: Bool
    private let calendar: Calendar
    private let today: Date
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    init(
        selection: Binding<Date>,
        in availableRange: ClosedRange<Date>,
        today: Date = Date(),
        isNavigationEmbedded: Bool = false,
        onClose: @escaping () -> Void
    ) {
        let calendar = Calendar.hoursGregorian
        let normalizedToday = calendar.startOfDay(for: today)

        _selection = selection
        self.availableRange = availableRange
        self.onClose = onClose
        self.isNavigationEmbedded = isNavigationEmbedded
        self.calendar = calendar
        self.today = normalizedToday
        _displayedMonth = State(
            initialValue: OfficeCalendarMath.startOfMonth(
                containing: selection.wrappedValue,
                calendar: calendar
            )
        )
    }

    var body: some View {
        Group {
            if isNavigationEmbedded {
                calendarContent
            } else {
                NavigationStack {
                    calendarContent
                }
            }
        }
        .onAppear {
            displayedMonth = OfficeCalendarMath.startOfMonth(
                containing: selection,
                calendar: calendar
            )
            tour.receive(.calendarGridOpened)
        }
    }

    private var calendarContent: some View {
        VStack(spacing: 10) {
            monthHeader
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(daySlots.indices, id: \.self) { index in
                    if let date = daySlots[index] {
                        dayButton(for: date)
                    } else {
                        Color.clear
                            .frame(height: 40)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("office-date-picker")
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isShowingCurrentMonth {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today", action: returnToToday)
                        .disabled(!isAvailable(today))
                        .accessibilityIdentifier("calendar-today")
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                SheetCloseButton(
                    accessibilityLabel: "Close Calendar",
                    accessibilityIdentifier: "office-calendar-close",
                    appTourTarget: .calendarClose,
                    action: onClose
                )
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            monthNavigationButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous month",
                identifier: "calendar-previous-month",
                offset: -1
            )

            Spacer()

            Text(
                displayedMonth.formatted(
                    .dateTime.month(.wide).year()
                )
            )
            .font(.headline)
            .accessibilityIdentifier("calendar-visible-month")

            Spacer()

            monthNavigationButton(
                systemImage: "chevron.right",
                accessibilityLabel: "Next month",
                identifier: "calendar-next-month",
                offset: 1
            )
        }
        .frame(minHeight: 38)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(
                Array(weekdaySymbols.enumerated()),
                id: \.offset
            ) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func monthNavigationButton(
        systemImage: String,
        accessibilityLabel: String,
        identifier: String,
        offset: Int
    ) -> some View {
        let target = month(byAdding: offset)
        let canNavigate = target.map(canDisplay) ?? false

        return Button {
            guard let target else { return }
            displayedMonth = target
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.hoursPrimaryText)
        .disabled(!canNavigate)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private func dayButton(for date: Date) -> some View {
        let isSelected = calendar.isDate(
            date,
            inSameDayAs: selection
        )
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let isEnabled = isAvailable(date)

        return Button {
            selection = date
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.hoursPrimaryText)
                        .padding(2)
                }

                if isToday {
                    Circle()
                        .stroke(
                            Color.hoursTodayAccent,
                            lineWidth: isSelected ? 3 : 2
                        )
                        .padding(isSelected ? 0 : 2)
                }

                Text(
                    date.formatted(
                        .dateTime.day()
                    )
                )
                .font(.body.monospacedDigit())
                .foregroundStyle(
                    dayForegroundColor(
                        isSelected: isSelected,
                        isToday: isToday,
                        isEnabled: isEnabled
                    )
                )
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(
            date.formatted(
                .dateTime.weekday(.wide).month(.wide).day().year()
            )
        )
        .accessibilityValue(
            accessibilityValue(
                isSelected: isSelected,
                isToday: isToday
            )
        )
        .accessibilityIdentifier(
            isToday
                ? "office-calendar-today"
                : "office-calendar-day-\(LocalDay(date))"
        )
    }

    private var daySlots: [Date?] {
        OfficeCalendarMath.daySlots(
            in: displayedMonth,
            calendar: calendar
        )
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var isShowingCurrentMonth: Bool {
        OfficeCalendarMath.isSameMonth(
            displayedMonth,
            as: today,
            calendar: calendar
        )
    }

    private func month(byAdding offset: Int) -> Date? {
        calendar.date(
            byAdding: .month,
            value: offset,
            to: displayedMonth
        )
    }

    private func canDisplay(_ month: Date) -> Bool {
        OfficeCalendarMath.month(
            month,
            intersects: availableRange,
            calendar: calendar
        )
    }

    private func isAvailable(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        let lowerBound = calendar.startOfDay(
            for: availableRange.lowerBound
        )
        let upperBound = calendar.startOfDay(
            for: availableRange.upperBound
        )
        return (lowerBound...upperBound).contains(day)
    }

    private func returnToToday() {
        guard isAvailable(today) else { return }

        displayedMonth = OfficeCalendarMath.startOfMonth(
            containing: today,
            calendar: calendar
        )
        selection = today
    }

    private func dayForegroundColor(
        isSelected: Bool,
        isToday: Bool,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled else { return Color.secondary.opacity(0.35) }
        if isSelected { return Color.hoursBackground }
        if isToday { return Color.hoursTodayAccent }
        return Color.hoursPrimaryText
    }

    private func accessibilityValue(
        isSelected: Bool,
        isToday: Bool
    ) -> String {
        switch (isSelected, isToday) {
        case (true, true):
            "Selected, Today"
        case (true, false):
            "Selected"
        case (false, true):
            "Today"
        case (false, false):
            ""
        }
    }
}

enum OfficeCalendarMath {
    static func startOfMonth(
        containing date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func isSameMonth(
        _ lhs: Date,
        as rhs: Date,
        calendar: Calendar
    ) -> Bool {
        calendar.isDate(
            lhs,
            equalTo: rhs,
            toGranularity: .month
        )
    }

    static func daySlots(
        in month: Date,
        calendar: Calendar
    ) -> [Date?] {
        let monthStart = startOfMonth(
            containing: month,
            calendar: calendar
        )
        let weekday = calendar.component(
            .weekday,
            from: monthStart
        )
        let leadingEmptyDays = (
            weekday - calendar.firstWeekday + 7
        ) % 7
        let dayCount = calendar.range(
            of: .day,
            in: .month,
            for: monthStart
        )?.count ?? 0

        var slots = Array<Date?>(
            repeating: nil,
            count: leadingEmptyDays
        )
        slots.append(
            contentsOf: (0..<dayCount).compactMap { offset in
                calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: monthStart
                )
            }
        )
        while slots.count < 42 {
            slots.append(nil)
        }
        return slots
    }

    static func month(
        _ month: Date,
        intersects range: ClosedRange<Date>,
        calendar: Calendar
    ) -> Bool {
        guard let interval = calendar.dateInterval(
            of: .month,
            for: month
        ),
        let monthEnd = calendar.date(
            byAdding: .day,
            value: -1,
            to: interval.end
        ) else {
            return false
        }

        let lowerBound = calendar.startOfDay(for: range.lowerBound)
        let upperBound = calendar.startOfDay(for: range.upperBound)
        return interval.start <= upperBound && monthEnd >= lowerBound
    }
}
