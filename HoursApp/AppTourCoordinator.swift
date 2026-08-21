import Foundation
import HoursCore
import Observation

enum AppTourLayer: Hashable {
    case home
    case calendar
    case search
    case settings
    case reader
}

enum AppTourTarget: Hashable {
    case prayButton
    case readerFirstChant
    case cantorPitch
    case cantorClose
    case readerContents
    case readerOratio
    case readerOptions
    case readerEnglish
    case readerOptionsClose
    case readerBack
    case dayTitle
    case calendarList
    case calendarIcon
    case calendarClose
    case searchButton
    case searchField
    case searchCategoryChants
    case searchResult
    case searchChantSetting
    case searchChantBack
    case searchDetailBack
    case searchClose
    case hourSelector
    case settingsButton
    case settingsSynchronization
    case settingsHourDisplay
    case settingsAppearance
    case settingsClose
    case settingsAbout
    case aboutTour
}

enum AppTourStep: Int, CaseIterable, Equatable {
    case chooseHour
    case prayVespers
    case tapFirstNeume
    case changeCantorPitch
    case closeCantorGuide
    case openReaderContents
    case chooseOratio
    case openReaderOptions
    case enableEnglish
    case closeReaderOptions
    case returnHomeFromReader
    case openCalendar
    case scrollCalendarMonth
    case openCalendarGrid
    case closeCalendar
    case swipeDay
    case openSearch
    case submitSearch
    case chooseChants
    case openSearchResult
    case chooseFirstChantSetting
    case returnFromFirstChant
    case chooseSecondChantSetting
    case returnFromSecondChant
    case returnToSearchResults
    case closeSearch
    case openSettings
    case changeHourDisplay
    case changeAppearance
    case closeSettings
    case reopenSettings
    case restoreHourDisplay
    case restoreAppearance
    case restoreAutomaticTracking
    case openAbout
    case aboutReplay

    var layer: AppTourLayer {
        switch self {
        case .chooseHour, .prayVespers, .openCalendar, .swipeDay, .openSearch,
             .openSettings, .reopenSettings:
            .home
        case .tapFirstNeume, .changeCantorPitch, .closeCantorGuide,
             .openReaderContents, .chooseOratio, .openReaderOptions,
             .enableEnglish, .closeReaderOptions, .returnHomeFromReader:
            .reader
        case .scrollCalendarMonth, .openCalendarGrid, .closeCalendar:
            .calendar
        case .submitSearch, .chooseChants, .openSearchResult,
             .chooseFirstChantSetting, .returnFromFirstChant,
             .chooseSecondChantSetting, .returnFromSecondChant,
             .returnToSearchResults, .closeSearch:
            .search
        case .changeHourDisplay, .changeAppearance, .closeSettings,
             .restoreHourDisplay, .restoreAppearance,
             .restoreAutomaticTracking, .openAbout, .aboutReplay:
            .settings
        }
    }

    var target: AppTourTarget {
        switch self {
        case .chooseHour: .hourSelector
        case .prayVespers: .prayButton
        case .tapFirstNeume: .readerFirstChant
        case .changeCantorPitch: .cantorPitch
        case .closeCantorGuide: .cantorClose
        case .openReaderContents: .readerContents
        case .chooseOratio: .readerOratio
        case .openReaderOptions: .readerOptions
        case .enableEnglish: .readerEnglish
        case .closeReaderOptions: .readerOptionsClose
        case .returnHomeFromReader: .readerBack
        case .openCalendar, .swipeDay: .dayTitle
        case .scrollCalendarMonth: .calendarList
        case .openCalendarGrid: .calendarIcon
        case .closeCalendar: .calendarClose
        case .openSearch: .searchButton
        case .submitSearch: .searchField
        case .chooseChants: .searchCategoryChants
        case .openSearchResult: .searchResult
        case .chooseFirstChantSetting, .chooseSecondChantSetting:
            .searchChantSetting
        case .returnFromFirstChant, .returnFromSecondChant:
            .searchChantBack
        case .returnToSearchResults: .searchDetailBack
        case .closeSearch: .searchClose
        case .openSettings, .reopenSettings: .settingsButton
        case .changeHourDisplay, .restoreHourDisplay: .settingsHourDisplay
        case .changeAppearance, .restoreAppearance: .settingsAppearance
        case .restoreAutomaticTracking: .settingsSynchronization
        case .closeSettings: .settingsClose
        case .openAbout: .settingsAbout
        case .aboutReplay: .aboutTour
        }
    }

