import Foundation
import HoursCore
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(
        subsystem: "com.matthewmccarty.hours",
        category: "CalendarSnapshot"
    )
    private static let signposter = OSSignposter(
        subsystem: "com.matthewmccarty.hours",
        category: "AppStartup"
    )

    static let defaultNotationScale = 1.0
    static let automaticOfficeSelectionKey =
        "automaticOfficeSelectionEnabled"
    static let manuallySelectedHourKey = "manuallySelectedOfficeHour"
    static let readerIsPresentedKey = "readerRestoration.isPresented"
    static let readerDayKey = "readerRestoration.day"
    static let readerHourKey = "readerRestoration.hour"
    static let readerScrollOffsetKey = "readerRestoration.scrollOffset"
    nonisolated static let showsEnglishKey =
        "prayerOptions.showsEnglish"
    nonisolated static let notationScaleKey =
        "prayerOptions.notationScale"
    nonisolated static let priestOrDeaconPresentKey =
        "prayerOptions.priestOrDeaconPresent"

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
    private(set) var isReaderSessionActive: Bool
    var selectedCivilDate = Date()
    var showsEnglish = false {
        didSet {
            userDefaults.set(
                showsEnglish,
                forKey: Self.showsEnglishKey
            )
        }
    }
    var notationScale = AppModel.defaultNotationScale {
        didSet {
            userDefaults.set(
                notationScale,
                forKey: Self.notationScaleKey
            )
        }
    }
    var isPriestOrDeaconPresent = false {
        didSet {
            userDefaults.set(
                isPriestOrDeaconPresent,
                forKey: Self.priestOrDeaconPresentKey
            )
        }
    }

    private var repository: (any ContentRepository)?
    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private var readerSession: ReaderSession?
    private var hasStarted = false
    private var selectionGeneration = 0
    @ObservationIgnored
    private var selectionTask: Task<SelectionPayload, Error>?
    @ObservationIgnored
    private var selectionTaskKey: SelectionKey?
    @ObservationIgnored
    private var availableDayIndices: [LocalDay: Int] = [:]

    init(
        repository: (any ContentRepository)? = nil,
        userDefaults: UserDefaults = .standard,
        date: Date = Date()
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        showsEnglish = userDefaults.bool(
            forKey: Self.showsEnglishKey
        )
        if userDefaults.object(forKey: Self.notationScaleKey) != nil {
            notationScale = userDefaults.double(
                forKey: Self.notationScaleKey
            )
        }
        isPriestOrDeaconPresent = userDefaults.bool(
            forKey: Self.priestOrDeaconPresentKey
        )

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

        let restoredReaderSession = Self.readerSession(from: userDefaults)
        readerSession = restoredReaderSession
        isReaderSessionActive = restoredReaderSession != nil

        if let restoredReaderSession {
            selectedHour = restoredReaderSession.hour
        } else if !automaticSelectionEnabled,
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

    var appTourState: AppModelTourState {
        AppModelTourState(
            selectedDay: selectedDay?.date
                ?? LocalDay(selectedCivilDate),
            selectedHour: selectedHour,
            automaticallySelectsCurrentOffice:
                automaticallySelectsCurrentOffice,
            reader: readerSession.map {
                AppTourReaderSnapshot(
                    day: $0.day,
                    hour: $0.hour,
                    scrollOffset: $0.scrollOffset
                )
            }
        )
    }

    @discardableResult
    func start() async -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        isLoading = true
        defer { isLoading = false }
        let interval = Self.signposter.beginInterval("CorpusStartup")
        defer {
            Self.signposter.endInterval("CorpusStartup", interval)
        }

        var didUpdateCalendarSnapshot = false

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
            availableDayIndices = Dictionary(
                uniqueKeysWithValues: days.enumerated().map {
                    ($0.element.date, $0.offset)
                }
            )
            do {
                let snapshotStore =
                    HoursLiturgicalCalendarSnapshotStore.shared
                didUpdateCalendarSnapshot = try await Task.detached(
                    priority: .utility
                ) {
                    try snapshotStore.saveIfChanged(days: days)
                }.value
            } catch {
                let message = error.localizedDescription
                Self.logger.error(
                    "Unable to save calendar snapshot: \(message, privacy: .public)"
                )
            }

            // Keep automatic Matins on one Office date across midnight,
            // advancing the calendar when Lauds begins at 4 a.m.
            let now = Date()
            let currentHour = OfficeHour.current(at: now)
            let currentDay = LocalDay.currentOfficeDay(at: now)
            let initialHour: OfficeHour
            let initialDay: LocalDay
            if let readerSession,
               days.contains(where: { $0.date == readerSession.day }) {
                selectedHour = readerSession.hour
                initialHour = readerSession.hour
                initialDay = readerSession.day
            } else if automaticallySelectsCurrentOffice {
                if readerSession != nil {
                    endReaderSession()
                }
                selectedHour = currentHour
                initialHour = currentHour
                initialDay = currentDay
            } else {
                if readerSession != nil {
                    endReaderSession()
                }
                initialHour = selectedHour
                initialDay = currentDay
            }
            let initial = days.first(where: { $0.date == initialDay }) ?? fallback
            selectedCivilDate = initial.date.date ?? Date()
            await select(day: initial.date, hour: initialHour)
        } catch {
            errorMessage = error.localizedDescription
        }
        return didUpdateCalendarSnapshot
    }

    func availableDay(offsetFromSelectedBy offset: Int) -> LiturgicalDay? {
        guard let selectedDate = selectedDay?.date,
              let selectedIndex = availableDayIndices[selectedDate],
              availableDays.indices.contains(selectedIndex + offset) else {
            return nil
        }
        return availableDays[selectedIndex + offset]
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
        guard automaticallySelectsCurrentOffice,
              !isReaderSessionActive else { return }

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

    func searchContent(
        _ query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        hour: OfficeHour? = nil,
        requiresScore: Bool = false,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        guard let repository else {
            throw ContentRepositoryError.databaseUnavailable(
                "The office corpus has not finished loading."
            )
        }
        return try await repository.searchHits(
            query: query,
            language: language,
            kind: kind,
            hour: hour,
            requiresScore: requiresScore,
            limit: limit
        )
    }

    func searchOfficeTitles(
        _ query: String,
        language: LiturgicalSearchLanguage = .all,
        hour: OfficeHour? = nil,
        at date: Date = Date(),
        limit: Int = 50
    ) async throws -> [LiturgicalUsageContext] {
        guard let repository else {
            throw ContentRepositoryError.databaseUnavailable(
                "The office corpus has not finished loading."
            )
        }
        return try await repository.searchOfficeTitles(
            query: query,
            language: language,
            hour: hour,
            usageRange: LocalDay.currentOfficeDay(at: date).liturgicalYearRange,
            limit: limit
        )
    }

    func searchContentDetail(
        id: String,
        at date: Date = Date()
    ) async throws -> LiturgicalSearchResult {
        guard let repository else {
            throw ContentRepositoryError.databaseUnavailable(
                "The office corpus has not finished loading."
            )
        }
        return try await repository.searchDetail(
            id: id,
            usageRange: LocalDay.currentOfficeDay(at: date).liturgicalYearRange
        )
    }

    func selectOffice(on day: LocalDay, hour: OfficeHour) async {
        if selectedHour != hour {
            selectedHour = hour
        }
        if let civilDate = day.date,
           selectedCivilDate != civilDate {
            selectedCivilDate = civilDate
        }
        await select(day: day, hour: hour)
    }

    func beginReaderSession(for office: OfficeDocument) {
        selectedHour = office.hour
        if let civilDate = office.date.date {
            selectedCivilDate = civilDate
        }
        readerSession = ReaderSession(
            day: office.date,
            hour: office.hour,
            scrollOffset: 0
        )
        isReaderSessionActive = true
        persistReaderSession()
    }

    func restoredReaderScrollOffset(for office: OfficeDocument) -> Double? {
        guard let readerSession,
              readerSession.day == office.date,
              readerSession.hour == office.hour else {
            return nil
        }
        return readerSession.scrollOffset
    }

    func updateReaderScrollOffset(
        _ scrollOffset: Double,
        for office: OfficeDocument
    ) {
        guard var readerSession,
              readerSession.day == office.date,
              readerSession.hour == office.hour else {
            return
        }
        readerSession.scrollOffset = max(0, scrollOffset)
        self.readerSession = readerSession
        userDefaults.set(
            readerSession.scrollOffset,
            forKey: Self.readerScrollOffsetKey
        )
    }

    func endReaderSession() {
        readerSession = nil
        isReaderSessionActive = false
        userDefaults.removeObject(forKey: Self.readerIsPresentedKey)
        userDefaults.removeObject(forKey: Self.readerDayKey)
        userDefaults.removeObject(forKey: Self.readerHourKey)
        userDefaults.removeObject(forKey: Self.readerScrollOffsetKey)
    }

    func shouldRestoreReader(for office: OfficeDocument) -> Bool {
        guard let readerSession else { return false }
        return readerSession.day == office.date
            && readerSession.hour == office.hour
    }

    func restoreAppTourState(_ snapshot: AppTourSnapshot) async {
        if let showsEnglish = snapshot.showsEnglish {
            self.showsEnglish = showsEnglish
        }
        setAutomaticOfficeSelection(
            snapshot.automaticallySelectsCurrentOffice
        )
        selectedHour = snapshot.selectedHour
        if let date = snapshot.selectedDay.date {
            selectedCivilDate = date
        }
        await select(
            day: snapshot.selectedDay,
            hour: snapshot.selectedHour
        )

        if let reader = snapshot.reader {
            readerSession = ReaderSession(
                day: reader.day,
                hour: reader.hour,
                scrollOffset: reader.scrollOffset
            )
            isReaderSessionActive = true
            persistReaderSession()
        } else {
            endReaderSession()
        }
    }

    private func persistReaderSession() {
        guard let readerSession else { return }
        userDefaults.set(true, forKey: Self.readerIsPresentedKey)
        userDefaults.set(
            readerSession.day.description,
            forKey: Self.readerDayKey
        )
        userDefaults.set(
            readerSession.hour.rawValue,
            forKey: Self.readerHourKey
        )
        userDefaults.set(
            readerSession.scrollOffset,
            forKey: Self.readerScrollOffsetKey
        )
    }

    private static func readerSession(
        from userDefaults: UserDefaults
    ) -> ReaderSession? {
        guard userDefaults.bool(forKey: readerIsPresentedKey),
              let rawDay = userDefaults.string(forKey: readerDayKey),
              let day = LocalDay(iso8601: rawDay),
              let rawHour = userDefaults.string(forKey: readerHourKey),
              let hour = OfficeHour(rawValue: rawHour) else {
            return nil
        }
        return ReaderSession(
            day: day,
            hour: hour,
            scrollOffset: max(
                0,
                userDefaults.double(forKey: readerScrollOffsetKey)
            )
        )
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

    private struct ReaderSession: Sendable {
        let day: LocalDay
        let hour: OfficeHour
        var scrollOffset: Double
    }
}
