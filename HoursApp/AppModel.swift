import Foundation
import HoursCore
import Observation
import OSLog
import UIKit

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

    /// The reader's size until the reader sets one. On an iPad it is large
    /// enough that a staff across the reader's 820 points holds about the
    /// Liber's 43 staff spaces, where at 100% it would hold 62.
    static let defaultNotationScale = UIDevice.current.userInterfaceIdiom == .pad ? 1.4 : 1.0
    /// The reader's size on an iPhone's display as large as an iPad's, as
    /// iPhone Duo's held open, until the reader sets one: an iPad's.
    static let largeDisplayDefaultNotationScale = 1.4
    static let automaticOfficeSelectionKey =
        "automaticOfficeSelectionEnabled"
    static let manuallySelectedHourKey = "manuallySelectedOfficeHour"
    static let readerIsPresentedKey = "readerRestoration.isPresented"
    static let readerDayKey = "readerRestoration.day"
    static let readerHourKey = "readerRestoration.hour"
    static let readerScrollOffsetKey = "readerRestoration.scrollOffset"
    static let readerScrollAnchorKey = "readerRestoration.scrollAnchor"
    static let readerPageKey = "readerRestoration.page"
    static let readerTraditionKey = "readerRestoration.tradition"
    static let officeTraditionKey = "officeTradition"
    nonisolated static let showsEnglishKey =
        "prayerOptions.showsEnglish"
    nonisolated static let showsLatinKey =
        "prayerOptions.showsLatin"
    nonisolated static let showsChantKey =
        "prayerOptions.showsChant"
    nonisolated static let notationScaleKey =
        "prayerOptions.notationScale"
    nonisolated static let largeDisplayNotationScaleKey =
        "prayerOptions.largeDisplayNotationScale"
    nonisolated static let compactPsalmodyKey =
        "prayerOptions.compactPsalmody"
    nonisolated static let priestOrDeaconPresentKey =
        "prayerOptions.priestOrDeaconPresent"
    nonisolated static let showsMassOrdinaryKey =
        "prayerOptions.showsOrdinary"
    /// The place among its day's Masses of the Mass the reader holds; kept
    /// in place of `readerHourKey` while a Mass is read.
    static let readerMassIndexKey = "readerRestoration.massIndex"

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
    /// Whether the reader is open, at an Hour or at a Mass.
    var isReaderSessionActive: Bool { readerSession != nil }
    var selectedCivilDate = Date()
    var showsEnglish = false {
        didSet {
            userDefaults.set(
                showsEnglish,
                forKey: Self.showsEnglishKey
            )
            if !showsEnglish, !showsLatin { showsLatin = true }
        }
    }
    /// Whether the reader shows the Latin; without it, the English alone.
    var showsLatin = true {
        didSet {
            userDefaults.set(showsLatin, forKey: Self.showsLatinKey)
            if !showsLatin, !showsEnglish { showsEnglish = true }
        }
    }
    /// Whether the Latin is shown with its chant, where it has one.
    var showsChant = true {
        didSet {
            userDefaults.set(showsChant, forKey: Self.showsChantKey)
        }
    }

    /// The languages the reader shows: the Latin, the English, or both.
    var readerLanguage: ReaderLanguage {
        get {
            switch (showsLatin, showsEnglish) {
            case (true, false): .latin
            case (false, true): .english
            default: .both
            }
        }
        set {
            // Both chosen, the reader stays on the page it shows.
            let page = readerPage
            switch newValue {
            case .latin:
                showsLatin = true
                showsEnglish = false
            case .english:
                showsEnglish = true
                showsLatin = false
            case .both:
                showsLatin = true
                showsEnglish = true
                turnReaderPage(to: page)
            }
        }
    }

    /// The page the reader shows: the language chosen, or, where both are,
    /// the page it is turned to.
    var readerPage: ReaderPage {
        switch readerLanguage {
        case .latin: .latin
        case .english: .english
        case .both: turnedPage
        }
    }

    /// The page a reader of both languages is turned to.
    private var turnedPage = ReaderPage.latin

    /// Whether the reader shows chant: the Latin is shown, and its chant.
    var showsScores: Bool { showsLatin && showsChant }
    var notationScale = AppModel.defaultNotationScale {
        didSet {
            userDefaults.set(
                notationScale,
                forKey: Self.notationScaleKey
            )
        }
    }
    /// The reader's size on an iPhone's display as large as an iPad's, as
    /// iPhone Duo's held open. It is kept apart from the size of the
    /// iPhone's own display, so that each display keeps its own.
    var largeDisplayNotationScale = AppModel.largeDisplayDefaultNotationScale {
        didSet {
            userDefaults.set(
                largeDisplayNotationScale,
                forKey: Self.largeDisplayNotationScaleKey
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
    /// Whether a Mass shows its Ordinary, or the propers of the day alone.
    var showsMassOrdinary = true {
        didSet {
            userDefaults.set(
                showsMassOrdinary,
                forKey: Self.showsMassOrdinaryKey
            )
        }
    }

    /// The Mass the reader holds, opened from Home; nil when none is open.
    private(set) var mass: OfficeDocument?
    /// The Masses of the day the Mass is read on: one, or (at Christmas, on
    /// All Souls, on Maundy Thursday) several.
    private(set) var massListings: [MassListing] = []
    private(set) var isLoadingMass = false
    private(set) var massErrorMessage: String?
    /// The place among its day's Masses of the Mass that is open.
    var massIndex: Int? { readerSession?.massIndex }

    private var repository: (any ContentRepository)?
    @ObservationIgnored
    private var missal: (any MissalProvider)?
    @ObservationIgnored
    private let missalLoader: @Sendable (OfficeTradition) throws -> any MissalProvider
    @ObservationIgnored
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private let repositoryLoader: @Sendable (OfficeTradition) throws -> any ContentRepository
    @ObservationIgnored
    private let calendarSnapshotStore: HoursLiturgicalCalendarSnapshotStore
    /// What the reader holds, an Hour or a Mass, and where it stands.
    /// Unobserved, so that a settled scroll does not lay the reader out
    /// again; the reader reads it whenever its document changes.
    @ObservationIgnored
    private(set) var readerSession: ReaderSession?
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
        },
        missalLoader: @escaping @Sendable (OfficeTradition) throws -> any MissalProvider = {
            try SQLiteMissalRepository(
                databaseURL: $0.missalURL(),
                expectedTradition: $0,
                // Without the Kyriale, search offers the settings the
                // Missal sings, and nothing else is lost.
                kyriale: try? KyrialeCatalog(databaseURL: KyrialeCatalog.bundledURL())
            )
        }
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        self.repositoryLoader = repositoryLoader
        self.missalLoader = missalLoader
        self.calendarSnapshotStore = calendarSnapshotStore
        officeTradition = userDefaults.string(forKey: Self.officeTraditionKey)
            .flatMap(OfficeTradition.init(rawValue:)) ?? .roman1960
        let showsEnglish = userDefaults.bool(
            forKey: Self.showsEnglishKey
        )
        self.showsEnglish = showsEnglish
        // One language at least is shown: the Latin, unless the English is.
        let showsLatin = userDefaults.object(forKey: Self.showsLatinKey) == nil
            || userDefaults.bool(forKey: Self.showsLatinKey)
        self.showsLatin = showsLatin || !showsEnglish
        if userDefaults.object(forKey: Self.showsChantKey) != nil {
            showsChant = userDefaults.bool(forKey: Self.showsChantKey)
        }
        if userDefaults.object(forKey: Self.notationScaleKey) != nil {
            notationScale = userDefaults.double(
                forKey: Self.notationScaleKey
            )
        }
        if userDefaults.object(forKey: Self.largeDisplayNotationScaleKey) != nil {
            largeDisplayNotationScale = userDefaults.double(
                forKey: Self.largeDisplayNotationScaleKey
            )
        }
        usesCompactPsalmody = userDefaults.bool(
            forKey: Self.compactPsalmodyKey
        )
        isPriestOrDeaconPresent = userDefaults.bool(
            forKey: Self.priestOrDeaconPresentKey
        )
        if userDefaults.object(forKey: Self.showsMassOrdinaryKey) != nil {
            showsMassOrdinary = userDefaults.bool(
                forKey: Self.showsMassOrdinaryKey
            )
        }

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

        if let hour = restoredReaderSession?.hour {
            selectedHour = hour
        } else if !automaticSelectionEnabled,
           let rawHour = userDefaults.string(
               forKey: Self.manuallySelectedHourKey
           ),
           let savedHour = OfficeHour(rawValue: rawHour) {
            selectedHour = savedHour
        } else {
            selectedHour = .current(at: date)
        }
        turnedPage = restoredReaderSession?.page ?? .latin
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
            missal = nil
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
            _ = await publishCalendarSnapshot(days: days, repository: replacement, tradition: tradition)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == selectionGeneration else { return false }
            traditionErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Gives the widget the corpus's calendar: every day served, or, for a
    /// perennial corpus, the days it stores with the plan that serves the rest.
    private func publishCalendarSnapshot(
        days: [LiturgicalDay],
        repository: any ContentRepository,
        tradition: OfficeTradition
    ) async -> Bool {
        HoursSharedPreferences.defaults.set(tradition.rawValue, forKey: HoursSharedPreferences.officeTraditionKey)
        let store = calendarSnapshotStore
        do {
            let perennial = try await repository.perennialCalendar()
            return try await Task.detached(priority: .utility) {
                try store.saveIfChanged(
                    days: perennial?.storedDays ?? days,
                    tradition: tradition,
                    plan: perennial?.plan
                )
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
            // The tour knows the Hours' reader only.
            reader: readerSession.flatMap { session in
                session.hour.map {
                    AppTourReaderSnapshot(
                        day: session.day,
                        hour: $0,
                        scrollOffset: session.scrollOffset,
                        scrollAnchor: session.scrollAnchor,
                        page: session.page
                    )
                }
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
            didUpdateCalendarSnapshot = await publishCalendarSnapshot(
                days: days,
                repository: repository,
                tradition: officeTradition
            )

            // Automatic selection follows the civil date: Matins after
            // midnight belongs to the new liturgical day.
            let now = Date()
            let currentHour = OfficeHour.current(at: now)
            let currentDay = LocalDay.currentOfficeDay(at: now)
            let initialHour: OfficeHour
            let initialDay: LocalDay
            // An Hour left open is opened again where the corpus has its
            // day; a Mass left open is left to the Missal.
            if let readerSession, let hour = readerSession.hour,
               days.contains(where: { $0.date == readerSession.day }) {
                selectedHour = hour
                initialHour = hour
                initialDay = readerSession.day
            } else if automaticallySelectsCurrentOffice {
                if readerSession?.hour != nil {
                    endReaderSession()
                }
                selectedHour = currentHour
                initialHour = currentHour
                initialDay = currentDay
            } else {
                if readerSession?.hour != nil {
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
            usageRange: LocalDay.currentOfficeDay(at: date).upcomingOfficesRange,
            limit: limit
        )
    }

    /// The Masses a search of titles finds: each by its own title, or by the
    /// title of its day's Office at Terce, after which the Mass of the day
    /// is sung.
    func searchMassTitles(
        _ query: String,
        language: LiturgicalSearchLanguage = .all,
        at date: Date = Date(),
        limit: Int = 50
    ) async throws -> [MassUsageContext] {
        guard let repository else {
            throw ContentRepositoryError.databaseUnavailable(
                "The office corpus has not finished loading."
            )
        }
        let usageRange = LocalDay.currentOfficeDay(at: date).upcomingOfficesRange
        let officeDays = try await repository.officeTitleDays(
            query: query,
            language: language,
            hour: LiturgicalTitleResult.massDayHour,
            usageRange: usageRange
        )
        return try await loadedMissal().searchMassTitles(
            query: query,
            language: language,
            usageRange: usageRange,
            officeDays: officeDays,
            limit: limit
        )
    }

    /// Reads the edition's Missal for a search of its parts, as Search
    /// opens, so that the first search need not wait for it.
    func prepareMassPartSearch() async {
        try? await loadedMissal().prepareMassPartSearch()
    }

    /// The parts of the Mass whose words hold the query's, in the edition's
    /// Missal.
    func searchMassParts(
        _ query: String,
        language: LiturgicalSearchLanguage = .all,
        filter: MassPartFilter = .everyPart,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        guard repository != nil else {
            throw ContentRepositoryError.databaseUnavailable(
                "The office corpus has not finished loading."
            )
        }
        return try await loadedMissal().searchMassParts(
            query: query,
            language: language,
            filter: filter,
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
        let usageRange = LocalDay.currentOfficeDay(at: date).upcomingOfficesRange
        // A part of the Mass is the Missal's.
        if id.hasPrefix(MassPartSearch.idPrefix) {
            return try await loadedMissal().massPartDetail(id: id, usageRange: usageRange)
        }
        return try await repository.searchDetail(
            id: id,
            usageRange: usageRange
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
        // An Hour opened in place of the Mass lets the Mass go.
        clearMass()
        readerSession = ReaderSession(
            day: office.date,
            target: .hour(office.hour),
            scrollOffset: 0
        )
        // A newly opened Hour begins on its Latin page.
        turnedPage = .latin
        persistReaderSession()
    }

    /// The reader's size on the display it stands on: an iPhone's display as
    /// large as an iPad's has a size of its own.
    func notationScale(onLargeDisplay: Bool) -> Double {
        onLargeDisplay ? largeDisplayNotationScale : notationScale
    }

    func setNotationScale(_ scale: Double, onLargeDisplay: Bool) {
        if onLargeDisplay {
            largeDisplayNotationScale = scale
        } else {
            notationScale = scale
        }
    }

    static func defaultNotationScale(onLargeDisplay: Bool) -> Double {
        onLargeDisplay ? largeDisplayDefaultNotationScale : defaultNotationScale
    }

    /// Turns a reader of both languages to one of its pages, which it shows
    /// again on its return. A reader of one language has but one page.
    func turnReaderPage(to page: ReaderPage) {
        guard readerLanguage == .both else { return }
        turnedPage = page
        guard readerSession != nil else { return }
        readerSession?.page = page
        userDefaults.set(page.rawValue, forKey: Self.readerPageKey)
    }

    func restoredReaderScrollOffset(for document: OfficeDocument) -> Double? {
        guard sessionHolds(document) else { return nil }
        return readerSession?.scrollOffset
    }

    func restoredReaderScrollAnchor(for document: OfficeDocument) -> OfficeReaderScrollAnchor? {
        guard sessionHolds(document) else { return nil }
        return readerSession?.scrollAnchor
    }

    func updateReaderScrollOffset(
        _ scrollOffset: Double,
        for document: OfficeDocument,
        anchor: OfficeReaderScrollAnchor? = nil
    ) {
        guard sessionHolds(document), var session = readerSession else { return }
        session.scrollOffset = Self.sanitizedReaderScrollOffset(scrollOffset)
        session.scrollAnchor = anchor
        readerSession = session
        persistReaderScrollAnchor(anchor)
        userDefaults.set(session.scrollOffset, forKey: Self.readerScrollOffsetKey)
    }

    /// Closes the reader, at an Hour or at a Mass, and forgets its place.
    func endReaderSession() {
        readerSession = nil
        clearMass()
        for key in [
            Self.readerIsPresentedKey, Self.readerDayKey, Self.readerHourKey,
            Self.readerMassIndexKey, Self.readerScrollOffsetKey,
            Self.readerTraditionKey, Self.readerScrollAnchorKey, Self.readerPageKey,
        ] {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Whether the reader left open at an Hour is this office's.
    func shouldRestoreReader(for office: OfficeDocument) -> Bool {
        readerSession?.hour != nil && sessionHolds(office)
    }

    /// Whether the session is the reader of a document: of its Hour on its
    /// day, or of the Mass that is open.
    private func sessionHolds(_ document: OfficeDocument) -> Bool {
        guard let readerSession, readerSession.day == document.date else { return false }
        switch readerSession.target {
        case let .hour(hour):
            return !document.isMass && document.hour == hour
        case .mass:
            return document.isMass && document.id == mass?.id
        }
    }

    // MARK: The Mass

    /// Opens the Mass of a day in the reader: the first of its Masses, or
    /// another the day has.
    func openMass(on day: LocalDay, index: Int = 0) async {
        clearMass()
        readerSession = ReaderSession(day: day, target: .mass(index: index), scrollOffset: 0)
        turnedPage = .latin
        persistReaderSession()
        await loadMass()
    }

    /// Reads again the Mass a relaunch restores.
    func reloadMass() async {
        guard massIndex != nil, mass == nil, !isLoadingMass else { return }
        await loadMass()
    }

    /// Shows another of the day's Masses.
    func selectMass(index: Int) async {
        guard let current = massIndex, current != index,
              massListings.indices.contains(index) else { return }
        readerSession?.target = .mass(index: index)
        readerSession?.scrollOffset = 0
        readerSession?.scrollAnchor = nil
        readerSession?.page = .latin
        turnedPage = .latin
        persistReaderSession()
        await loadMass()
    }

    private func clearMass() {
        mass = nil
        massListings = []
        massErrorMessage = nil
    }

    private func loadMass() async {
        guard let session = readerSession, let requested = session.massIndex else { return }
        /// Whether the reader still holds the Mass this load was asked for.
        func isCurrent() -> Bool {
            readerSession?.day == session.day && massIndex == requested
        }
        isLoadingMass = true
        massErrorMessage = nil
        defer { isLoadingMass = false }
        do {
            let missal = try loadedMissal()
            let listings = try await missal.masses(on: session.day)
            guard !listings.isEmpty else {
                throw ContentRepositoryError.contentUnavailable(session.day, nil)
            }
            let index = listings.indices.contains(requested) ? requested : 0
            let document = try await missal.mass(on: session.day, index: index)
            guard isCurrent() else { return }
            massListings = listings
            mass = document
            // A Mass the day no longer has gives way to its first, which is
            // then the one chosen and restored.
            if index != requested {
                readerSession?.target = .mass(index: index)
                userDefaults.set(index, forKey: Self.readerMassIndexKey)
            }
        } catch {
            guard isCurrent() else { return }
            mass = nil
            massErrorMessage = error.localizedDescription
        }
    }

    private func loadedMissal() throws -> any MissalProvider {
        if let missal, missal.tradition == officeTradition {
            return missal
        }
        let loaded = try missalLoader(officeTradition)
        missal = loaded
        return loaded
    }

    func restoreAppTourState(_ snapshot: AppTourSnapshot) async {
        if let showsEnglish = snapshot.showsEnglish {
            self.showsEnglish = showsEnglish
        }
        if let showsLatin = snapshot.showsLatin {
            self.showsLatin = showsLatin
        }
        if let showsChant = snapshot.showsChant {
            self.showsChant = showsChant
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
            clearMass()
            readerSession = ReaderSession(
                day: reader.day,
                target: .hour(reader.hour),
                scrollOffset: reader.scrollOffset,
                scrollAnchor: reader.scrollAnchor,
                page: reader.page ?? .latin
            )
            turnedPage = reader.page ?? .latin
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
        switch readerSession.target {
        case let .hour(hour):
            userDefaults.set(hour.rawValue, forKey: Self.readerHourKey)
            userDefaults.removeObject(forKey: Self.readerMassIndexKey)
        case let .mass(index):
            userDefaults.set(index, forKey: Self.readerMassIndexKey)
            userDefaults.removeObject(forKey: Self.readerHourKey)
        }
        userDefaults.set(
            readerSession.scrollOffset,
            forKey: Self.readerScrollOffsetKey
        )
        userDefaults.set(readerSession.page.rawValue, forKey: Self.readerPageKey)
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
              let day = LocalDay(iso8601: rawDay) else {
            return nil
        }
        let target: ReaderTarget
        if userDefaults.object(forKey: readerMassIndexKey) != nil {
            target = .mass(index: max(0, userDefaults.integer(forKey: readerMassIndexKey)))
        } else if let hour = userDefaults.string(forKey: readerHourKey).flatMap(OfficeHour.init(rawValue:)) {
            target = .hour(hour)
        } else {
            return nil
        }
        return ReaderSession(
            day: day,
            target: target,
            scrollOffset: sanitizedReaderScrollOffset(
                userDefaults.double(forKey: readerScrollOffsetKey)
            ),
            scrollAnchor: userDefaults.data(forKey: readerScrollAnchorKey).flatMap {
                try? JSONDecoder().decode(OfficeReaderScrollAnchor.self, from: $0)
            },
            page: userDefaults.string(forKey: readerPageKey).flatMap(ReaderPage.init(rawValue:)) ?? .latin
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

    /// What the reader holds on its day: an Hour, or one of the day's
    /// Masses, by its place among them.
    enum ReaderTarget: Equatable, Sendable {
        case hour(OfficeHour)
        case mass(index: Int)
    }

    /// The reader that is open, and where it stands.
    struct ReaderSession: Equatable, Sendable {
        let day: LocalDay
        var target: ReaderTarget
        var scrollOffset: Double
        var scrollAnchor: OfficeReaderScrollAnchor? = nil
        /// The page the reader is turned to, where it shows both languages.
        var page = ReaderPage.latin

        var hour: OfficeHour? {
            if case let .hour(hour) = target { hour } else { nil }
        }

        var massIndex: Int? {
            if case let .mass(index) = target { index } else { nil }
        }
    }
}

/// The languages the reader shows.
enum ReaderLanguage: String, CaseIterable, Identifiable, Sendable {
    case latin
    case both
    case english

    var id: Self { self }

    var title: String {
        switch self {
        case .latin: "Latin"
        case .both: "Both"
        case .english: "English"
        }
    }
}

/// A page of the reader: the Latin, or the English. A reader that shows
/// both languages sets each on a page of its own and turns between them.
enum ReaderPage: String, CaseIterable, Codable, Identifiable, Sendable {
    case latin
    case english

    var id: Self { self }

    var title: String {
        switch self {
        case .latin: "Latin"
        case .english: "English"
        }
    }

    /// The other page of a reader of both languages.
    var facing: ReaderPage {
        self == .latin ? .english : .latin
    }
}
