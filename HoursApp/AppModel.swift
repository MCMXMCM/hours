import Foundation
import HoursCore
import Observation

@MainActor
@Observable
final class AppModel {
    static let defaultNotationScale = 1.0
    static let automaticOfficeSelectionKey =
        "automaticOfficeSelectionEnabled"
    static let manuallySelectedHourKey = "manuallySelectedOfficeHour"

    private(set) var availableDays: [LiturgicalDay] = []
    private(set) var selectedDay: LiturgicalDay?
    private(set) var office: OfficeDocument?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var selectedHour: OfficeHour {
        didSet {
            guard !automaticallySelectsCurrentOffice else { return }
            userDefaults.set(
                selectedHour.rawValue,
                forKey: Self.manuallySelectedHourKey
            )
        }
    }
    private(set) var automaticallySelectsCurrentOffice: Bool
    var selectedCivilDate = Date()
    var showsEnglish = false
    var notationScale = AppModel.defaultNotationScale
    var isPriestOrDeaconPresent = false

    private var repository: (any ContentRepository)?
    @ObservationIgnored
    private let userDefaults: UserDefaults
    private var hasStarted = false
    private var selectionGeneration = 0
    @ObservationIgnored
    private var selectionTask: Task<SelectionPayload, Error>?
    @ObservationIgnored
    private var selectionTaskKey: SelectionKey?

    init(
        repository: (any ContentRepository)? = nil,
        userDefaults: UserDefaults = .standard,
        date: Date = Date()
    ) {
        self.repository = repository
        self.userDefaults = userDefaults

        let automaticSelectionEnabled: Bool
        if userDefaults.object(
            forKey: Self.automaticOfficeSelectionKey
        ) == nil {
            automaticSelectionEnabled = true
        } else {
            automaticSelectionEnabled = userDefaults.bool(
                forKey: Self.automaticOfficeSelectionKey
            )
        }
        automaticallySelectsCurrentOffice = automaticSelectionEnabled

        if !automaticSelectionEnabled,
           let rawHour = userDefaults.string(
               forKey: Self.manuallySelectedHourKey
           ),
           let savedHour = OfficeHour(rawValue: rawHour) {
            selectedHour = savedHour
        } else {
            selectedHour = .current(at: date)
        }
    }

    var isDevelopmentCorpus: Bool {
        office?.format == .legacyReconstructed
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        defer { isLoading = false }

        do {
            guard let databaseURL = Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite") else {
                throw ContentRepositoryError.databaseUnavailable("The bundled base corpus is missing.")
            }
            let repository = try SQLiteContentRepository(databaseURL: databaseURL)
            self.repository = repository
            let days = try await repository.availableDays()
            guard let fallback = days.first else {
                throw ContentRepositoryError.databaseUnavailable("The bundled base corpus is empty.")
            }
            availableDays = days

            // Keep automatic Matins on one Office date across midnight,
            // advancing the calendar when Lauds begins at 4 a.m.
            let now = Date()
            let currentHour = OfficeHour.current(at: now)
            let currentDay = LocalDay.currentOfficeDay(at: now)
            let initialHour: OfficeHour
            if automaticallySelectsCurrentOffice {
                selectedHour = currentHour
                initialHour = currentHour
            } else {
                initialHour = selectedHour
            }
            let initial = days.first(where: { $0.date == currentDay }) ?? fallback
            selectedCivilDate = initial.date.date ?? Date()
            await select(day: initial.date, hour: initialHour)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAutomaticOfficeSelection(_ isEnabled: Bool) {
        automaticallySelectsCurrentOffice = isEnabled
        userDefaults.set(
            isEnabled,
            forKey: Self.automaticOfficeSelectionKey
        )

        if !isEnabled {
            userDefaults.set(
                selectedHour.rawValue,
                forKey: Self.manuallySelectedHourKey
            )
        }
    }

    func selectCurrentOffice(
        at date: Date = Date(),
        calendar: Calendar = .hoursGregorian
    ) async {
        guard automaticallySelectsCurrentOffice else { return }

        let hour = OfficeHour.current(at: date, calendar: calendar)
        let day = LocalDay.currentOfficeDay(
            at: date,
            calendar: calendar
        )

        if selectedHour != hour {
            selectedHour = hour
        }
        let officeDate = day.date(in: calendar) ?? date
        if selectedCivilDate != officeDate {
            selectedCivilDate = officeDate
        }
        await select(day: day, hour: hour)
    }

    func select(civilDate: Date) async {
        if selectedCivilDate != civilDate {
            selectedCivilDate = civilDate
        }
        await select(day: LocalDay(civilDate), hour: selectedHour)
    }

    func select(hour: OfficeHour) async {
        if selectedHour != hour {
            selectedHour = hour
        }
        guard let selectedDay else { return }
        await select(day: selectedDay.date, hour: hour)
    }

    func openFirstAvailableDay() async {
        guard let day = availableDays.first else { return }
        let firstDate = day.date.date ?? selectedCivilDate
        if selectedCivilDate != firstDate {
            selectedCivilDate = firstDate
        }
        await select(day: day.date, hour: selectedHour)
    }

    private func select(day: LocalDay, hour: OfficeHour) async {
        guard let repository else { return }

        if selectedDay?.date == day,
           office?.date == day,
           office?.hour == hour {
            if selectionTask != nil {
                selectionGeneration += 1
                selectionTask?.cancel()
                selectionTask = nil
                selectionTaskKey = nil
            }
            isLoading = false
            errorMessage = nil
            return
        }

        selectionGeneration += 1
        let generation = selectionGeneration
        let key = SelectionKey(day: day, hour: hour)
        isLoading = true
        errorMessage = nil

        let task: Task<SelectionPayload, Error>
        if selectionTaskKey == key, let selectionTask {
            task = selectionTask
        } else {
            selectionTask?.cancel()
            let currentDay = selectedDay?.date == day
                ? selectedDay
                : nil
            task = Task {
                try Task.checkCancellation()

                let resolvedDay: LiturgicalDay
                let resolvedOffice: OfficeDocument
                if let currentDay {
                    resolvedDay = currentDay
                    resolvedOffice = try await repository.office(
                        on: day,
                        hour: hour
                    )
                } else {
                    async let dayRequest = repository.day(on: day)
                    async let officeRequest = repository.office(
                        on: day,
                        hour: hour
                    )
                    (resolvedDay, resolvedOffice) = try await (
                        dayRequest,
                        officeRequest
                    )
                }

                try Task.checkCancellation()
                return SelectionPayload(
                    day: resolvedDay,
                    office: resolvedOffice
                )
            }
            selectionTask = task
            selectionTaskKey = key
        }

        do {
            let payload = try await task.value
            guard generation == selectionGeneration else { return }
            selectedDay = payload.day
            office = payload.office
        } catch {
            guard generation == selectionGeneration else { return }
            selectedDay = nil
            office = nil
            errorMessage = error.localizedDescription
        }
        if generation == selectionGeneration {
            isLoading = false
        }
        if selectionTaskKey == key {
            selectionTask = nil
            selectionTaskKey = nil
        }
    }

    private struct SelectionKey: Hashable, Sendable {
        let day: LocalDay
        let hour: OfficeHour
    }

    private struct SelectionPayload: Sendable {
        let day: LiturgicalDay
        let office: OfficeDocument
    }
}