    var title: String {
        switch self {
        case .chooseHour: "Spin to Vespers"
        case .prayVespers: "Pray Vespers"
        case .tapFirstNeume: "Try the Cantor Guide"
        case .changeCantorPitch: "Change the pitch"
        case .closeCantorGuide: "Close the Cantor Guide"
        case .openReaderContents: "Open the contents"
        case .chooseOratio: "Jump to the Oratio"
        case .openReaderOptions: "Open prayer settings"
        case .enableEnglish: "Show the English"
        case .closeReaderOptions: "Close prayer settings"
        case .returnHomeFromReader: "Return home"
        case .openCalendar: "Open the calendar"
        case .scrollCalendarMonth: "Explore the month list"
        case .openCalendarGrid: "Open the calendar grid"
        case .closeCalendar: "Return to Hours"
        case .swipeDay: "Move between days"
        case .openSearch: "Search the Office"
        case .submitSearch: "Find a familiar chant"
        case .chooseChants: "Filter to chants"
        case .openSearchResult: "Open Salve Regina"
        case .chooseFirstChantSetting: "Choose a chant setting"
        case .returnFromFirstChant: "Explore another setting"
        case .chooseSecondChantSetting: "Choose another setting"
        case .returnFromSecondChant: "Return to the result"
        case .returnToSearchResults: "Return to Search"
        case .closeSearch: "Return home"
        case .openSettings: "Explore display options"
        case .changeHourDisplay: "Change the Hour display"
        case .changeAppearance: "Change the appearance"
        case .closeSettings: "Return home"
        case .reopenSettings: "Return to Settings"
        case .restoreHourDisplay: "Restore the Wheel"
        case .restoreAppearance: "Restore Dynamic appearance"
        case .restoreAutomaticTracking: "Resume Automatic tracking"
        case .openAbout: "Open About"
        case .aboutReplay: "Tour complete"
        }
    }

    /// Time with no dimming or instruction card after an action whose result is
    /// worth seeing before the next target is introduced. Navigational actions
    /// intentionally advance immediately so the tour continues to feel direct.
    var revealDelayAfterCompletion: Duration {
        switch self {
        case .changeCantorPitch:
            .milliseconds(700)
        case .openReaderContents:
            .milliseconds(600)
        case .chooseOratio:
            .seconds(1)
        case .closeReaderOptions:
            .seconds(2)
        case .scrollCalendarMonth:
            .milliseconds(700)
        case .openCalendarGrid:
            .seconds(1)
        case .submitSearch, .chooseChants, .openSearchResult:
            .milliseconds(700)
        case .chooseFirstChantSetting, .chooseSecondChantSetting:
            .seconds(1.5)
        case .changeHourDisplay, .changeAppearance,
             .restoreHourDisplay, .restoreAppearance:
            .milliseconds(800)
        case .openAbout:
            .seconds(1)
        default:
            .zero
        }
    }
}

enum AppTourPresentationRequest: Equatable {
    case home
    case reader
}

enum AppTourEvent: Equatable {
    case readerOpened
    case cantorGuideOpened
    case scholaPitchChanged(ScholaPitch)
    case cantorGuideClosed
    case readerContentsOpened
    case readerSectionSelected(String)
    case readerOptionsOpened
    case englishVisibilityChanged(Bool)
    case readerOptionsClosed
    case readerClosed
    case calendarOpened
    case calendarMonthAdvanced
    case calendarGridOpened
    case calendarClosed(canSwipePrevious: Bool, canSwipeNext: Bool)
    case daySwiped(Int)
    case searchOpened
    case searchSubmitted(String)
    case searchResultsLoaded(query: String, count: Int)
    case searchCategorySelected(String)
    case searchResultOpened
    case searchChantOpened(String)
    case searchChantClosed(String)
    case searchDetailClosed
    case searchClosed
    case hourSelected(OfficeHour)
    case officeLoaded(OfficeHour)
    case settingsOpened
    case hourDisplayChanged(HourSelectionViewMode)
    case appearanceChanged(AppDisplayMode)
    case automaticHourSelectionChanged(Bool)
    case settingsClosed
    case aboutOpened
}

struct AppTourReaderSnapshot: Codable, Equatable {
    let day: LocalDay
    let hour: OfficeHour
    let scrollOffset: Double
}

struct AppModelTourState: Equatable {
    let selectedDay: LocalDay
    let selectedHour: OfficeHour
    let automaticallySelectsCurrentOffice: Bool
    let reader: AppTourReaderSnapshot?
}

