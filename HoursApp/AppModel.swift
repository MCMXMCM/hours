import Foundation
import HoursCore
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

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
    static let readerScrollAnchorKey = "readerRestoration.scrollAnchor"
    static let readerTraditionKey = "readerRestoration.tradition"
    static let officeTraditionKey = "officeTradition"
    nonisolated static let showsEnglishKey =
        "prayerOptions.showsEnglish"
    nonisolated static let notationScaleKey =
        "prayerOptions.notationScale"
    nonisolated static let compactPsalmodyKey =
        "prayerOptions.compactPsalmody"
    nonisolated static let priestOrDeaconPresentKey =
        "prayerOptions.priestOrDeaconPresent"

    private(set) var availableDays: [LiturgicalDay] = []
    private(set) var selectedDay: LiturgicalDay?
    private(set) var office: OfficeDocument?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var officeTradition: OfficeTradition
    private(set) var isChangingTradition = false
    private(set) var traditionErrorMessage: String?

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
    var usesCompactPsalmody = false {
        didSet {
            userDefaults.set(
                usesCompactPsalmody,
                forKey: Self.compactPsalmodyKey
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
    private let repositoryLoader: @Sendable (OfficeTradition) throws -> any ContentRepository
    @ObservationIgnored
    private let calendarSnapshotStore: HoursLiturgicalCalendarSnapshotStore
    @ObservationIgnored
    private var readerSession: ReaderSession?
    private var hasCompletedStartup = false
    private var isStarting = false
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
        date: Date = Date(),
        calendarSnapshotStore: HoursLiturgicalCalendarSnapshotStore = .shared,
        repositoryLoader: @escaping @Sendable (OfficeTradition) throws -> any ContentRepository = {
            try SQLiteContentRepository(databaseURL: $0.databaseURL(), expectedTradition: $0)
        }
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        self.repositoryLoader = repositoryLoader
        self.calendarSnapshotStore = calendarSnapshotStore
        officeTradition = userDefaults.string(forKey: Self.officeTraditionKey)
            .flatMap(OfficeTradition.init(rawValue:)) ?? .roman1960
        showsEnglish = userDefaults.bool(
            forKey: Self.showsEnglishKey
        )
        if userDefaults.object(forKey: Self.notationScaleKey) != nil {
            notationScale = userDefaults.double(
                forKey: Self.notationScaleKey
            )
        }
        usesCompactPsalmody = userDefaults.bool(
            forKey: Self.compactPsalmodyKey
        )
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

    /// Load the complete replacement before changing the user's selected tradition.
    /// A missing or invalid pack leaves the current office and preference intact.
    @discardableResult
    func changeOfficeTradition(to tradition: OfficeTradition) async -> Bool {
        guard tradition != officeTradition, !isChangingTradition, !isStarting else { return false }
        isChangingTradition = true
        traditionErrorMessage = nil
        defer { isChangingTradition = false }
        selectionGeneration += 1
        let generation = selectionGeneration
        selectionTask?.cancel()
        selectionTask = nil
        selectionTaskKey = nil
        isLoading = false
        let day = selectedDay?.date ?? LocalDay(selectedCivilDate)
        let hour = selectedHour
        do {
            let loader = repositoryLoader
            let replacement = try await Task.detached {
                try loader(tradition)
            }.value
            let days = try await replacement.availableDays()
            guard !days.isEmpty else {
                throw ContentRepositoryError.databaseUnavailable("The \(tradition.title) corpus is empty.")
            }
            let newDay = try await replacement.day(on: day)
            let newOffice = try await replacement.office(on: day, hour: hour)
            guard generation == selectionGeneration, !Task.isCancelled else { return false }

            endReaderSession()
            repository = replacement
            availableDays = days
            availableDayIndices = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.date, $0.offset) })
            officeTradition = tradition
            selectedDay = newDay
            office = newOffice
            errorMessage = nil
            hasCompletedStartup = true
            userDefaults.set(tradition.rawValue, forKey: Self.officeTraditionKey)
            // Search hit IDs are local to a corpus. Queries themselves remain useful.
            userDefaults.removeObject(forKey: AppTourPersistence.recentHitsKey)
            _ = await publishCalendarSnapshot(days: days, tradition: tradition)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == selectionGeneration else { return false }
            traditionErrorMessage = error.localizedDescription
            return false
        }
    }

    private func publishCalendarSnapshot(days: [LiturgicalDay], tradition: OfficeTradition) async -> Bool {
        HoursSharedPreferences.defaults.set(tradition.rawValue, forKey: HoursSharedPreferences.officeTraditionKey)
        let store = calendarSnapshotStore
        do {
            return try await Task.detached(priority: .utility) {
                try store.saveIfChanged(days: days, tradition: tradition)
            }.value
        } catch {
            Self.logger.error("Unable to save calendar snapshot: \(error.localizedDescription, privacy: .public)")
            return false
        }
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
                    scrollOffset: $0.scrollOffset,
                    scrollAnchor: $0.scrollAnchor
                )
            }
        )
    }

    @discardableResult
    func start() async -> Bool {
        guard !isStarting else { return false }
        guard !hasCompletedStartup || selectedDay == nil else {
            return false
        }
        isStarting = true
        isLoading = true
        defer {
            isStarting = false
            isLoading = false
        }
        let interval = Self.signposter.beginInterval("CorpusStartup")
        defer {
            Self.signposter.endInterval("CorpusStartup", interval)
        }

        var didUpdateCalendarSnapshot = false

        do {
            let repository = try self.repository ?? repositoryLoader(officeTradition)
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
            didUpdateCalendarSnapshot = await publishCalendarSnapshot(days: days, tradition: officeTradition)

            // Automatic selection follows the civil date: Matins after
            // midnight belongs to the new liturgical day.
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
            hasCompletedStartup = selectedDay != nil && office != nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        return didUpdateCalendarSnapshot
    }

    func refreshAfterBecomingActive() async {
        while isStarting {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }

        guard !isReaderSessionActive else { return }

        guard selectedDay != nil else {
            _ = await start()
            return
        }

        if automaticallySelectsCurrentOffice {
            await selectCurrentOffice()
        } else if office == nil {
            await select(hour: selectedHour)
        }
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
        if automaticallySelectsCurrentOffice {
            setAutomaticOfficeSelection(false)
        }
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

    func restoredReaderScrollAnchor(for office: OfficeDocument) -> OfficeReaderScrollAnchor? {
        guard shouldRestoreReader(for: office) else { return nil }
        return readerSession?.scrollAnchor
    }

    func updateReaderScrollOffset(
        _ scrollOffset: Double,
        for office: OfficeDocument,
        anchor: OfficeReaderScrollAnchor? = nil
    ) {
        guard var readerSession,
              readerSession.day == office.date,
              readerSession.hour == office.hour else {
            return
        }
        readerSession.scrollOffset = Self.sanitizedReaderScrollOffset(
            scrollOffset
        )
        readerSession.scrollAnchor = anchor
        self.readerSession = readerSession
        persistReaderScrollAnchor(anchor)
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
        userDefaults.removeObject(forKey: Self.readerTraditionKey)
        userDefaults.removeObject(forKey: Self.readerScrollAnchorKey)
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
                scrollOffset: reader.scrollOffset,
                scrollAnchor: reader.scrollAnchor
            )
            isReaderSessionActive = true
            persistReaderSession()
        } else {
            endReaderSession()
        }
    }

    private func persistReaderSession() {
        guard let readerSession else { return }
        persistReaderScrollAnchor(readerSession.scrollAnchor)
        userDefaults.set(true, forKey: Self.readerIsPresentedKey)
        userDefaults.set(officeTradition.rawValue, forKey: Self.readerTraditionKey)
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

    private func persistReaderScrollAnchor(_ anchor: OfficeReaderScrollAnchor?) {
        if let anchor, let data = try? JSONEncoder().encode(anchor) {
            userDefaults.set(data, forKey: Self.readerScrollAnchorKey)
        } else {
            userDefaults.removeObject(forKey: Self.readerScrollAnchorKey)
        }
    }

    private static func readerSession(
        from userDefaults: UserDefaults
    ) -> ReaderSession? {
        let selectedTradition = userDefaults.string(forKey: officeTraditionKey) ?? OfficeTradition.roman1960.rawValue
        guard OfficeTradition(rawValue: selectedTradition) != nil else { return nil }
        let savedTradition = userDefaults.string(forKey: readerTraditionKey) ?? OfficeTradition.roman1960.rawValue
        guard selectedTradition == savedTradition else { return nil }
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
            scrollOffset: sanitizedReaderScrollOffset(
                userDefaults.double(forKey: readerScrollOffsetKey)
            ),
            scrollAnchor: userDefaults.data(forKey: readerScrollAnchorKey).flatMap {
                try? JSONDecoder().decode(OfficeReaderScrollAnchor.self, from: $0)
            }
        )
    }

    private static func sanitizedReaderScrollOffset(
        _ scrollOffset: Double
    ) -> Double {
        guard scrollOffset.isFinite else { return 0 }
        return max(0, scrollOffset)
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

        let knownDay = selectedDay?.date == day
            ? selectedDay
            : availableDayIndices[day].map { availableDays[$0] }
        if let knownDay {
            if selectedDay?.date != day {
                office = nil
            }
            selectedDay = knownDay
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
            let currentDay = knownDay
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
            if selectedDay?.date != day {
                selectedDay = nil
            }
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
        var scrollAnchor: OfficeReaderScrollAnchor? = nil
    }
}