struct AppTourSnapshot: Codable, Equatable {
    let selectedDay: LocalDay
    let selectedHour: OfficeHour
    let automaticallySelectsCurrentOffice: Bool
    let hourDisplay: HourSelectionViewMode
    let appearance: AppDisplayMode
    let reader: AppTourReaderSnapshot?
    let recentQueriesJSON: String
    let recentHitsJSON: String
    let showsEnglish: Bool?
    let scholaPitchRawValue: Int?

    init(
        selectedDay: LocalDay,
        selectedHour: OfficeHour,
        automaticallySelectsCurrentOffice: Bool,
        hourDisplay: HourSelectionViewMode,
        appearance: AppDisplayMode,
        reader: AppTourReaderSnapshot?,
        recentQueriesJSON: String,
        recentHitsJSON: String,
        showsEnglish: Bool? = nil,
        scholaPitchRawValue: Int? = nil
    ) {
        self.selectedDay = selectedDay
        self.selectedHour = selectedHour
        self.automaticallySelectsCurrentOffice =
            automaticallySelectsCurrentOffice
        self.hourDisplay = hourDisplay
        self.appearance = appearance
        self.reader = reader
        self.recentQueriesJSON = recentQueriesJSON
        self.recentHitsJSON = recentHitsJSON
        self.showsEnglish = showsEnglish
        self.scholaPitchRawValue = scholaPitchRawValue
    }
}

enum AppTourPersistence {
    static let initialOfferSeenKey = "appTour.initialOfferSeen.v1"
    static let recoverySnapshotKey = "appTour.recoverySnapshot.v1"
    static let recentQueriesKey = "prayerSearch.recentQueries"
    static let recentHitsKey = "prayerSearch.recentHits"
    static let hourDisplayKey = "hourSelectionView"

    static func recoverInterruptedSnapshot(
        standardDefaults: UserDefaults = .standard,
        appearanceDefaults: UserDefaults = HoursSharedPreferences.defaults
    ) -> AppTourSnapshot? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-app-tour") {
            standardDefaults.removeObject(forKey: initialOfferSeenKey)
            standardDefaults.removeObject(forKey: recoverySnapshotKey)
            return nil
        }
        #endif
        guard let data = standardDefaults.data(
            forKey: recoverySnapshotKey
        ) else {
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(
            AppTourSnapshot.self,
            from: data
        ) else {
            standardDefaults.removeObject(forKey: recoverySnapshotKey)
            return nil
        }
        applyPersistentValues(
            from: snapshot,
            standardDefaults: standardDefaults,
            appearanceDefaults: appearanceDefaults
        )
        return snapshot
    }

    static func applyPersistentValues(
        from snapshot: AppTourSnapshot,
        standardDefaults: UserDefaults,
        appearanceDefaults: UserDefaults
    ) {
        standardDefaults.set(
            snapshot.hourDisplay.rawValue,
            forKey: hourDisplayKey
        )
        appearanceDefaults.set(
            snapshot.appearance.rawValue,
            forKey: HoursSharedPreferences.appearanceModeKey
        )
        standardDefaults.set(
            snapshot.automaticallySelectsCurrentOffice,
            forKey: AppModel.automaticOfficeSelectionKey
        )
        standardDefaults.set(
            snapshot.selectedHour.rawValue,
            forKey: AppModel.manuallySelectedHourKey
        )
        standardDefaults.set(
            snapshot.recentQueriesJSON,
            forKey: recentQueriesKey
        )
        standardDefaults.set(
            snapshot.recentHitsJSON,
            forKey: recentHitsKey
        )
        if let showsEnglish = snapshot.showsEnglish {
            standardDefaults.set(
                showsEnglish,
                forKey: AppModel.showsEnglishKey
            )
        }
        if let scholaPitchRawValue = snapshot.scholaPitchRawValue {
            standardDefaults.set(
                scholaPitchRawValue,
                forKey: ChantPlaybackController.scholaPitchKey
            )
        }

        if let reader = snapshot.reader {
            standardDefaults.set(
                true,
                forKey: AppModel.readerIsPresentedKey
            )
            standardDefaults.set(
                reader.day.description,
                forKey: AppModel.readerDayKey
            )
            standardDefaults.set(
                reader.hour.rawValue,
                forKey: AppModel.readerHourKey
            )
            standardDefaults.set(
                reader.scrollOffset,
                forKey: AppModel.readerScrollOffsetKey
            )
        } else {
            standardDefaults.removeObject(
                forKey: AppModel.readerIsPresentedKey
            )
            standardDefaults.removeObject(forKey: AppModel.readerDayKey)
            standardDefaults.removeObject(forKey: AppModel.readerHourKey)
            standardDefaults.removeObject(
                forKey: AppModel.readerScrollOffsetKey
            )
        }
    }
}

@MainActor
@Observable
final class AppTourCoordinator {
    private(set) var isWelcomePresented = false
    private(set) var isActive = false
    private(set) var isTransitioning = false
    private(set) var step: AppTourStep?
    private(set) var requestedHour: OfficeHour?
    private(set) var requiredDaySwipeOffset: Int?
    private(set) var presentationRequest: AppTourPresentationRequest?
    private(set) var presentationRequestID = 0
    private(set) var accessibilityFocusID = 0
    private(set) var pendingAboutReplay = false

    @ObservationIgnored
    private let standardDefaults: UserDefaults
    @ObservationIgnored
    private let appearanceDefaults: UserDefaults
    @ObservationIgnored
    private let cantorGuideAppreciationDelay: Duration
    @ObservationIgnored
    private let transitionDelayOverride: Duration?
    @ObservationIgnored
    private var stepTransitionTask: Task<Void, Never>?
    @ObservationIgnored
    private var isFinishing = false
    @ObservationIgnored
    private var recoverySnapshot: AppTourSnapshot?
    @ObservationIgnored
    private var snapshot: AppTourSnapshot?
    @ObservationIgnored
    private var welcomeAction = WelcomeAction.none
    private var targetFrames: [AppTourTarget: CGRect] = [:]
    @ObservationIgnored
    private var submittedSearch = false
    @ObservationIgnored
    private var lastSearchResultCount = 0
    @ObservationIgnored
    private var selectedRequestedHour = false
    @ObservationIgnored
    private var requiresPrimeDetour = false
    @ObservationIgnored
    private(set) var firstSearchChantSettingID: String?

    init(
        recoveredSnapshot: AppTourSnapshot? = nil,
        standardDefaults: UserDefaults = .standard,
        appearanceDefaults: UserDefaults = HoursSharedPreferences.defaults,
        cantorGuideAppreciationDelay: Duration = .seconds(2.5),
        transitionDelayOverride: Duration? = nil
    ) {
        self.recoverySnapshot = recoveredSnapshot
        self.standardDefaults = standardDefaults
        self.appearanceDefaults = appearanceDefaults
        self.cantorGuideAppreciationDelay = cantorGuideAppreciationDelay
        self.transitionDelayOverride = transitionDelayOverride

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-app-tour") {
            standardDefaults.removeObject(
                forKey: AppTourPersistence.initialOfferSeenKey
            )
            standardDefaults.removeObject(
                forKey: AppTourPersistence.recoverySnapshotKey
            )
        }
        #endif
    }

    var currentLayer: AppTourLayer? { step?.layer }
    var currentTarget: AppTourTarget? { step?.target }
    var presentsOverlay: Bool { isActive && !isTransitioning }

    var progressText: String {
        guard let step else { return "" }
        return "Step \(step.rawValue + 1) of \(AppTourStep.allCases.count)"
    }

    var title: String {
        guard let step else { return "App Tour" }
        guard step == .chooseHour else { return step.title }
        if requestedHour == .prime {
            return "Spin to Prime"
        }
        if requiresPrimeDetour {
            return "Spin back to Vespers"
        }
        return step.title
    }

    var instruction: String {
        guard let step else { return "" }
        return switch step {
        case .chooseHour:
            if requestedHour == .prime {
                "Spin the Wheel until Prime settles beneath the pointer."
            } else if requiresPrimeDetour {
                "Now spin the Wheel until Vespers settles beneath the pointer again."
            } else {
                "Spin the Wheel until Vespers settles beneath the pointer."
            }
        case .prayVespers:
            "Tap Pray Vespers to open the prayer reader."
        case .tapFirstNeume:
            "Tap the first neume to hear it in the Cantor Guide."
        case .changeCantorPitch:
            "Open the Schola pitch menu and change the pitch from A to G."
        case .closeCantorGuide:
            "Tap × to close the Cantor Guide."
        case .openReaderContents:
            "Tap the contents button to see every part of Vespers."
        case .chooseOratio:
            "Tap Oratio to jump directly to the collect."
        case .openReaderOptions:
            "Tap the gear to open prayer settings."
        case .enableEnglish:
            "Turn on Show English to display the translation beside the Latin."
        case .closeReaderOptions:
            "Tap × to close prayer settings."
        case .returnHomeFromReader:
            "Tap Back to return to the Hours home screen."
        case .openCalendar:
            "Tap the liturgical day title to open the calendar."
        case .scrollCalendarMonth:
            "Swipe up through the list. At the bottom, keep swiping up to move into the next month."
        case .openCalendarGrid:
            "Tap the calendar icon for faster navigation across months and days."
        case .closeCalendar:
            "This grid makes distant dates easier to reach. Tap × to return home."
        case .swipeDay:
            requiredDaySwipeOffset == 1
                ? "Swipe left across the day title to move to the next day. Swipe right normally goes back."
                : "Swipe right across the day title to move to the previous day. Swipe left normally advances."
        case .openSearch:
            "Tap Search to find prayers, readings, and chants throughout the Office."
        case .submitSearch:
            submittedSearch
                ? "Searching the bundled Office for Salve Regina…"
                : "Type “Salve Regina” and submit the search."
        case .chooseChants:
            "Tap Chants to show only results with Gregorian notation."
        case .openSearchResult:
            "Tap the Salve Regina result to see its text and chant settings."
        case .chooseFirstChantSetting:
            "Tap the highlighted setting to view its Gregorian notation."
        case .returnFromFirstChant:
            "After viewing this setting, tap Back to compare another one."
        case .chooseSecondChantSetting:
            "Tap a different highlighted setting to view another melody."
        case .returnFromSecondChant:
            "Tap Back to return to the Salve Regina result."
        case .returnToSearchResults:
            "Tap Back once more to return to the Search results."
        case .closeSearch:
            "Office and Language can narrow searches further. Tap the × in the top-right corner to return home."
        case .openSettings:
            "Tap Settings to customize how Hours looks and selects canonical Hours."
        case .changeHourDisplay:
            "Switch between the Dial and Wheel display."
        case .changeAppearance:
            "Switch between Dynamic and System appearance."
        case .closeSettings:
            "Tap × to return to the Office."
        case .reopenSettings:
            "Tap Settings again to restore the defaults and visit About."
        case .restoreHourDisplay:
            "Choose Wheel to restore the default Hour display."
        case .restoreAppearance:
            "Choose Dynamic to restore the default canonical-hour appearance."
        case .restoreAutomaticTracking:
            "Tap Automatic so Hours follows the current canonical Hour again."
        case .openAbout:
            "Tap the info button in the top-left corner to open About Hours."
        case .aboutReplay:
            "You can replay this tour anytime from About."
        }
    }

    var isFinalStep: Bool { step == .aboutReplay }
    var shouldFocusSearchField: Bool {
        step == .submitSearch && !submittedSearch
    }

    func launchAnimationCompleted() {
        guard recoverySnapshot == nil,
              !isActive,
              !standardDefaults.bool(
                forKey: AppTourPersistence.initialOfferSeenKey
              ) else {
            return
        }
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains(
            "--suppress-app-tour"
        ) else {
            return
        }
        #endif
        isWelcomePresented = true
    }

    func requestWelcomeStart() {
        markInitialOfferSeen()
        welcomeAction = .start
        isWelcomePresented = false
    }

    func requestWelcomeSkip() {
        markInitialOfferSeen()
        welcomeAction = .skip
        isWelcomePresented = false
    }

    func requestWelcomeClose() {
        markInitialOfferSeen()
        welcomeAction = .close
        isWelcomePresented = false
    }

    func welcomeDidDismiss(model: AppModel) {
        markInitialOfferSeen()
        defer { welcomeAction = .none }
        guard welcomeAction == .start else { return }
        begin(model: model)
    }

    func requestAboutReplay() {
        pendingAboutReplay = true
    }

    func beginPendingAboutReplay(model: AppModel) {
        guard pendingAboutReplay else { return }
        pendingAboutReplay = false
        begin(model: model)
    }

    func begin(model: AppModel) {
        let snapshot = captureSnapshot(from: model)
        model.showsEnglish = false
        begin(snapshot: snapshot)
    }

    func begin(snapshot: AppTourSnapshot) {
        self.snapshot = snapshot
        persistRecoverySnapshot(snapshot)
        applyTourDisplayDefaults()
        submittedSearch = false
        lastSearchResultCount = 0
        selectedRequestedHour = false
        requiresPrimeDetour = snapshot.selectedHour == .vespers
        firstSearchChantSettingID = nil
        requestedHour = requiresPrimeDetour ? .prime : .vespers
        requiredDaySwipeOffset = nil
        stepTransitionTask?.cancel()
        stepTransitionTask = nil
        isTransitioning = false
        isActive = true
        setStep(.chooseHour, after: .zero)
        requestPresentation(.home)
    }

    func receive(_ event: AppTourEvent) {
        guard isActive, !isTransitioning, let step else { return }
        switch (step, event) {
        case let (.chooseHour, .hourSelected(hour)):
            guard hour == requestedHour else { return }
            selectedRequestedHour = true

        case let (.chooseHour, .officeLoaded(hour)):
            guard selectedRequestedHour, hour == requestedHour else { return }
            if requestedHour == .prime {
                showVespersInstructionAfterTransition()
                return
            }
            setStep(.prayVespers)

        case (.prayVespers, .readerOpened):
            setStep(.tapFirstNeume)

        case (.tapFirstNeume, .cantorGuideOpened):
            if cantorGuideAppreciationDelay == .zero {
                setStep(.changeCantorPitch, after: .zero)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(
                    for: self.cantorGuideAppreciationDelay
                )
                guard self.isActive,
                      self.step == .tapFirstNeume else { return }
                self.setStep(.changeCantorPitch, after: .zero)
            }

        case let (.changeCantorPitch, .scholaPitchChanged(pitch)):
            guard pitch == .g else { return }
            setStep(.closeCantorGuide)

        case (.closeCantorGuide, .cantorGuideClosed):
            setStep(.openReaderContents)

        case (.openReaderContents, .readerContentsOpened):
            setStep(.chooseOratio)

        case let (.chooseOratio, .readerSectionSelected(title)):
            guard Self.normalized(title) == "oratio" else { return }
            setStep(.openReaderOptions)

        case (.openReaderOptions, .readerOptionsOpened):
            setStep(.enableEnglish)

        case let (.enableEnglish, .englishVisibilityChanged(isVisible)):
            guard isVisible else { return }
            setStep(.closeReaderOptions)

        case (.closeReaderOptions, .readerOptionsClosed):
            setStep(.returnHomeFromReader)

        case (.returnHomeFromReader, .readerClosed):
            setStep(.openCalendar)

        case (.openCalendar, .calendarOpened):
            setStep(.scrollCalendarMonth)

        case (.scrollCalendarMonth, .calendarMonthAdvanced):
            setStep(.openCalendarGrid)

        case (.openCalendarGrid, .calendarGridOpened):
            setStep(.closeCalendar)

        case let (
            .closeCalendar,
            .calendarClosed(canSwipePrevious, canSwipeNext)
        ):
            if canSwipeNext {
                requiredDaySwipeOffset = 1
            } else if canSwipePrevious {
                requiredDaySwipeOffset = -1
            } else {
                return
            }
            setStep(.swipeDay)

        case let (.swipeDay, .daySwiped(offset)):
            guard offset == requiredDaySwipeOffset else { return }
            setStep(.openSearch)

        case (.openSearch, .searchOpened):
            submittedSearch = false
            lastSearchResultCount = 0
            setStep(.submitSearch)

        case let (.submitSearch, .searchSubmitted(query)):
            guard Self.isRequiredSearch(query) else { return }
            submittedSearch = true
            accessibilityFocusID += 1
            if lastSearchResultCount > 0 {
                setStep(.chooseChants)
            }

        case let (
            .submitSearch,
            .searchResultsLoaded(query, count)
        ):
            guard Self.isRequiredSearch(query) else { return }
            lastSearchResultCount = count
            if submittedSearch, count > 0 {
                setStep(.chooseChants)
            }

        case let (.chooseChants, .searchCategorySelected(category)):
            guard category == "chants" else { return }
            setStep(.openSearchResult)

        case (.openSearchResult, .searchResultOpened):
            setStep(.chooseFirstChantSetting)

        case let (.chooseFirstChantSetting, .searchChantOpened(id)):
            firstSearchChantSettingID = id
            setStep(.returnFromFirstChant)

        case let (.returnFromFirstChant, .searchChantClosed(id)):
            guard id == firstSearchChantSettingID else { return }
            setStep(.chooseSecondChantSetting)

        case let (.chooseSecondChantSetting, .searchChantOpened(id)):
            guard id != firstSearchChantSettingID else { return }
            setStep(.returnFromSecondChant)

        case let (.returnFromSecondChant, .searchChantClosed(id)):
            guard id != firstSearchChantSettingID else { return }
            setStep(.returnToSearchResults)

        case (.returnToSearchResults, .searchDetailClosed):
            setStep(.closeSearch)

        case (.closeSearch, .searchClosed):
            setStep(.openSettings)

        case (.openSettings, .settingsOpened):
            setStep(.changeHourDisplay)

        case let (.changeHourDisplay, .hourDisplayChanged(mode)):
            guard mode == .sunDial else { return }
            setStep(.changeAppearance)

        case let (.changeAppearance, .appearanceChanged(mode)):
            guard mode == .system else { return }
            setStep(.closeSettings)

        case (.closeSettings, .settingsClosed):
            setStep(.reopenSettings)

        case (.reopenSettings, .settingsOpened):
            setStep(.restoreHourDisplay)

        case let (.restoreHourDisplay, .hourDisplayChanged(mode)):
            guard mode == .wheel else { return }
            setStep(.restoreAppearance)

        case let (.restoreAppearance, .appearanceChanged(mode)):
            guard mode == .dynamic else { return }
            setStep(.restoreAutomaticTracking)

        case let (
            .restoreAutomaticTracking,
            .automaticHourSelectionChanged(isAutomatic)
        ):
            guard isAutomatic else { return }
            setStep(.openAbout)

        case (.openAbout, .aboutOpened):
            setStep(.aboutReplay)

        default:
            return
        }
    }

    func report(frame: CGRect, for target: AppTourTarget) {
        guard frame.isFinite,
              frame.width > 0,
              frame.height > 0 else { return }
        guard targetFrames[target] != frame else { return }
        targetFrames[target] = frame
    }

    func frame(for target: AppTourTarget) -> CGRect? {
        targetFrames[target]
    }

    func finish(
        model: AppModel,
        playback: ChantPlaybackController
    ) async {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        let completedInAbout = step == .aboutReplay
        guard let snapshot else {
            deactivate()
            return
        }
        playback.stop()
        if let rawPitch = snapshot.scholaPitchRawValue,
           let pitch = ScholaPitch(rawValue: rawPitch) {
            playback.scholaPitch = pitch
        }
        if completedInAbout {
            await applyCompletedTourDefaults(
                from: snapshot,
                to: model
            )
        } else {
            AppTourPersistence.applyPersistentValues(
                from: snapshot,
                standardDefaults: standardDefaults,
                appearanceDefaults: appearanceDefaults
            )
            await model.restoreAppTourState(snapshot)
        }
        standardDefaults.removeObject(
            forKey: AppTourPersistence.recoverySnapshotKey
        )
        let request: AppTourPresentationRequest = snapshot.reader == nil
            ? .home
            : .reader
        deactivate()
        if !completedInAbout {
            requestPresentation(request)
        }
    }

    private func applyCompletedTourDefaults(
        from snapshot: AppTourSnapshot,
        to model: AppModel
    ) async {
        standardDefaults.set(
            HourSelectionViewMode.wheel.rawValue,
            forKey: AppTourPersistence.hourDisplayKey
        )
        appearanceDefaults.set(
            AppDisplayMode.dynamic.rawValue,
            forKey: HoursSharedPreferences.appearanceModeKey
        )
        standardDefaults.set(
            snapshot.recentQueriesJSON,
            forKey: AppTourPersistence.recentQueriesKey
        )
        standardDefaults.set(
            snapshot.recentHitsJSON,
            forKey: AppTourPersistence.recentHitsKey
        )
        if let showsEnglish = snapshot.showsEnglish {
            model.showsEnglish = showsEnglish
        }
        model.endReaderSession()
        model.setAutomaticOfficeSelection(true)
        await model.selectCurrentOffice()
    }

    func recoverAfterModelStart(model: AppModel) async {
        guard let recoverySnapshot else { return }
        await model.restoreAppTourState(recoverySnapshot)
        standardDefaults.removeObject(
            forKey: AppTourPersistence.recoverySnapshotKey
        )
        self.recoverySnapshot = nil
    }

    func consumePresentationRequest() {
        presentationRequest = nil
    }

    private func captureSnapshot(from model: AppModel) -> AppTourSnapshot {
        let state = model.appTourState
        return AppTourSnapshot(
            selectedDay: state.selectedDay,
            selectedHour: state.selectedHour,
            automaticallySelectsCurrentOffice:
                state.automaticallySelectsCurrentOffice,
            hourDisplay: HourSelectionViewMode(
                rawValue: standardDefaults.string(
                    forKey: AppTourPersistence.hourDisplayKey
                ) ?? ""
            ) ?? .wheel,
            appearance: AppDisplayMode(
                rawValue: appearanceDefaults.string(
                    forKey: HoursSharedPreferences.appearanceModeKey
                ) ?? ""
            ) ?? .dynamic,
            reader: state.reader,
            recentQueriesJSON: standardDefaults.string(
                forKey: AppTourPersistence.recentQueriesKey
            ) ?? "[]",
            recentHitsJSON: standardDefaults.string(
                forKey: AppTourPersistence.recentHitsKey
            ) ?? "[]",
            showsEnglish: model.showsEnglish,
            scholaPitchRawValue: standardDefaults.object(
                forKey: ChantPlaybackController.scholaPitchKey
            ) == nil
                ? ScholaPitch.a.rawValue
                : standardDefaults.integer(
                    forKey: ChantPlaybackController.scholaPitchKey
                )
        )
    }

    private func setStep(
        _ step: AppTourStep,
        after delay: Duration? = nil
    ) {
        let delay = delay
            ?? transitionDelayOverride
            ?? self.step?.revealDelayAfterCompletion
            ?? .zero
        stepTransitionTask?.cancel()

        guard delay != .zero else {
            isTransitioning = false
            self.step = step
            accessibilityFocusID += 1
            stepTransitionTask = nil
            return
        }

        let expectedStep = self.step
        isTransitioning = true
        stepTransitionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard let self,
                  self.isActive,
                  self.isTransitioning,
                  self.step == expectedStep else { return }
            self.isTransitioning = false
            self.step = step
            self.accessibilityFocusID += 1
            self.stepTransitionTask = nil
        }
    }

    private func showVespersInstructionAfterTransition() {
        let delay = transitionDelayOverride
            ?? AppTourStep.chooseHour.revealDelayAfterCompletion
        guard delay != .zero else {
            selectedRequestedHour = false
            requestedHour = .vespers
            accessibilityFocusID += 1
            return
        }

        stepTransitionTask?.cancel()
        isTransitioning = true
        stepTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard self.isActive,
                  self.isTransitioning,
                  self.step == .chooseHour else { return }
            self.selectedRequestedHour = false
            self.requestedHour = .vespers
            self.isTransitioning = false
            self.accessibilityFocusID += 1
            self.stepTransitionTask = nil
        }
    }

    private func requestPresentation(
        _ presentation: AppTourPresentationRequest
    ) {
        presentationRequest = presentation
        presentationRequestID += 1
    }

    private func persistRecoverySnapshot(_ snapshot: AppTourSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        standardDefaults.set(
            data,
            forKey: AppTourPersistence.recoverySnapshotKey
        )
    }

    private func applyTourDisplayDefaults() {
        standardDefaults.set(
            HourSelectionViewMode.wheel.rawValue,
            forKey: AppTourPersistence.hourDisplayKey
        )
        appearanceDefaults.set(
            AppDisplayMode.dynamic.rawValue,
            forKey: HoursSharedPreferences.appearanceModeKey
        )
    }

    private func markInitialOfferSeen() {
        standardDefaults.set(
            true,
            forKey: AppTourPersistence.initialOfferSeenKey
        )
    }

    private func deactivate() {
        stepTransitionTask?.cancel()
        stepTransitionTask = nil
        isActive = false
        isTransitioning = false
        step = nil
        snapshot = nil
        requestedHour = nil
        requiredDaySwipeOffset = nil
        firstSearchChantSettingID = nil
        // Keep geometry reported by views that remain mounted after the tour.
        // `onGeometryChange` does not report an unchanged frame again when a
        // same-session replay begins, so clearing this cache would leave the
        // replay spotlight without an interaction hole.
    }

    private static func isRequiredSearch(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Salve Regina") == .orderedSame
    }

    func intendedSearchChantSettingID(from ids: [String]) -> String? {
        switch step {
        case .chooseFirstChantSetting:
            ids.first
        case .chooseSecondChantSetting:
            ids.first(where: { $0 != firstSearchChantSettingID })
        default:
            nil
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "la")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum WelcomeAction {
        case none
        case start
        case skip
        case close
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite
            && width.isFinite && height.isFinite
    }
}
