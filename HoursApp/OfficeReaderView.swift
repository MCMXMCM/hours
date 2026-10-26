import HoursCore
import Observation
import OSLog
import SwiftUI
import UIKit

/// Whether an iPhone shows the reader on a display as large as an iPad's,
/// regular both ways, as iPhone Duo's held open. The reader is read there as
/// on an iPad, at a size of its own.
private func readsOnLargeDisplay(
    _ horizontal: UserInterfaceSizeClass?,
    _ vertical: UserInterfaceSizeClass?
) -> Bool {
    UIDevice.current.userInterfaceIdiom == .phone
        && horizontal == .regular && vertical == .regular
}

/// The reader of an Office or a Mass. Where it shows both languages it sets
/// the Latin and the English each on a page of its own, side by side, and
/// turns between them by a swipe or by its page indicator; else it shows
/// the one page of the language chosen.
struct OfficeReaderView: View {
    let office: OfficeDocument
    let displayMode: AppDisplayMode
    /// The Hour whose light the reader takes: the Hour read, or, for a
    /// Mass, the Hour chosen on Home.
    let skyHour: OfficeHour
    let restoredScrollOffset: Double?
    let restoredScrollAnchor: OfficeReaderScrollAnchor?
    let onScrollOffsetChange: (Double, OfficeReaderScrollAnchor?) -> Void

    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedScore: ChantScore?
    @State private var selectedScoreSectionID: String?
    @State private var showsSections = false
    @State private var pendingSectionJumpID: String?
    @State private var showsOptions = false
    @State private var isPreparingPrint = false
    @State private var printErrorMessage: String?
    @State private var cantorTracking = CantorGuideTrackingState()
    @State private var pager: OfficeReaderPager

    /// Whether the words a priest or deacon says in place of the lay forms
    /// stand in the text: in the Office, as Prayer options say; never in the
    /// Mass, whose celebrant the Missal's own words already suppose.
    private var isPriestOrDeaconPresent: Bool {
        office.isMass ? false : model.isPriestOrDeaconPresent
    }

    private var readerScale: CGFloat {
        CGFloat(
            GregorianLayoutMetrics.clampedNotationScale(
                model.notationScale(onLargeDisplay: isLargeDisplay)
            )
        )
    }

    private var isLargeDisplay: Bool {
        readsOnLargeDisplay(horizontalSizeClass, verticalSizeClass)
    }

    init(
        office: OfficeDocument,
        displayMode: AppDisplayMode,
        skyHour: OfficeHour,
        restoredScrollOffset: Double? = nil,
        restoredScrollAnchor: OfficeReaderScrollAnchor? = nil,
        onScrollOffsetChange: @escaping (Double, OfficeReaderScrollAnchor?) -> Void = { _, _ in }
    ) {
        self.office = office
        self.displayMode = displayMode
        self.skyHour = skyHour
        self.restoredScrollOffset = restoredScrollOffset
        self.restoredScrollAnchor = restoredScrollAnchor
        self.onScrollOffsetChange = onScrollOffsetChange
        _pager = State(initialValue: OfficeReaderPager(openingAnchor: restoredScrollAnchor))
    }

    var body: some View {
        Group {
            if office.format == .contentUnavailable {
                unavailableOffice
            } else {
                pages
            }
        }
        .background {
            if displayMode.showsAmbientSky {
                AmbientSkyView(selection: skyHour)
                .ignoresSafeArea()
            } else {
                Color.hoursBackground
                    .ignoresSafeArea()
            }
        }
        .sheet(
            isPresented: $showsOptions,
            onDismiss: {
                tour.receive(.readerOptionsClosed)
            }
        ) {
            PrayerOptionsView(
                isMass: office.isMass,
                isLargeDisplay: isLargeDisplay,
                isPreparingPrint: isPreparingPrint,
                isPrintingAvailable: OfficePrintPresenter.isPrintingAvailable,
                onPrint: printCurrentOffice
            ) {
                showsOptions = false
            }
                .modifier(
                    AdaptiveSheetPresentation(phoneDetents: [.large])
                )
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.hoursBackground)
                .appTourOverlayHost(.reader)
                .environment(model)
                .environment(playback)
                .environment(tour)
                .alert(
                    "Unable to Print",
                    isPresented: Binding(
                        get: { printErrorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                printErrorMessage = nil
                            }
                        }
                    )
                ) {
                    Button("OK") {
                        printErrorMessage = nil
                    }
                } message: {
                    Text(
                        printErrorMessage
                            ?? "The print job could not be prepared."
                    )
                }
        }
        .sheet(
            isPresented: $showsSections,
            onDismiss: jumpToPendingSection
        ) {
            OfficeSectionsSheet(
                entries: pager.outlines[model.readerPage] ?? [],
                onSelect: { entry in
                    pendingSectionJumpID = entry.id
                    tour.receive(
                        .readerSectionSelected(entry.title)
                    )
                    showsSections = false
                }
            )
            .modifier(
                AdaptiveSheetPresentation(
                    phoneDetents: [.medium, .large]
                )
            )
            .presentationDragIndicator(.visible)
            .appTourOverlayHost(.reader)
            .environment(model)
            .environment(playback)
            .environment(tour)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if office.format != .contentUnavailable {
                    ToolbarButtonStack {
                        Button {
                            guard !tour.isActive
                                    || tour.step == .openReaderContents,
                                  pager.outlines[model.readerPage] != nil else {
                                return
                            }
                            showsSections = true
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 15, weight: .regular))
                                .frame(width: 34, height: 34)
                                .appTourToolbarTarget(.readerContents)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Office sections")
                        .accessibilityHint(
                            "Opens a list of sections to jump to"
                        )
                        .accessibilityIdentifier("office-sections")

                        Button {
                            guard !tour.isActive
                                    || tour.step == .openReaderOptions else {
                                return
                            }
                            showsOptions = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .regular))
                                .frame(width: 34, height: 34)
                                .appTourToolbarTarget(.readerOptions)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Prayer options")
                        .accessibilityIdentifier("prayer-options")
                    }
                }
            }
            .standsInVerticalBars()
            if model.readerLanguage == .both,
               office.format != .contentUnavailable {
                ToolbarItem(placement: .subtitle) {
                    ReaderPageIndicator(page: model.readerPage) { page in
                        turn(to: page)
                    }
                    .appTourTarget(.readerPageIndicator)
                }
            }
        }
        .onDisappear {
            playback.stop()
        }
        .onChange(of: model.isPriestOrDeaconPresent) { _, _ in
            closeCantorGuide()
        }
        .onChange(of: model.usesCompactPsalmody) { _, _ in
            closeCantorGuide()
        }
        .onChange(of: model.showsMassOrdinary) { _, _ in
            closeCantorGuide()
        }
        .onChange(of: model.showsScores) { _, _ in
            closeCantorGuide()
        }
        // The reader opens on its page, as it was left. A page shown
        // otherwise than by a turn, as when a language is chosen, stands at
        // the words read on the page it replaces: a page laid out already is
        // brought there, and a new page restores itself to them.
        .onChange(of: model.readerPage, initial: true) { previous, page in
            guard !pager.isTurning else { return }
            pager.position = page == .latin ? 0 : 1
            guard page != previous, pager.readyPages.contains(page) else { return }
            Task { @MainActor in
                await pager.align(page, to: pager.reading)
            }
        }
    }

    /// The reader's pages: the page shown, and, where both languages are
    /// shown, the facing page beside it, which can be dragged into view.
    private var pages: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(livePages) { page in
                    ReaderPageSlot(
                        page: page,
                        pager: pager,
                        isPaged: model.readerLanguage == .both,
                        crossfades: reduceMotion,
                        isShown: page == model.readerPage,
                        width: pageTurnDistance(in: geometry)
                    ) {
                        pageView(page)
                    }
                }
            }
            .gesture(
                ReaderPageTurnGesture(
                    page: model.readerPage,
                    isEnabled: canTurn,
                    onBegan: beginDrag,
                    onChanged: drag,
                    onEnded: endDrag
                )
            )
            .onChange(of: pageTurnDistance(in: geometry), initial: true) { _, distance in
                pager.turnDistance = distance
            }
        }
    }

    /// How far a page moves as it turns: across the screen, so that a page
    /// turned away stands past its edge, and not beneath a bar down its side
    /// where iPhone Duo sets its bars.
    private func pageTurnDistance(in geometry: GeometryProxy) -> CGFloat {
        geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
    }

    /// The pages laid out: the page shown, and, where both languages are
    /// shown, the facing page beside it from the first, so that a swipe can
    /// turn to it at once. A page first laid out under a drag would end the
    /// drag that wanted it.
    private var livePages: [ReaderPage] {
        model.readerLanguage == .both ? ReaderPage.allCases : [model.readerPage]
    }

    private func pageView(_ page: ReaderPage) -> some View {
        OfficeReaderPage(
            office: office,
            page: page,
            restoredScrollOffset: restoredScrollOffset,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent,
            pager: pager,
            selectedScore: $selectedScore,
            selectedScoreSectionID: $selectedScoreSectionID,
            cantorTracking: cantorTracking,
            onCloseCantorGuide: closeCantorGuide,
            onSettle: { offset, anchor, reading in
                pager.settle(page, reading: reading)
                onScrollOffsetChange(offset, anchor)
            }
        )
    }

    /// Whether the reader may be turned: both languages are shown, and the
    /// tour, if it is under way, has come to its turn of the page.
    private var canTurn: Bool {
        model.readerLanguage == .both
            && (!tour.isActive
                || tour.step == .turnToEnglish
                || tour.step == .returnHomeFromReader)
    }

    /// Turns to a page from the indicator: the page is brought to where the
    /// reader stands, and turned to, sliding or, with Reduce Motion, fading.
    /// An open Cantor Guide is closed first.
    private func turn(to page: ReaderPage) {
        guard canTurn, page != model.readerPage, !pager.isTurning else { return }
        if selectedScore != nil {
            closeCantorGuide()
        }
        let interval = OfficeReaderPageTurn.signposter.beginInterval(
            "ReaderPageTurn",
            id: OfficeReaderPageTurn.signposter.makeSignpostID(),
            "indicator"
        )
        let from = model.readerPage
        pager.isTurning = true
        Task { @MainActor in
            await pager.prepareTurn(from: from, to: page)
            finishTurn(to: page, from: from, interval: interval)
        }
    }

    private func beginDrag() {
        guard pager.dragOrigin == nil, !pager.isTurning else { return }
        let from = model.readerPage
        pager.dragOrigin = from
        pager.isTurning = true
        pager.bringFacingPage(of: from)
    }

    private func drag(_ translation: CGFloat, width: CGFloat) {
        // With Reduce Motion the page does not follow the finger; it fades
        // when the drag is let go.
        guard let from = pager.dragOrigin, !reduceMotion else { return }
        pager.position = OfficeReaderPageTurn.position(
            from: from,
            translation: translation,
            width: max(width, pager.turnDistance)
        )
    }

    private func endDrag(_ translation: CGFloat, velocity: CGFloat, width: CGFloat) {
        guard let from = pager.dragOrigin else { return }
        pager.dragOrigin = nil
        let completes = OfficeReaderPageTurn.completes(
            from: from,
            translation: translation,
            velocity: velocity,
            width: width
        )
        let interval = completes
            ? OfficeReaderPageTurn.signposter.beginInterval(
                "ReaderPageTurn",
                id: OfficeReaderPageTurn.signposter.makeSignpostID(),
                "swipe"
            )
            : nil
        finishTurn(to: completes ? from.facing : from, from: from, interval: interval)
    }

    private func finishTurn(
        to page: ReaderPage,
        from: ReaderPage,
        interval: OSSignpostIntervalState?
    ) {
        if page != from {
            // The Cantor Guide sings from the page turned from: a turn,
            // swiped or tapped, stops it and closes it.
            if selectedScore != nil {
                closeCantorGuide()
            }
            model.turnReaderPage(to: page)
            tour.receive(.readerPageTurned(page))
        }
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: 0.25)
                : .spring(duration: 0.32, bounce: 0)
        ) {
            pager.position = page == .latin ? 0 : 1
        } completion: {
            pager.isTurning = false
            if let interval {
                OfficeReaderPageTurn.signposter.endInterval("ReaderPageTurn", interval)
            }
            if page != from {
                pager.turnCompleted(to: page)
            }
        }
    }

    private func jumpToPendingSection() {
        guard let sectionID = pendingSectionJumpID else { return }
        pendingSectionJumpID = nil
        pager.jump(to: sectionID, on: model.readerPage)
    }

    private var unavailableOffice: some View {
        ScrollView {
            VStack(spacing: 0) {
                OfficeReaderHeader(
                    office: office,
                    page: model.readerPage,
                    readerScale: readerScale
                )
                ContentUnavailableView {
                    Label("Office text coming soon", systemImage: "book.closed")
                } description: {
                    Text(
                        "The complete ordered text and chants for this hour "
                            + "have not yet been verified. Hours will not "
                            + "substitute a different office."
                    )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 80)
                .accessibilityIdentifier("office-content-unavailable")
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private func closeCantorGuide() {
        playback.stop()
        selectedScore = nil
        selectedScoreSectionID = nil
        cantorTracking.reset()
        tour.receive(.cantorGuideClosed)
    }

    private func printCurrentOffice() {
        guard !isPreparingPrint, !tour.isActive else { return }
        // Paper cannot be turned: with both languages chosen, the Latin is
        // printed with its English beneath.
        let snapshot = OfficePrintSnapshot(
            office: office,
            showsEnglish: model.showsEnglish,
            showsLatin: model.showsLatin,
            showsChant: model.showsChant,
            usesCompactPsalmody: model.usesCompactPsalmody,
            showsOrdinary: model.showsMassOrdinary,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent,
            // A page prints alike from every device: the reader's size as a
            // share of the display's own default.
            readerScale: model.notationScale(onLargeDisplay: isLargeDisplay)
                / AppModel.defaultNotationScale(onLargeDisplay: isLargeDisplay)
        )
        isPreparingPrint = true
        Task { @MainActor in
            defer { isPreparingPrint = false }
            do {
                try await OfficePrintPresenter.present(
                    snapshot: snapshot
                ) { errorMessage in
                    printErrorMessage = errorMessage
                }
            } catch {
                printErrorMessage = error.localizedDescription
            }
        }
    }
}

/// A page of the reader, placed as far as the reader is turned: beside the
/// other page, or, with Reduce Motion, over it, fading in as the other
/// fades out. It alone reads the turn, so that neither page is laid out
/// anew as the pages move.
private struct ReaderPageSlot<Content: View>: View {
    let page: ReaderPage
    let pager: OfficeReaderPager
    let isPaged: Bool
    let crossfades: Bool
    let isShown: Bool
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // How far this page is turned from view: 0 shown, 1 turned away.
        let away = page == .latin ? pager.position : 1 - pager.position
        let direction: CGFloat = page == .latin ? -1 : 1
        content
            .offset(x: isPaged && !crossfades ? direction * away * width : 0)
            .opacity(isPaged && crossfades ? 1 - away : 1)
            .allowsHitTesting(isShown && !pager.isTurning)
            .accessibilityHidden(!isShown)
            .zIndex(isShown ? 1 : 0)
    }
}

/// One page of the reader: the Office in Latin, sung from its chant where
/// the chant is shown, or in English. Each page keeps its own scroll view,
/// presentation and place, prepared off the main actor.
private struct OfficeReaderPage: View {
    let office: OfficeDocument
    let page: ReaderPage
    let restoredScrollOffset: Double?
    /// As the reader resolves it for the Office or the Mass.
    let isPriestOrDeaconPresent: Bool
    let pager: OfficeReaderPager
    @Binding var selectedScore: ChantScore?
    @Binding var selectedScoreSectionID: String?
    let cantorTracking: CantorGuideTrackingState
    let onCloseCantorGuide: () -> Void
    let onSettle: (Double, OfficeReaderScrollAnchor?, OfficeReaderPageTurn.ReadingPlace?) -> Void

    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var presentation: OfficeReaderPresentation?
    @State private var preparedScores: PreparedOfficeScores?
    @State private var transientState = OfficeReaderTransientState()

    static let topAnchorID = "office-reader-top"

    /// Whether the page is in Latin: else it is in English.
    private var isLatin: Bool { page == .latin }

    /// Whether the page sings from the chant: the Latin, its chant shown.
    private var showsScores: Bool { isLatin && model.showsChant }

    /// Whether the reader shows this page.
    private var isShown: Bool { model.readerPage == page }

    /// The reader's size on the display it stands on.
    private var notationScale: Double {
        model.notationScale(
            onLargeDisplay: readsOnLargeDisplay(horizontalSizeClass, verticalSizeClass)
        )
    }

    private var readerScale: CGFloat {
        CGFloat(
            GregorianLayoutMetrics.clampedNotationScale(notationScale)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            if let presentation,
               presentation.officeID == office.id {
                let sections = presentation.sections
                // The first score that is shown: where a priest or deacon is
                // present, a request or a greeting stands as text.
                let firstChantSectionID = sections.first(where: {
                    $0.chant != nil
                        && !OfficePrayerText.requiresTextFallback(
                            for: $0,
                            isPriestOrDeaconPresent: isPriestOrDeaconPresent
                        )
                })?.id
                let scores = presentation.scores
                let scoreWidth = min(geometry.size.width, 820)
                let preparationKey = ScorePreparationKey(
                    officeID: office.id,
                    scoreSignature: presentation.scoreSignature,
                    width: Int(scoreWidth.rounded()),
                    notationScale: Int((notationScale * 100).rounded()),
                    lyricScale: Int(
                        (GregorianScoreView.lyricScale(for: dynamicTypeSize) * 100)
                            .rounded()
                    ),
                    displayScale: Int((displayScale * 100).rounded())
                )
                ZStack {
                    if let preparedScores,
                       preparedScores.key == preparationKey {
                        let blocks = OfficeReaderBlockBuilder.blocks(
                            of: sections,
                            heightFloors: preparedScores.sectionHeightFloors,
                            minimumHeight: Self.minimumBlockHeight(in: geometry)
                        )
                        ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(blocks) { block in
                                    VStack(spacing: 0) {
                                        if block.sectionRange.lowerBound == 0 {
                                            OfficeReaderHeader(
                                                office: office,
                                                page: page,
                                                readerScale: readerScale
                                            )
                                                .id(Self.topAnchorID)
                                                .background {
                                                    OfficeReaderScrollViewAccessor { scrollView, view in
                                                        transientState.scrollView = scrollView
                                                        transientState.registerSectionView(view, for: Self.topAnchorID)
                                                    }
                                                }
                                        }

                                        ForEach(
                                            Array(
                                                zip(
                                                    block.sectionRange,
                                                    sections[block.sectionRange]
                                                )
                                            ),
                                            id: \.1.id
                                        ) { index, section in
                                            sectionView(
                                                index: index,
                                                section: section,
                                                sections: sections,
                                                preparedScores: preparedScores,
                                                firstChantSectionID: firstChantSectionID,
                                                geometry: geometry,
                                                proxy: proxy
                                            )
                                        }
                                    }
                                    .id(block.id)
                                }
                            }
                            .background {
                                OfficeReaderScrollViewAccessor { scrollView, _ in
                                    transientState.scrollView = scrollView
                                }
                            }
                            .frame(maxWidth: 820)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 100)
                        }
                        // The facing page, out of sight, is out of reach of
                        // VoiceOver too. Its empty scroll view is still listed,
                        // under a name of its own.
                        .accessibilityHidden(!isShown)
                        .accessibilityIdentifier(
                            isShown ? "office-reader-scroll" : "office-reader-facing-scroll"
                        )
                        .onScrollGeometryChange(
                            for: OfficeReaderScrollGeometry.self
                        ) { geometry in
                            OfficeReaderScrollGeometry(geometry)
                        } action: { _, scrollGeometry in
                            // Ignore geometry produced while iOS hides or snapshots
                            // the scene. It must not replace the reading position.
                            guard scenePhase == .active else { return }
                            transientState.latestScrollOffset = scrollGeometry.offset
                            transientState.maximumScrollOffset = scrollGeometry.maximumOffset
                            transientState.latestScrollAnchor = OfficeReaderScrollRestoration.anchor(
                                in: transientState.sectionFrames
                            )
                            transientState.hasScrollGeometry = true
                        }
                        .onScrollPhaseChange { _, phase in
                            if phase == .tracking || phase == .interacting {
                                transientState.sectionJumpToken = nil
                                transientState.protectedAnchor = nil
                                transientState.userInterruptedRestoration = true
                                transientState.hasAppliedInitialScroll = true
                                if isShown {
                                    pager.pageBeganScrolling()
                                }
                            }
                            if phase == .animating {
                                transientState.sectionJumpToken = nil
                                transientState.protectedAnchor = nil
                            }
                            guard phase == .idle, scenePhase == .active else { return }
                            // Let section frames catch up with the final scroll geometry.
                            DispatchQueue.main.async { saveScrollOffset() }
                        }
                        // The passage is found again whenever the page is
                        // laid out anew beneath it: on return to the app, and
                        // when the clergy's greeting is shown or hidden, which
                        // lengthens or shortens what stands above.
                        .task(
                            id: OfficeReaderPassageKey(
                                scenePhase: scenePhase,
                                isPriestOrDeaconPresent: isPriestOrDeaconPresent
                            )
                        ) {
                            guard scenePhase == .active else { return }
                            await restoreScrollPosition(
                                sections: sections,
                                blocks: blocks,
                                using: proxy
                            )
                        }
                        .onChange(of: blocks, initial: true) {
                            let sectionIDs = Set(sections.map(\.id)).union([Self.topAnchorID])
                            pager.register(
                                page,
                                handle: OfficeReaderPageHandle(
                                    readingPlace: { readingPlace() },
                                    isScrolling: {
                                        guard let scrollView = transientState.scrollView else { return false }
                                        return scrollView.isTracking || scrollView.isDragging
                                            || scrollView.isDecelerating
                                    },
                                    placeNow: { place in
                                        placeNow(at: place, among: sectionIDs)
                                    },
                                    align: { place in
                                        await align(to: place, among: sectionIDs, in: blocks, using: proxy)
                                    },
                                    jump: { sectionID in
                                        jump(to: sectionID, in: blocks, using: proxy)
                                    }
                                )
                            )
                        }
                        .background {
                            if isLatin {
                                AppTourFirstChantScroll(
                                    sectionID: firstChantSectionID
                                ) { sectionID in
                                    transientState.protectedAnchor = nil
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        scroll(toTopOf: sectionID, in: blocks, using: proxy)
                                    }
                                }
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if isLatin, let selectedScore {
                                PlaybackControlsView(
                                    score: selectedScore,
                                    onClose: onCloseCantorGuide
                                )
                                .frame(maxWidth: 820)
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier(
                                    uiTestCantorTrackingIdentifier
                                )
                                .onGeometryChange(
                                    for: CGRect.self,
                                    of: { barGeometry in
                                        barGeometry.frame(in: .global)
                                    },
                                    action: { frame in
                                        cantorTracking.cantorGuideFrame = frame
                                        if let latestActiveNeume =
                                            cantorTracking.latestActiveNeume {
                                            track(
                                                latestActiveNeume,
                                                readerFrame: geometry.frame(in: .global),
                                                using: proxy
                                            )
                                        }
                                        scheduleUITestOpeningCheck()
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .animation(
                            .easeInOut(duration: 0.2),
                            value: selectedScoreSectionID
                        )
                    }
                    } else {
                        preparingOffice
                    }
                }
                .task(id: preparationKey) {
                    let metrics = GregorianScoreView.metrics(
                        notationScale: notationScale,
                        dynamicTypeSize: dynamicTypeSize,
                        displayScale: displayScale
                    )
                    let scoresByID = await GregorianScorePreparer.prepare(
                        scores: scores,
                        width: scoreWidth,
                        metrics: metrics,
                        pieceScoreIDs: Set(
                            sections.filter(\.kind.opensPiece).compactMap(\.chant?.id)
                        )
                    )
                    guard !Task.isCancelled else { return }
                    preparedScores = PreparedOfficeScores(
                        key: preparationKey,
                        scores: scoresByID,
                        sectionHeightFloors: sectionHeightFloors(
                            of: sections,
                            scores: scoresByID,
                            columnWidth: scoreWidth - 40
                        )
                    )
                }
            } else {
                preparingOffice
            }
        }
        .onDisappear {
            transientState.sectionJumpToken = nil
            transientState.protectedAnchor = nil
            pager.unregister(page)
        }
        .task(
            id: OfficeReaderPresentationKey(
                officeID: office.id,
                usesCompactPsalmody: model.usesCompactPsalmody,
                showsOrdinary: model.showsMassOrdinary,
                showsScores: showsScores
            )
        ) {
            guard office.format != .contentUnavailable else { return }
            let key = OfficeReaderPresentationKey(
                officeID: office.id,
                usesCompactPsalmody: model.usesCompactPsalmody,
                showsOrdinary: model.showsMassOrdinary,
                showsScores: showsScores
            )
            // A page laid out again, as when a language is chosen and
            // chosen back, keeps the presentation prepared for it.
            if let kept = pager.presentation(for: key) {
                presentation = kept
                pager.setOutline(kept.outlineEntries, for: page)
                return
            }
            presentation = nil
            preparedScores = nil

            let office = office
            let preparationTask = Task.detached(
                priority: .userInitiated
            ) {
                try OfficeReaderPresentation.prepare(
                    office: office,
                    usesCompactPsalmody: key.usesCompactPsalmody,
                    showsOrdinary: key.showsOrdinary,
                    showsScores: key.showsScores
                )
            }
            do {
                let prepared = try await withTaskCancellationHandler {
                    try await preparationTask.value
                } onCancel: {
                    preparationTask.cancel()
                }
                try Task.checkCancellation()
                guard prepared.officeID == office.id else { return }
                pager.keep(prepared, for: key)
                pager.setOutline(prepared.outlineEntries, for: page)
                presentation = prepared
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            transientState.sectionJumpToken = nil
            transientState.protectedAnchor = nil
            saveScrollOffset()
        }
    }

    private func sectionView(
        index: Int,
        section: OfficeSection,
        sections: [OfficeSection],
        preparedScores: PreparedOfficeScores,
        firstChantSectionID: String?,
        geometry: GeometryProxy,
        proxy: ScrollViewProxy
    ) -> some View {
        OfficeSectionView(
            section: section,
            isMass: office.isMass,
            isFollowedByContinuation: sections.indices.contains(index + 1)
                && sections[index + 1].title.isEmpty,
            showsLatin: isLatin,
            showsChant: model.showsChant,
            usesCompactPsalmody:
                model.usesCompactPsalmody,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent,
            contentScale: readerScale,
            scorePreparation: section.chant.flatMap {
                preparedScores.scores[$0.id]
            },
            isCantorGuideScore:
                CantorGuideHighlightScope.isActive(
                    sectionID: section.id,
                    selectedSectionID:
                        selectedScoreSectionID
                ),
            isAppTourFirstChant:
                section.id == firstChantSectionID,
            onTapEvent: { score, eventID in
                transientState.sectionJumpToken = nil
                transientState.protectedAnchor = nil
                if tour.step == .tapFirstNeume {
                    playback.scholaPitch = .a
                }
                selectedScore = score
                selectedScoreSectionID = section.id
                #if DEBUG
                if Self.uiTestSimulatesCantorFollow {
                    playback.simulateViewportFollow(
                        score: score,
                        fromEventID: eventID
                    )
                } else {
                    playback.play(
                        score: score,
                        fromEventID: eventID
                    )
                }
                #else
                playback.play(
                    score: score,
                    fromEventID: eventID
                )
                #endif
                tour.receive(.cantorGuideOpened)
            },
            onActiveNeumeFrameChange: { activeNeume in
                cantorTracking.latestActiveNeume = activeNeume
                if Self.uiTestSimulatesCantorFollow,
                   cantorTracking.uiTestInitialActiveNeume == nil {
                    cantorTracking.uiTestInitialActiveNeume = activeNeume
                }
                track(
                    activeNeume,
                    readerFrame: geometry.frame(in: .global),
                    using: proxy
                )
            }
        )
        .id(section.id)
        .background {
            OfficeReaderScrollViewAccessor { scrollView, view in
                transientState.scrollView = scrollView
                transientState.registerSectionView(view, for: section.id)
            }
        }
    }

    private var preparingOffice: some View {
        VStack(spacing: 18) {
            ProgressView()
            Text("Preparing chant notation…")
                .font(.custom("EBGaramond-Regular", size: 20, relativeTo: .body))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("office-reader-preparing-notation")
    }

    private func track(
        _ activeNeume: ActiveNeumeFrame,
        readerFrame: CGRect,
        using proxy: ScrollViewProxy
    ) {
        guard selectedScore != nil,
              activeNeume.eventID == playback.currentEventID else {
            cantorTracking.automaticScrollTargetID = nil
            return
        }

        guard let cantorGuideFrame = cantorTracking.cantorGuideFrame else {
            return
        }
        guard let anchorY = CantorGuideViewportTracking.scrollAnchorY(
            activeFrame: activeNeume.frame,
            readerFrame: readerFrame,
            obscuredBottomHeight: max(
                0,
                readerFrame.maxY - cantorGuideFrame.minY
            )
        ) else {
            cantorTracking.automaticScrollTargetID = nil
            return
        }
        guard cantorTracking.automaticScrollTargetID
            != activeNeume.scrollTargetID else {
            return
        }

        cantorTracking.automaticScrollTargetID = activeNeume.scrollTargetID
        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(
                activeNeume.scrollTargetID,
                anchor: UnitPoint(x: 0.5, y: anchorY)
            )
        }
    }

    /// Half as tall again as the reader's scroll view, which runs under the
    /// bars. See `OfficeReaderBlockBuilder`.
    private static func minimumBlockHeight(in geometry: GeometryProxy) -> CGFloat {
        let insets = geometry.safeAreaInsets
        return 1.5 * (geometry.size.height + insets.top + insets.bottom)
    }

    private func sectionHeightFloors(
        of sections: [OfficeSection],
        scores: [String: GregorianScorePreparation],
        columnWidth: CGFloat
    ) -> [CGFloat] {
        // The reader's smallest running text: a psalm verse, as
        // `SelectableTextView` sets it.
        let size = 21 * readerScale
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont(name: "EBGaramond-Regular", size: size)
                ?? UIFont.systemFont(ofSize: size),
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)
            )
        )
        return OfficeReaderBlockBuilder.heightFloors(
            of: sections,
            scoreHeights: scores.mapValues(\.height),
            textLineHeight: font.lineHeight,
            textCharactersPerLine: OfficeReaderBlockBuilder.charactersPerLine(
                columnWidth: columnWidth,
                pointSize: font.pointSize
            )
        )
    }

    /// Brings a section to the top of the reader. The lazy stack can find a
    /// section only in a block it has laid out; until then the block itself
    /// is brought up, and the section can be found once it is there.
    private func scroll(
        toTopOf sectionID: String,
        in blocks: [OfficeReaderBlock],
        using proxy: ScrollViewProxy
    ) {
        if transientState.sectionFrames[sectionID] != nil {
            proxy.scrollTo(sectionID, anchor: .top)
        } else if let block = sectionID == Self.topAnchorID
                    ? blocks.first
                    : blocks.first(where: { $0.sectionIDs.contains(sectionID) }) {
            proxy.scrollTo(block.id, anchor: .top)
        }
    }

    private func jump(
        to sectionID: String,
        in blocks: [OfficeReaderBlock],
        using proxy: ScrollViewProxy
    ) {
        transientState.protectedAnchor = nil
        transientState.userInterruptedRestoration = true
        transientState.hasAppliedInitialScroll = true
        let token = UUID()
        transientState.sectionJumpToken = token
        Task { @MainActor in
            await Task.yield()
            guard transientState.sectionJumpToken == token else { return }
            // First materialize the destination. An animated jump continues
            // writing its estimated offset after the lazy sections have grown.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scroll(toTopOf: sectionID, in: blocks, using: proxy)
            }
            var settledPasses = 0
            for _ in 0..<30 {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
                guard transientState.sectionJumpToken == token,
                      scenePhase == .active,
                      let scrollView = transientState.scrollView,
                      !scrollView.isTracking, !scrollView.isDragging,
                      !scrollView.isDecelerating else { return }
                guard let frame = transientState.sectionFrames[sectionID] else {
                    withTransaction(transaction) {
                        scroll(toTopOf: sectionID, in: blocks, using: proxy)
                    }
                    continue
                }
                let current = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                let maximum = max(0, scrollView.contentSize.height
                    + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
                    - scrollView.bounds.height)
                let target = OfficeReaderScrollRestoration.offset(
                    Double(current + frame.minY), maximumOffset: maximum
                )
                if abs(target - current) <= 1 {
                    settledPasses += 1
                    if settledPasses >= 3 {
                        saveScrollOffset()
                        transientState.protectedAnchor = OfficeReaderScrollAnchor(
                            sectionID: sectionID, viewportY: Double(frame.minY)
                        )
                        transientState.sectionJumpToken = nil
                        return
                    }
                } else {
                    settledPasses = 0
                    scrollView.setContentOffset(
                        CGPoint(x: scrollView.contentOffset.x,
                            y: target - scrollView.adjustedContentInset.top), animated: false
                    )
                }
            }
            if transientState.sectionJumpToken == token {
                transientState.sectionJumpToken = nil
            }
        }
    }

    /// The reading line's height in the reading area, a quarter of the way
    /// down it (see `OfficeReaderPageTurn.readingLineFraction`).
    private static func readingLine(of scrollView: UIScrollView) -> CGFloat {
        let height = scrollView.bounds.height - scrollView.adjustedContentInset.top
            - scrollView.adjustedContentInset.bottom
        return max(0, height) * OfficeReaderPageTurn.readingLineFraction
    }

    /// Where the reader reads on this page.
    private func readingPlace() -> OfficeReaderPageTurn.ReadingPlace? {
        guard let scrollView = transientState.scrollView else { return nil }
        return OfficeReaderPageTurn.readingPlace(
            in: transientState.sectionFrames,
            lineY: Self.readingLine(of: scrollView)
        )
    }

    /// The offset that sets the page at a placement, where what the
    /// placement needs is laid out; else the section to bring into the lazy
    /// stack's layout first. Nil where the page has nothing to stand for it.
    private func target(
        for placement: OfficeReaderPagePlacement,
        among sectionIDs: Set<String>,
        in scrollView: UIScrollView
    ) -> OfficeReaderPlacementTarget? {
        let frames = transientState.sectionFrames
        let sectionID: String
        let top: CGFloat?
        switch placement {
        case let .anchor(anchor):
            guard sectionIDs.contains(anchor.sectionID) else { return nil }
            sectionID = anchor.sectionID
            top = CGFloat(anchor.viewportY)
        case let .reading(place):
            guard let placed = OfficeReaderPageTurn.placement(
                of: place,
                in: frames,
                among: sectionIDs,
                lineY: Self.readingLine(of: scrollView)
            ) else { return nil }
            sectionID = placed.sectionID
            top = placed.top
        }
        guard let top, let frame = frames[sectionID] else { return .section(sectionID) }
        let current = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        return .offset(OfficeReaderScrollRestoration.offset(
            Double(current + frame.minY - top),
            maximumOffset: Self.maximumOffset(of: scrollView)
        ))
    }

    /// Sets the page at once at the words read on the other, where they are
    /// laid out, as the facing page is set before a drag shows it. Says
    /// whether the page now stands there.
    private func placeNow(
        at place: OfficeReaderPageTurn.ReadingPlace,
        among sectionIDs: Set<String>
    ) -> Bool {
        guard let scrollView = transientState.scrollView,
              case let .offset(target)? = target(
                  for: .reading(place),
                  among: sectionIDs,
                  in: scrollView
              ) else {
            return false
        }
        transientState.userInterruptedRestoration = true
        transientState.sectionJumpToken = nil
        let current = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        if abs(target - current) > 1 {
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: target - scrollView.adjustedContentInset.top),
                animated: false
            )
        }
        let anchor = OfficeReaderScrollRestoration.anchor(in: transientState.sectionFrames)
        transientState.hasAppliedInitialScroll = true
        transientState.savedAnchor = anchor
        transientState.protectedAnchor = anchor
        return abs(target - current) <= 1
    }

    /// Brings the page to the words the reader reads on the other page, so
    /// that a turn shows them at the same height, however much longer or
    /// shorter this page sets them. The lazy stack lays out what it finds
    /// on the way, so they are sought until the page stands still there.
    /// Says whether it does.
    private func align(
        to place: OfficeReaderPageTurn.ReadingPlace,
        among sectionIDs: Set<String>,
        in blocks: [OfficeReaderBlock],
        using proxy: ScrollViewProxy
    ) async -> Bool {
        let interval = OfficeReaderPageTurn.signposter.beginInterval("ReaderPageAlignment")
        defer { OfficeReaderPageTurn.signposter.endInterval("ReaderPageAlignment", interval) }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        var settledPasses = 0
        var hasMoved = false
        var hasTakenOver = false
        passes: for _ in 0..<40 {
            guard !Task.isCancelled else { return false }
            // A page just laid out may not yet have found its scroll view.
            if let scrollView = transientState.scrollView {
                guard !scrollView.isTracking, !scrollView.isDragging else { return false }
                if !hasTakenOver {
                    // The page's own restoration gives way.
                    hasTakenOver = true
                    transientState.userInterruptedRestoration = true
                    transientState.sectionJumpToken = nil
                    transientState.protectedAnchor = nil
                }
                switch target(for: .reading(place), among: sectionIDs, in: scrollView) {
                case let .offset(target)?:
                    let current = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                    if abs(target - current) <= 1 {
                        settledPasses += 1
                        // In place at the first look: it was set there before.
                        if !hasMoved || settledPasses >= 2 { break passes }
                    } else {
                        hasMoved = true
                        settledPasses = 0
                        scrollView.setContentOffset(
                            CGPoint(x: scrollView.contentOffset.x, y: target - scrollView.adjustedContentInset.top),
                            animated: false
                        )
                    }
                case let .section(sectionID)?:
                    hasMoved = true
                    withTransaction(transaction) {
                        scroll(toTopOf: sectionID, in: blocks, using: proxy)
                    }
                case nil:
                    return false
                }
            }
            do { try await Task.sleep(for: .milliseconds(16)) }
            catch { return false }
        }
        guard hasTakenOver else { return false }
        let anchor = OfficeReaderScrollRestoration.anchor(in: transientState.sectionFrames)
        transientState.hasAppliedInitialScroll = true
        transientState.savedAnchor = anchor
        transientState.protectedAnchor = anchor
        return settledPasses > 0
    }

    private static func maximumOffset(of scrollView: UIScrollView) -> CGFloat {
        max(
            0,
            scrollView.contentSize.height + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        )
    }

    private func saveScrollOffset() {
        guard transientState.hasAppliedInitialScroll, transientState.hasScrollGeometry else { return }
        // Geometry and its section anchor are captured together while active;
        // background snapshots may already have resized the native view.
        let offset = Double(transientState.latestScrollOffset)
        let anchor = scenePhase == .active
            ? OfficeReaderScrollRestoration.anchor(in: transientState.sectionFrames)
            : transientState.latestScrollAnchor
        transientState.savedOffset = offset
        transientState.savedAnchor = anchor
        // The facing page follows the page shown, and keeps no place of its own.
        if isShown {
            onSettle(offset, anchor, scenePhase == .active ? readingPlace() : nil)
        }
    }

    private func restoreScrollPosition(
        sections: [OfficeSection],
        blocks: [OfficeReaderBlock],
        using proxy: ScrollViewProxy
    ) async {
        // This task also runs when score preparation recreates the ScrollView.
        // Capture the last settled position before new layout can overwrite it.
        let sectionIDs = Set(sections.map(\.id)).union([Self.topAnchorID])
        let savedOffset = transientState.savedOffset ?? restoredScrollOffset ?? 0
        let uiTestSectionID = Self.uiTestScoreID.flatMap { scoreID in
            sections.first(where: { $0.chant?.id == scoreID })?.id
        } ?? Self.uiTestSectionID
        // A UI test may ask for a section; it opens there as a saved place
        // would. A page laid out since the reader opened stands at the
        // words read on the page shown before it.
        let placement: OfficeReaderPagePlacement? = uiTestSectionID.map {
            .anchor(OfficeReaderScrollAnchor(sectionID: $0, viewportY: 0))
        } ?? transientState.savedAnchor.map { .anchor($0) }
            ?? pager.reading.map { .reading($0) }
            ?? pager.openingAnchor.map { .anchor($0) }
        transientState.protectedAnchor = nil
        transientState.hasAppliedInitialScroll = false
        transientState.userInterruptedRestoration = false
        defer { pager.markReady(page) }
        await Task.yield()
        guard !Task.isCancelled else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        var settledPasses = 0
        for _ in 0..<30 {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            guard !transientState.userInterruptedRestoration else { return }
            guard scenePhase == .active, transientState.hasScrollGeometry,
                  let scrollView = transientState.scrollView else { continue }
            let currentOffset = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
            // Read the native range alongside the native offset. SwiftUI's
            // last geometry event may still describe the pre-layout range.
            let target: CGFloat
            switch placement.flatMap({ self.target(for: $0, among: sectionIDs, in: scrollView) }) {
            case let .offset(offset)?:
                target = offset
            case let .section(sectionID)?:
                // Resolve the actual section first; a lazy stack's total
                // height is only an estimate until the surrounding chant
                // views are laid out.
                withTransaction(transaction) {
                    scroll(toTopOf: sectionID, in: blocks, using: proxy)
                }
                continue
            case nil:
                target = OfficeReaderScrollRestoration.offset(
                    savedOffset,
                    maximumOffset: Self.maximumOffset(of: scrollView)
                )
            }
            if abs(target - currentOffset) <= 1 {
                settledPasses += 1
                if settledPasses >= 3 { break }
            } else {
                settledPasses = 0
                // A saved point must never become a persistent bottom-edge
                // request as the lazy content grows during restoration.
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: target - scrollView.adjustedContentInset.top),
                    animated: false
                )
            }
        }
        guard !Task.isCancelled else { return }
        transientState.hasAppliedInitialScroll = true
        if settledPasses >= 3 {
            saveScrollOffset()
            transientState.protectedAnchor = transientState.savedAnchor
        }
    }

    private static var uiTestSectionID: String? {
        uiTestArgument(after: "--ui-test-reader-section")
    }

    private static var uiTestScoreID: String? {
        uiTestArgument(after: "--ui-test-reader-score")
    }

    private static func uiTestArgument(after flag: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let argumentIndex = arguments.firstIndex(
            of: flag
        ) else {
            return nil
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
        #else
        return nil
        #endif
    }

    private static var uiTestSimulatesCantorFollow: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(
            "--ui-test-cantor-follow"
        )
        #else
        false
        #endif
    }

    private var uiTestCantorTrackingIdentifier: String {
        #if DEBUG
        guard Self.uiTestSimulatesCantorFollow,
              cantorTracking.uiTestOpeningWasPreserved == true,
              let initialActiveNeume = cantorTracking.uiTestInitialActiveNeume,
              let activeNeume = cantorTracking.latestActiveNeume,
              let cantorGuideFrame = cantorTracking.cantorGuideFrame,
              activeNeume.eventID != initialActiveNeume.eventID,
              activeNeume.frame.maxY <= cantorGuideFrame.minY - 20 else {
            return "cantor-guide-bar"
        }
        return "cantor-tracking-passed"
        #else
        "cantor-guide-bar"
        #endif
    }

    private func scheduleUITestOpeningCheck() {
        #if DEBUG
        guard Self.uiTestSimulatesCantorFollow,
              !cantorTracking.uiTestOpeningCheckIsScheduled else {
            return
        }
        cantorTracking.uiTestOpeningCheckIsScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let initialActiveNeume =
                    cantorTracking.uiTestInitialActiveNeume,
                  let activeNeume = cantorTracking.latestActiveNeume,
                  activeNeume.eventID == initialActiveNeume.eventID else {
                cantorTracking.uiTestOpeningWasPreserved = false
                return
            }
            cantorTracking.uiTestOpeningWasPreserved = abs(
                activeNeume.frame.midY - initialActiveNeume.frame.midY
            ) <= 20
        }
        #endif
    }
}

/// The head of a page of the reader: the day's rank, the Hour's title and
/// the observance, in the language of the page.
private struct OfficeReaderHeader: View {
    let office: OfficeDocument
    let page: ReaderPage
    let readerScale: CGFloat

    @Environment(AppModel.self) private var model

    var body: some View {
        let isLatin = page == .latin
        let observanceLatin = ObservanceTitle.latin(
            office.observance?.titleLatin ?? office.contextLabel
        )
        let observanceEnglish = office.observance?.titleEnglish.map(
            ObservanceTitle.english
        )
        VStack(spacing: 10) {
            if model.isDevelopmentCorpus {
                Text("DEVELOPMENT CORPUS")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("development-corpus-banner")
            }

            Text(
                office.observance?.rankLabel
                    // Home's day's, but not for a Mass of another day.
                    ?? model.selectedDay.flatMap {
                        !office.isMass || $0.date == office.date ? $0.rankLabel : nil
                    }
                    ?? office.englishName
            )
                .font(
                    .custom(
                        "EBGaramond-Regular",
                        size: 18 * readerScale,
                        relativeTo: .body
                    )
                )
                .foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
                .accessibilityIdentifier("office-rank-label")

            if model.officeTradition != .roman1960 {
                Text(model.officeTradition.title)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("office-tradition-label")
            }

            Text(
                isLatin
                    ? office.titleLatin
                    : office.titleEnglish.flatMap { $0.isEmpty ? nil : $0 } ?? office.titleLatin
            )
                .font(
                    .custom(
                        "EBGaramond-Regular",
                        size: 43 * readerScale,
                        relativeTo: .largeTitle
                    )
                )
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineSpacing(-4 * readerScale)
                .accessibilityIdentifier("office-reader-title")

            Text(isLatin ? observanceLatin : observanceEnglish ?? observanceLatin)
                .font(
                    .custom(
                        "EBGaramond-Regular",
                        size: 19 * readerScale,
                        relativeTo: .body
                    )
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 38)
        .frame(maxWidth: .infinity)
    }
}

struct OfficeReaderPresentationKey: Hashable {
    let officeID: String
    let usesCompactPsalmody: Bool
    let showsOrdinary: Bool
    let showsScores: Bool
}

/// Where a page of the reader is to stand: a section at a height on the
/// screen, as the page itself was left; or at the words the reader reads
/// on the other page.
private enum OfficeReaderPagePlacement {
    case anchor(OfficeReaderScrollAnchor)
    case reading(OfficeReaderPageTurn.ReadingPlace)
}

/// What sets a page at its placement: the offset, or, first, a section
/// the lazy stack has yet to lay out.
private enum OfficeReaderPlacementTarget {
    case offset(CGFloat)
    case section(String)
}

private struct OfficeReaderPassageKey: Hashable {
    let scenePhase: ScenePhase
    let isPriestOrDeaconPresent: Bool
}

nonisolated struct OfficeReaderPresentation: Sendable {
    private static let signposter = OSSignposter(
        subsystem: "com.matthewmccarty.hours",
        category: "OfficeReader"
    )

    let officeID: String
    let sections: [OfficeSection]
    let scores: [ChantScore]
    let scoreSignature: Int
    let outlineEntries: [OfficeReaderOutlineEntry]

    /// The sections as shown, and the scores to prepare: none where the
    /// chant is not shown (`showsScores`).
    static func prepare(
        office: OfficeDocument,
        usesCompactPsalmody: Bool = false,
        showsOrdinary: Bool = true,
        showsScores: Bool = true
    ) throws -> OfficeReaderPresentation {
        let interval = signposter.beginInterval(
            "ReaderPresentationPreparation"
        )
        defer {
            signposter.endInterval(
                "ReaderPresentationPreparation",
                interval
            )
        }

        try Task.checkCancellation()
        let sections = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format,
            usesCompactPsalmody: usesCompactPsalmody,
            showsOrdinary: showsOrdinary,
            showsScores: showsScores
        )
        try Task.checkCancellation()

        var seenScoreIDs: Set<String> = []
        let scores = showsScores
            ? sections.compactMap(\.chant).filter {
                seenScoreIDs.insert($0.id).inserted
            }
            : []
        var hasher = Hasher()
        for score in scores {
            try Task.checkCancellation()
            hasher.combine(score.id)
            hasher.combine(score.gabc)
            hasher.combine(score.mode)
            hasher.combine(score.timeline.events.count)
        }
        try Task.checkCancellation()

        return OfficeReaderPresentation(
            officeID: office.id,
            sections: sections,
            scores: scores,
            scoreSignature: hasher.finalize(),
            outlineEntries: OfficeReaderOutlineBuilder.entries(
                from: sections
            )
        )
    }
}

nonisolated struct OfficeReaderOutlineEntry: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

nonisolated enum OfficeReaderSectionJump {
    /// Sheet rows must not reuse reader section IDs. `ScrollViewReader`
    /// matches the first view with that ID, and the still-presented outline
    /// row is in the hierarchy before a lazy hymn has been realized.
    static func outlineRowID(for sectionID: String) -> String {
        "office-outline-row-\(sectionID)"
    }
}

private struct OfficeSectionsSheetRow: Identifiable {
    let entry: OfficeReaderOutlineEntry

    var id: String {
        OfficeReaderSectionJump.outlineRowID(for: entry.id)
    }
}

nonisolated enum OfficeReaderOutlineBuilder {
    static func entries(
        from sections: [OfficeSection]
    ) -> [OfficeReaderOutlineEntry] {
        sections.compactMap { section in
            let title = outlineTitle(for: section)
            guard !title.isEmpty else { return nil }
            return OfficeReaderOutlineEntry(
                id: section.id,
                title: title
            )
        }
    }

    private static func outlineTitle(for section: OfficeSection) -> String {
        let title = section.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !title.isEmpty {
            return title
        }

        // The ordered Matins source stores lesson and Te Deum labels as
        // content inside the broader "Pater" part. Repeated-heading
        // suppression correctly hides that inherited part title, so recover
        // these explicit structural labels for the jump outline itself.
        let latin = section.latin.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if isNumberedLessonTitle(latin) {
            return latin
        }
        if normalizedWords(latin).starts(with: ["te", "deum", "laudamus"]) {
            return "Te Deum"
        }
        return ""
    }

    private static func isNumberedLessonTitle(_ value: String) -> Bool {
        let parts = value.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              parts[0].localizedCaseInsensitiveCompare("Lectio") == .orderedSame,
              let number = Int(parts[1])
        else {
            return false
        }
        return number > 0
    }

    private static func normalizedWords(_ value: String) -> [String] {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "la")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

/// Brings the first chant to the top when the tour asks for its first neume.
/// It reads the tour for itself: the reader, whose sections are laid out
/// lazily, is not made anew at each step of the tour.
private struct AppTourFirstChantScroll: View {
    @Environment(AppTourCoordinator.self) private var tour
    let sectionID: String?
    let scroll: (String) -> Void

    var body: some View {
        Color.clear
            .task(id: tour.step) {
                guard tour.step == .tapFirstNeume,
                      let sectionID else { return }
                await Task.yield()
                scroll(sectionID)
            }
    }
}

private struct OfficeSectionsSheet: View {
    let entries: [OfficeReaderOutlineEntry]
    let onSelect: (OfficeReaderOutlineEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTourCoordinator.self) private var tour

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries.map(OfficeSectionsSheetRow.init)) { row in
                    let entry = row.entry
                    Button {
                        guard !tour.isActive
                                || tour.step == .chooseOratio else {
                            return
                        }
                        onSelect(entry)
                    } label: {
                        Text(entry.title)
                            .font(
                                .custom(
                                    "EBGaramond-Regular",
                                    size: 21,
                                    relativeTo: .body
                                )
                            )
                            .foregroundStyle(Color.hoursPrimaryText)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 56,
                                alignment: .leading
                            )
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(entry.title)")
                    .accessibilityIdentifier(
                        Self.isOratio(entry.title)
                            ? "tour-reader-oratio"
                            : "office-outline-jump-\(entry.id)"
                    )
                    .id(row.id)
                    .appTourTarget(
                        .readerOratio,
                        when: Self.isOratio(entry.title)
                    )
                }
                .listStyle(.plain)
                .task(id: tour.step) {
                    guard tour.step == .chooseOratio,
                          let entry = entries.first(where: {
                              Self.isOratio($0.title)
                          }) else { return }
                    await Task.yield()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(
                            OfficeReaderSectionJump.outlineRowID(
                                for: entry.id
                            ),
                            anchor: .center
                        )
                    }
                }
                .navigationTitle("Office sections")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetCloseButton(
                            accessibilityLabel: "Close Office Sections",
                            accessibilityIdentifier: "office-sections-close",
                            action: dismiss.callAsFunction
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("office-sections-sheet")
        .onAppear {
            tour.receive(.readerContentsOpened)
        }
    }

    private static func isOratio(_ title: String) -> Bool {
        title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "la")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines) == "oratio"
    }
}

/// Consecutive sections that the reader lays out together, as one child of
/// its lazy stack.
nonisolated struct OfficeReaderBlock: Equatable, Identifiable, Sendable {
    let id: String
    let sectionRange: Range<Int>
    let sectionIDs: [String]
}

/// Gathers an office's sections into the blocks its reader lays out lazily.
///
/// SwiftUI keeps a child of a lazy stack that lies below the screen only
/// while the child begins more than about a screen above the stack's end, and
/// it reckons that end by counting each child not laid out at the average
/// height of those it has measured. A child shorter than a screen can thus be
/// dropped for standing too near the end, move the reckoned end by being
/// dropped, and be laid out again. After a jump from the contents to the
/// Oratio of Vespers, whose closing versicles then stood just below the
/// screen, this went on without end as soon as the app was left, and the
/// reader stopped answering. A block taller than the screen always begins
/// far enough above the end to be kept.
nonisolated enum OfficeReaderBlockBuilder {
    /// The height of a score whose layout was not prepared.
    private static let unpreparedScoreHeight: CGFloat = 112

    /// The most characters that stand on a line of running text. Latin prose
    /// in the reader's face averages some 0.39 of its point size to the
    /// character; 0.3 leaves room for lines of narrow letters, so that a
    /// text's lines are counted too few rather than too many.
    static func charactersPerLine(
        columnWidth: CGFloat,
        pointSize: CGFloat
    ) -> CGFloat {
        max(1, columnWidth / (0.3 * max(1, pointSize)))
    }

    /// A height each section is sure to reach: that of its score, or of its
    /// Latin in the reader's smallest running text. Its heading, rubric,
    /// translation and padding only add to it.
    static func heightFloors(
        of sections: [OfficeSection],
        scoreHeights: [String: CGFloat],
        textLineHeight: CGFloat,
        textCharactersPerLine: CGFloat
    ) -> [CGFloat] {
        sections.map { section in
            let lines = (
                CGFloat(section.latin.count) / max(1, textCharactersPerLine)
            ).rounded(.up)
            let textHeight = max(1, lines) * textLineHeight
            guard let chant = section.chant else { return textHeight }
            let scoreHeight = scoreHeights[chant.id] ?? unpreparedScoreHeight
            // A greeting that clergy say otherwise is set as text, in place
            // of its score, when a priest or deacon is present.
            return OfficePrayerText.requiresTextFallback(
                for: section,
                isPriestOrDeaconPresent: true
            ) ? min(scoreHeight, textHeight) : scoreHeight
        }
    }

    /// Blocks whose sections' floors together reach `minimumHeight`. Sections
    /// left over at the end, too few to make a block, join the last; an
    /// office that does not reach `minimumHeight` is a single block.
    static func blocks(
        of sections: [OfficeSection],
        heightFloors: [CGFloat],
        minimumHeight: CGFloat
    ) -> [OfficeReaderBlock] {
        var ranges: [Range<Int>] = []
        var start = 0
        var height: CGFloat = 0
        for index in sections.indices {
            if heightFloors.indices.contains(index) {
                height += max(0, heightFloors[index])
            }
            if height >= minimumHeight {
                ranges.append(start..<(index + 1))
                start = index + 1
                height = 0
            }
        }
        if start < sections.count || ranges.isEmpty {
            let lowerBound = ranges.popLast()?.lowerBound ?? 0
            ranges.append(lowerBound..<sections.count)
        }
        return ranges.map { range in
            let sectionIDs = sections[range].map(\.id)
            return OfficeReaderBlock(
                id: "office-reader-block-\(sectionIDs.first ?? "")",
                sectionRange: range,
                sectionIDs: sectionIDs
            )
        }
    }
}

private struct ScorePreparationKey: Hashable {
    let officeID: String
    let scoreSignature: Int
    let width: Int
    let notationScale: Int
    let lyricScale: Int
    let displayScale: Int
}

private struct PreparedOfficeScores {
    let key: ScorePreparationKey
    let scores: [String: GregorianScorePreparation]
    /// A height each section is sure to reach, by which sections are
    /// gathered into the blocks the reader lays out lazily.
    let sectionHeightFloors: [CGFloat]
}

enum CantorGuideHighlightScope {
    static func isActive(
        sectionID: String,
        selectedSectionID: String?
    ) -> Bool {
        sectionID == selectedSectionID
    }
}

@Observable
private final class CantorGuideTrackingState {
    // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    var automaticScrollTargetID: String?
    var cantorGuideFrame: CGRect?
    var latestActiveNeume: ActiveNeumeFrame?
    var uiTestInitialActiveNeume: ActiveNeumeFrame?
    var uiTestOpeningWasPreserved: Bool?
    var uiTestOpeningCheckIsScheduled = false

    func reset() {
        automaticScrollTargetID = nil
        cantorGuideFrame = nil
        latestActiveNeume = nil
        uiTestInitialActiveNeume = nil
        uiTestOpeningWasPreserved = nil
        uiTestOpeningCheckIsScheduled = false
    }
}

enum CantorGuideViewportTracking {
    private static let bottomMargin: CGFloat = 24

    static func scrollAnchorY(
        activeFrame: CGRect,
        readerFrame: CGRect,
        obscuredBottomHeight: CGFloat
    ) -> CGFloat? {
        guard readerFrame.height > 0 else { return nil }

        let visibleTop = readerFrame.minY
        let visibleBottom = readerFrame.maxY
            - max(0, obscuredBottomHeight)
            - bottomMargin
        guard visibleBottom > visibleTop else { return 0.5 }

        let isVisible = activeFrame.minY >= visibleTop
            && activeFrame.maxY <= visibleBottom
        guard !isVisible else { return nil }

        let visibleCenter = (visibleTop + visibleBottom) / 2
        return min(
            1,
            max(0, (visibleCenter - readerFrame.minY) / readerFrame.height)
        )
    }
}

nonisolated enum OfficeReaderSectionBuilder {
    /// The end of the identifier of the rest of a psalm that compact
    /// psalmody sets after the verse sung from its score.
    static let compactContinuationSuffix = "-compact-continuation"

    /// The sections as the reader shows them. A Mass shows its Ordinary
    /// unless `showsOrdinary` is false, when it shows the propers alone.
    /// Where the chant is not shown (`showsScores`), the words its scores
    /// alone hold are written out (writingOutSungWords).
    static func displaySections(
        from source: [OfficeSection],
        format: OfficeDocument.Format?,
        usesCompactPsalmody: Bool = false,
        showsOrdinary: Bool = true,
        showsScores: Bool = true
    ) -> [OfficeSection] {
        if format == .missal {
            // A Mass is set out by its compiler in the Missal's order and
            // words; none of the Office's arrangements applies to it.
            return showingCrossSigns(
                in: showsOrdinary ? source : source.filter { !$0.isOrdinary }
            )
        }
        let arranged = arrangedSections(
            from: source,
            format: format,
            usesCompactPsalmody: usesCompactPsalmody && showsScores
        )
        // Last of all, so that the words a chant alone holds are read by
        // nothing that arranges the sections, and a mark is lost in no
        // rearrangement.
        let sections = settingEnglishOfSungParts(
            in: OfficePrayerText.markingWhatAllSay(in: OfficePrayerText.writingOutSungLayForms(in: arranged))
        )
        return showsScores ? sections : writingOutSungWords(in: sections)
    }

    private static func arrangedSections(
        from source: [OfficeSection],
        format: OfficeDocument.Format?,
        usesCompactPsalmody: Bool
    ) -> [OfficeSection] {
        if format == .sourceOrdered {
            // Source imports are already in liturgical order. Never run the
            // Roman reconstruction/correction heuristics over a source-ordered office:
            // its antiphons, including those repeated between the strophes of a
            // psalm, are printed in both languages and none is spurious.
            let source = suppressingRepeatedHeadings(
                SourceOfficeTextPresentation.sections(
                    OfficePrayerText.groupingDeadOfficeGreeting(in: source)
                )
            )
            return showingDirectionsAsRubrics(in: showingCrossSigns(in: usesCompactPsalmody
                ? compactingPsalmody(in: source, usesSourceLineBreaks: true)
                : source))
        }
        let presentationSource = format == .authoritativeOrdered
            ? correctedSource(
                source,
                preservesUnnumberedAntiphons: true
            )
            : source
        let source = withCorrectedHeadings(in: withoutPrintedHeadings(
            in: correctingNumberedLessonTranslations(presentationSource)
        ))
        let displayed: [OfficeSection]
        if format == .authoritativeOrdered {
            // The authoritative corpus repeats a part's title on each atomic
            // prayer or score across every hour. Preserve its order, fold
            // prose that is actually covered by a score into that score, and
            // present one heading for the whole office part.
            displayed = suppressingRepeatedHeadings(
                interleavingTextWithNonPsalmChants(
                    source,
                    allowsTitleFallback: false
                )
            )
        } else {
            displayed = sections(from: source)
        }
        let restored = restoringPsalmodyEnglish(in: displayed)
        guard usesCompactPsalmody else { return showingDirectionsAsRubrics(in: showingCrossSigns(in: restored)) }
        return showingDirectionsAsRubrics(in: showingCrossSigns(in: compactingPsalmody(in: restored)))
    }

    /// The ordered corpus repeats a part's heading, with its source note, as
    /// the first line of the part's text ("Oratio {ex Proprio Sanctorum}").
    /// The heading and the note are shown already, so that line is omitted; a
    /// psalm-division counter ("Canticum Isaiæ [4]") is not part of a heading.
    private static func withoutPrintedHeadings(in sections: [OfficeSection]) -> [OfficeSection] {
        func withoutHeading(_ value: String?, heading: String?, note: String?) -> String? {
            guard let value, let heading, !heading.isEmpty else { return value }
            var parts = value.components(separatedBy: "\n\n")
            let first = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let printed = [heading] + (note.map { ["\(heading) {\($0)}", "\(heading) (\($0))"] } ?? [])
            guard let first, printed.contains(first) else { return value }
            parts.removeFirst()
            return parts.joined(separator: "\n\n")
        }
        return sections.map { section in
            let title = section.title.replacingOccurrences(
                of: #"\s*\[\d+\]$"#,
                with: "",
                options: .regularExpression
            )
            let latin = withoutHeading(section.latin, heading: section.title, note: section.rubric)
                ?? section.latin
            let english = withoutHeading(
                section.english,
                heading: section.titleEnglish,
                note: section.rubricEnglish
            )
            guard title != section.title || latin != section.latin || english != section.english else {
                return section
            }
            // An unchanged title is not replaced: replacing an empty one
            // would remove its translation with it.
            return section.replacingPresentation(
                title: title == section.title ? nil : title,
                latin: latin,
                english: .some(english)
            )
        }
    }

    /// Headings the source supplies mechanically: a numbered "Section" where it
    /// has none, "Capitulum Responsorium Versus" over a chapter that no short
    /// responsory follows (Lauds and Vespers, where the hymn comes next), and
    /// "Start" as the English of a short lesson or an opening.
    static func withCorrectedHeadings(in sections: [OfficeSection]) -> [OfficeSection] {
        // The chapter, its short responsory and versicle are consecutive parts
        // under one heading; a run without the responsory's versicle is a
        // chapter alone.
        let combined = "Capitulum Responsorium Versus"
        var chapterOnly = Set<Int>()
        var start = 0
        while start < sections.count {
            guard sections[start].title == combined else { start += 1; continue }
            var end = start
            while end < sections.count, sections[end].title == combined { end += 1 }
            let hasVersicle = sections[start..<end].contains {
                $0.latin.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("V/") || $0.latin.contains("℣.")
            }
            if !hasVersicle { chapterOnly.formUnion(start..<end) }
            start = end
        }
        return sections.enumerated().map { index, section in
            if section.title.range(of: #"^Section \d+$"#, options: .regularExpression) != nil {
                return section.replacingPresentation(title: "", titleEnglish: .some(nil))
            }
            if chapterOnly.contains(index) {
                return section.replacingPresentation(title: "Capitulum", titleEnglish: .some("Chapter"))
            }
            if section.titleEnglish == "Start" {
                switch section.title {
                case "Lectio brevis":
                    return section.replacingPresentation(titleEnglish: .some("Short reading"))
                case "Incipit":
                    return section.replacingPresentation(titleEnglish: .some("Beginning"))
                default:
                    break
                }
            }
            return section
        }
    }

    /// Directions printed in the source as a part of their own ("secreto",
    /// "Sequens stropha dicitur flexis genibus.") govern the part that follows,
    /// so they are shown as its rubric rather than as words to be said.
    static func showingDirectionsAsRubrics(in sections: [OfficeSection]) -> [OfficeSection] {
        let direction = #"^(?:secreto|flexis genibus|Sequens stropha dicitur flexis genibus\.|Et recto tono dicitur benedictio:|Deinde dicitur secreto|Deinde dicitur tantum Pater Noster secreto, nisi sequatur alia Hora\.)$"#
        var result: [OfficeSection] = []
        var pending: OfficeSection?
        for section in sections {
            if let held = pending {
                pending = nil
                if section.rubric == nil {
                    let inheritsHeading = section.title.isEmpty && !held.title.isEmpty
                    result.append(section.replacingPresentation(
                        title: inheritsHeading ? held.title : nil,
                        titleEnglish: inheritsHeading ? .some(held.titleEnglish) : nil,
                        rubric: .some(held.latin.trimmingCharacters(in: .whitespacesAndNewlines)),
                        rubricEnglish: .some(held.english?.trimmingCharacters(in: .whitespacesAndNewlines))
                    ))
                    continue
                }
                result.append(held)
            }
            if section.chant == nil, section.kind != .rubric,
               section.latin.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: direction, options: [.regularExpression, .caseInsensitive]) != nil {
                pending = section
            } else {
                result.append(section)
            }
        }
        if let held = pending { result.append(held) }
        return result
    }

    /// Some sources print the sign of the cross as a plus sign held in text
    /// presentation ("lábia ︎+︎ mea"); show it as the cross it stands for.
    private static func showingCrossSigns(in sections: [OfficeSection]) -> [OfficeSection] {
        let plus = "\u{FE0E}+\u{FE0E}"
        func crossed(_ value: String) -> String {
            value.replacingOccurrences(of: plus, with: "✠", options: .literal)
        }
        return sections.map { section in
            let latin = crossed(section.latin)
            let english = section.english.map(crossed)
            guard latin != section.latin || english != section.english else { return section }
            return section.replacingPresentation(latin: latin, english: .some(english))
        }
    }

    private static func restoringPsalmodyEnglish(
        in source: [OfficeSection]
    ) -> [OfficeSection] {
        source.map { section in
            guard section.kind == .psalm || section.kind == .canticle,
                  let english = section.english else {
                return section
            }
            let restored = removingEmbeddedAntiphonParagraphs(from: english)
            guard restored != english else { return section }
            return section.replacingPresentation(english: restored)
        }
    }

    private static func removingEmbeddedAntiphonParagraphs(
        from english: String
    ) -> String {
        let values = paragraphs(in: english)
        guard values.count > 2 else { return english }
        let retained = values.enumerated().compactMap { index, paragraph -> String? in
            guard isAntiphonParagraph(paragraph),
                  index > values.startIndex,
                  index < values.index(before: values.endIndex),
                  let previous = scriptureReference(in: values[index - 1]),
                  let next = scriptureReference(in: values[index + 1]),
                  previous.psalm == next.psalm,
                  next.verse == previous.verse + 1 else {
                return paragraph
            }
            return nil
        }
        return retained == values ? english : retained.joined(separator: "\n\n")
    }

    private static func correctingNumberedLessonTranslations(
        _ source: [OfficeSection]
    ) -> [OfficeSection] {
        source.map { section in
            let latinParts = section.latin
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
            guard latinParts.count == 2,
                  latinParts[0].localizedCaseInsensitiveCompare("Lectio")
                    == .orderedSame,
                  let ordinal = Int(latinParts[1]),
                  ordinal > 0 else {
                return section
            }

            func corrected(_ value: String?) -> String? {
                guard let value else { return nil }
                let parts = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isWhitespace)
                guard parts.count == 2,
                      parts[0].localizedCaseInsensitiveCompare("Reading")
                        == .orderedSame,
                      Int(parts[1]) != nil else {
                    return value
                }
                return "Reading \(ordinal)"
            }

            return OfficeSection(
                id: section.id,
                kind: section.kind,
                title: section.title,
                titleEnglish: corrected(section.titleEnglish),
                rubric: section.rubric,
                rubricEnglish: section.rubricEnglish,
                latin: section.latin,
                english: corrected(section.english),
                chant: section.chant
            )
        }
    }

    static func sections(from source: [OfficeSection]) -> [OfficeSection] {
        let source = interleavingTextWithNonPsalmChants(
            interleavingCompactPsalmody(correctedSource(source))
        )
        return suppressingRepeatedHeadings(source)
    }

    private static func compactingPsalmody(
        in sections: [OfficeSection],
        usesSourceLineBreaks: Bool = false
    ) -> [OfficeSection] {
        sections.flatMap { section in
            compactPsalmodySection(section, usesSourceLineBreaks: usesSourceLineBreaks) ?? [section]
        }
    }

    private static func compactPsalmodySection(
        _ section: OfficeSection,
        usesSourceLineBreaks: Bool
    ) -> [OfficeSection]? {
        guard section.kind == .psalm || section.kind == .canticle,
              let score = section.chant,
              let parsed = try? GregorianScoreParser.parse(
                  gabc: score.gabc,
                  timeline: score.timeline
              ) else {
            return nil
        }

        let verseElements = scoredVerseElements(in: parsed)
        guard verseElements.count > 1,
              let compactGABC = firstVerseGABC(from: score.gabc) else {
            return nil
        }
        let rawPointedVerseTexts = verseElements.map {
            pointedLyricText(in: $0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pointedVerseTexts = normalizingTrailingVerseOrdinals(
            rawPointedVerseTexts
        )
        let verseTexts = pointedVerseTexts.map {
            PsalmTextFormatter.removingEmphasisMarkers(from: $0)
        }
        guard verseTexts.allSatisfy({ !$0.isEmpty }) else { return nil }

        let englishAlignment: PsalmodyEnglishAlignment?
        if let english = section.english {
            guard let alignment = aligningPsalmodyEnglish(
                usesSourceLineBreaks
                    ? english.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    : paragraphs(in: english),
                with: verseTexts
            ) else {
                // Preserve the complete bilingual section when alignment is
                // uncertain; compacting must never discard its translation.
                return nil
            }
            englishAlignment = alignment
        } else {
            englishAlignment = nil
        }

        let firstVerse = GregorianScore(elements: verseElements[0])
        let firstEventIDs = Set(firstVerse.eventIDs)
        let firstEvents = score.timeline.events.filter {
            firstEventIDs.contains($0.id)
        }
        guard firstEvents.map(\.id) == firstVerse.eventIDs else { return nil }
        let compactTimeline = ChantTimeline(events: firstEvents)
        guard let validatedCompactScore = try? GregorianScoreParser.parse(
            gabc: compactGABC,
            timeline: compactTimeline
        ), validatedCompactScore.eventIDs == firstVerse.eventIDs else {
            return nil
        }

        let firstLatin = PsalmTextFormatter.strippingVersePrefix(
            from: verseTexts[0]
        )
        let compactScore = ChantScore(
            id: "\(score.id)-compact-\(section.id)",
            incipit: firstLatin,
            gabc: compactGABC,
            mode: score.mode,
            reviewStatus: score.reviewStatus,
            provenance: score.provenance,
            timeline: compactTimeline
        )
        let firstSection = OfficeSection(
            id: section.id,
            kind: section.kind,
            title: section.title,
            titleEnglish: section.titleEnglish,
            rubric: section.rubric,
            rubricEnglish: section.rubricEnglish,
            latin: firstLatin,
            english: englishAlignment.flatMap { $0.verses[0] }.map {
                PsalmTextFormatter.strippingVersePrefix(from: $0)
            },
            chant: compactScore
        )
        let continuation = OfficeSection(
            id: section.id + compactContinuationSuffix,
            kind: section.kind,
            title: "",
            latin: pointedVerseTexts.dropFirst().joined(separator: "\n\n"),
            english: englishAlignment.map {
                serializedPsalmodyEnglish(
                    Array($0.verses.dropFirst()),
                    trailing: $0.trailing
                )
            }
        )
        return [firstSection, continuation]
    }

    struct PsalmodyEnglishAlignment {
        let verses: [String?]
        let trailing: [String]
    }

    static func aligningPsalmodyEnglish(
        _ english: [String],
        with latin: [String]
    ) -> PsalmodyEnglishAlignment? {
        guard !latin.isEmpty else { return nil }
        if english.count == latin.count {
            return PsalmodyEnglishAlignment(
                verses: english.map(Optional.some),
                trailing: []
            )
        }

        let latinDoxologyCount = latin.reversed().prefix {
            isDoxologyParagraph($0)
        }.count
        guard latinDoxologyCount > 0 else { return nil }

        let latinPsalmCount = latin.count - latinDoxologyCount
        let trailingCount = english.reversed().prefix {
            isSafePsalmodyPostlude($0)
        }.count
        let doxologyEnd = english.count - trailingCount
        guard doxologyEnd >= latinDoxologyCount else { return nil }
        let doxologyStart = doxologyEnd - latinDoxologyCount
        let psalmEnglish = Array(english.prefix(doxologyStart))
        let doxologyEnglish = Array(
            english[doxologyStart..<doxologyEnd]
        )
        let trailing = Array(english.suffix(trailingCount))
        guard doxologyEnglish.allSatisfy(isDoxologyParagraph) else {
            return nil
        }
        let filteredPsalmEnglish = psalmEnglish.filter {
            !isSafePsalmodyInterlude($0)
        }
        guard let psalmEnglish = aligningNumberedPsalmodyEnglish(
            psalmEnglish,
            count: latinPsalmCount
        ) ?? aligningNumberedPsalmodyEnglish(
            filteredPsalmEnglish,
            count: latinPsalmCount
        ) else {
            return nil
        }

        return PsalmodyEnglishAlignment(
            verses: psalmEnglish + doxologyEnglish.map(Optional.some),
            trailing: trailing
        )
    }

    private static func aligningNumberedPsalmodyEnglish(
        _ english: [String],
        count: Int
    ) -> [String?]? {
        // Biblical verse gaps do not locate missing chant lines. If the
        // paragraph count cannot be verified, retain the full bilingual score.
        guard english.count == count else { return nil }
        return english.map(Optional.some)
    }

    static func serializedPsalmodyEnglish(
        _ verses: [String?],
        trailing: [String]
    ) -> String {
        var paragraphs = verses.map {
            $0 ?? PsalmTextFormatter.missingTranslationPlaceholder
        }
        if !trailing.isEmpty, let lastIndex = paragraphs.indices.last {
            paragraphs[lastIndex] += "\n" + trailing.joined(separator: "\n")
        }
        return paragraphs.joined(separator: "\n\n")
    }

    private static func isDoxologyParagraph(_ value: String) -> Bool {
        let value = PsalmTextFormatter.strippingVersePrefix(from: value)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "la")
            )
        return value.hasPrefix("gloria patri")
            || value.hasPrefix("sicut erat")
            || value.hasPrefix("glory be to the father")
            || value.hasPrefix("as it was in the beginning")
    }

    private static func isSafePsalmodyPostlude(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("℟.")
            || value.hasPrefix("℣.")
            || value.localizedCaseInsensitiveCompare("Amen.") == .orderedSame
    }

    private static func isSafePsalmodyInterlude(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "ant."
            || value.hasPrefix("ant. ")
            || value.hasPrefix("℟.br. ")
            || value.hasPrefix("℣.br. ")
    }

    static func scoredVerseElements(
        in score: GregorianScore
    ) -> [[GregorianNotationElement]] {
        var verses: [[GregorianNotationElement]] = []
        var current: [GregorianNotationElement] = []

        for element in score.elements {
            current.append(element)
            if case .division(.final) = element {
                if !GregorianScore(elements: current).lyricText.isEmpty {
                    verses.append(current)
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if !GregorianScore(elements: current).lyricText.isEmpty {
            verses.append(current)
        }
        return verses
    }

    static func pointedLyricText(
        in elements: [GregorianNotationElement]
    ) -> String {
        var result = ""
        var separatesFollowingLyric = false

        func append(
            _ text: String,
            style: GregorianLyricStyle,
            startsWord: Bool,
            isLyricMark: Bool
        ) {
            guard !text.isEmpty else { return }
            if !result.isEmpty,
               (startsWord || separatesFollowingLyric),
               result.last?.isWhitespace != true {
                result.append(" ")
            }
            if style == .accented {
                result.append(PsalmTextFormatter.emphasisStartMarker)
            }
            result.append(text)
            if style == .accented {
                result.append(PsalmTextFormatter.emphasisEndMarker)
            }
            separatesFollowingLyric = isLyricMark
        }

        for element in elements {
            switch element {
            case .neume(let neume):
                append(
                    neume.lyric,
                    style: neume.lyricStyle,
                    startsWord: neume.startsWord,
                    isLyricMark: false
                )
            case .lyricMark(let mark):
                append(
                    mark.text,
                    style: mark.style,
                    startsWord: mark.startsWord,
                    isLyricMark: true
                )
            case .clef, .accidental, .division, .forcedBreak:
                continue
            @unknown default:
                continue
            }
        }
        return result
    }

    private static func firstVerseGABC(from gabc: String) -> String? {
        guard let bodyMarker = gabc.range(of: "%%") else { return nil }
        let body = gabc[bodyMarker.upperBound...]
        guard let verseEnd = body.range(
            of: #"\(\s*::\s*\)"#,
            options: .regularExpression
        ) else {
            return nil
        }
        var firstVerse = String(gabc[..<verseEnd.upperBound])
        if let trailingNextOrdinal = firstVerse.range(
            of: #"\s+2\.\s*(?=\(\s*::\s*\)\s*$)"#,
            options: .regularExpression
        ) {
            firstVerse.removeSubrange(trailingNextOrdinal)
        }
        return firstVerse
    }

    static func normalizingTrailingVerseOrdinals(
        _ verses: [String]
    ) -> [String] {
        guard verses.count > 1 else { return verses }
        var result = verses

        for index in result.indices.dropLast() {
            let words = result[index].split(whereSeparator: \.isWhitespace)
            guard let last = words.last,
                  last.hasSuffix("."),
                  Int(last.dropLast()) == index + 2 else {
                continue
            }
            result[index] = words.dropLast().joined(separator: " ")
            let ordinal = "\(index + 2)."
            if !result[index + 1].hasPrefix("\(ordinal) ") {
                result[index + 1] = "\(ordinal) \(result[index + 1])"
            }
        }
        return result
    }

    private static func interleavingTextWithNonPsalmChants(
        _ source: [OfficeSection],
        allowsTitleFallback: Bool = true
    ) -> [OfficeSection] {
        // A heading names an office part; it does not prove that every prayer
        // under that heading is present in a score. Associate chants by Latin
        // content and remove only paragraphs that the GABC actually covers.
        let textIndices = source.indices.filter {
            source[$0].chant == nil && source[$0].kind != .psalm
        }
        var chantIndicesByTextIndex: [Int: [Int]] = [:]

        for chantIndex in source.indices
        where source[chantIndex].chant != nil && source[chantIndex].kind != .psalm {
            let chant = source[chantIndex]
            let contentMatch = bestTextIndex(
                matching: chant,
                at: chantIndex,
                in: source,
                candidates: textIndices
            )
            let title = normalizedTitle(chant.title)
            let titleMatch = textIndices
                .filter { normalizedTitle(source[$0].title) == title && !title.isEmpty }
                .min(by: {
                    abs($0 - chantIndex) < abs($1 - chantIndex)
                })

            if let textIndex = contentMatch
                ?? (allowsTitleFallback ? titleMatch : nil) {
                chantIndicesByTextIndex[textIndex, default: []].append(chantIndex)
            }
        }

        if !allowsTitleFallback {
            // An ordered office already places every score. Fold a score into
            // a text only where it replaces paragraphs which that text prints,
            // with no other prayer between them, and give each paragraph to
            // its nearest score. Otherwise a versicle repeating the opening of
            // a chapter, an antiphon quoted in a lesson, or the Tu autem of
            // one lesson would be moved to another place in the Hour.
            for (textIndex, chantIndices) in chantIndicesByTextIndex {
                let textParagraphs = paragraphs(in: source[textIndex].latin)
                // Some imported offices print a conclusion again after the
                // blessing. Such a text only repeats what the scores sing, so
                // it may be folded into them wherever it stands.
                let repeatsScores = text(
                    source[textIndex],
                    onlyRepeats: chantIndices.map { source[$0] }
                )
                var claimed: Set<Int> = []
                var claimedWords: Set<[String]> = []
                let retained = chantIndices
                    .sorted { abs($0 - textIndex) < abs($1 - textIndex) }
                    .filter { chantIndex in
                        guard repeatsScores || !isSeparatedByPrayer(
                            chantIndex,
                            from: textIndex,
                            in: source
                        ) else { return false }
                        let covered = textParagraphs.indices.filter {
                            !claimed.contains($0)
                                && score(
                                    source[chantIndex],
                                    coversParagraph: textParagraphs[$0]
                                )
                        }
                        // A repeated antiphon may print the same words twice;
                        // each occurrence remains available to its own score.
                        var newlyClaimed = false
                        for paragraph in covered {
                            let words = normalizedLatinWords(textParagraphs[paragraph])
                            guard claimedWords.insert(words).inserted else { continue }
                            claimed.insert(paragraph)
                            newlyClaimed = true
                        }
                        return newlyClaimed
                    }
                chantIndicesByTextIndex[textIndex] = retained.isEmpty
                    ? nil
                    : retained.sorted()
            }
        }

        var groupsByAnchor: [Int: (textIndex: Int, chantIndices: [Int])] = [:]
        var groupedIndices: Set<Int> = []
        for (textIndex, chantIndices) in chantIndicesByTextIndex {
            let anchor = ([textIndex] + chantIndices).min() ?? textIndex
            groupsByAnchor[anchor] = (textIndex, chantIndices.sorted())
            groupedIndices.insert(textIndex)
            groupedIndices.formUnion(chantIndices)
        }

        var result: [OfficeSection] = []
        for index in source.indices {
            if let group = groupsByAnchor[index] {
                result.append(
                    contentsOf: presentationSections(
                        text: source[group.textIndex],
                        chants: group.chantIndices.map { source[$0] }
                    )
                )
            } else if !groupedIndices.contains(index) {
                result.append(source[index])
            }
        }
        return result
    }

    /// Whether a text opens with words the score sings, as Compline's
    /// Deus in adiutórium does after the confession. A Glória Patri at the end
    /// of a canticle does not make the opening score belong there.
    private static func text(
        _ text: OfficeSection,
        opensWith chant: OfficeSection
    ) -> Bool {
        let heading = normalizedTitle(text.title)
        guard let first = paragraphs(in: text.latin).first(where: {
            normalizedTitle($0) != heading
        }) else { return false }
        return score(chant, coversParagraph: first)
    }

    /// Whether every paragraph of a text is sung by these scores, and every
    /// score is contained in the text: the text then adds nothing to them.
    private static func text(
        _ text: OfficeSection,
        onlyRepeats chants: [OfficeSection]
    ) -> Bool {
        let heading = normalizedTitle(text.title)
        let textParagraphs = paragraphs(in: text.latin).filter {
            normalizedTitle($0) != heading
        }
        let textWords = normalizedLatinWords(text.latin)
        guard !textParagraphs.isEmpty, !chants.isEmpty else { return false }
        return textParagraphs.allSatisfy { paragraph in
            chants.contains { score($0, coversParagraph: paragraph) }
        } && chants.allSatisfy { chant in
            let words = scoredWords(in: chant)
            return !words.isEmpty
                && longestSharedRun(words, textWords) * 10 >= words.count * 7
        }
    }

    /// Whether another printed prayer stands between a score and a text.
    /// Rubrics and other scores do not separate them.
    private static func isSeparatedByPrayer(
        _ chantIndex: Int,
        from textIndex: Int,
        in source: [OfficeSection]
    ) -> Bool {
        let lower = min(chantIndex, textIndex) + 1
        let upper = max(chantIndex, textIndex)
        guard lower < upper else { return false }
        return source[lower..<upper].contains {
            $0.chant == nil
                && $0.kind != .rubric
                && !$0.latin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func bestTextIndex(
        matching chant: OfficeSection,
        at chantIndex: Int,
        in source: [OfficeSection],
        candidates: [Int]
    ) -> Int? {
        let scoreWords = scoredWords(in: chant)
        guard scoreWords.count >= 4 else { return nil }

        return candidates
            .compactMap { index -> (index: Int, run: Int)? in
                substantialSharedRun(
                    scoreWords,
                    normalizedLatinWords(source[index].latin)
                ).map { (index: index, run: $0) }
            }
            .max(by: {
                if $0.run == $1.run {
                    return abs($0.index - chantIndex)
                        > abs($1.index - chantIndex)
                }
                return $0.run < $1.run
            })?
            .index
    }

    private static func presentationSections(
        text: OfficeSection,
        chants: [OfficeSection]
    ) -> [OfficeSection] {
        let latinParagraphs = paragraphs(in: text.latin)
        let englishParagraphs = text.english.map { paragraphs(in: $0) }
        let translationsAlign = englishParagraphs?.count == latinParagraphs.count
        let textTitle = normalizedTitle(text.title)
        let presentationTitle = textTitle.range(
            of: #"^section [0-9]+$"#,
            options: .regularExpression
        ) != nil
            ? chants.lazy.map(\.title).first(where: {
                !normalizedTitle($0).isEmpty
            }) ?? text.title
            : text.title
        let headingIndices = Set(
            latinParagraphs.indices.filter {
                let paragraph = normalizedTitle(latinParagraphs[$0])
                return paragraph == textTitle
                    || paragraph == normalizedTitle(presentationTitle)
            }
        )
        var coveredIndices = headingIndices
        var chantsByParagraph: [Int: [OfficeSection]] = [:]
        let matchedParagraphs = chants.map { chant in
            latinParagraphs.indices
                .filter { !headingIndices.contains($0) }
                .filter {
                    score(chant, coversParagraph: latinParagraphs[$0])
                }
        }
        let chantsCoveringText = Set(
            zip(chants, matchedParagraphs).compactMap { chant, matches in
                matches.isEmpty ? nil : chant.id
            }
        )

        for (chantIndex, chant) in chants.enumerated() {
            let matches = matchedParagraphs[chantIndex]
            if !matches.isEmpty {
                coveredIndices.formUnion(matches)
            }
            let previousAnchor = matchedParagraphs[..<chantIndex]
                .reversed()
                .lazy
                .compactMap(\.last)
                .first
            let nextAnchor = matchedParagraphs[(chantIndex + 1)...]
                .lazy
                .compactMap(\.first)
                .first
            let anchor = presentationAnchor(
                for: matches,
                in: latinParagraphs
            )
                ?? previousAnchor
                ?? nextAnchor
                ?? latinParagraphs.indices.first(where: {
                    !headingIndices.contains($0)
                })
                ?? latinParagraphs.startIndex
            chantsByParagraph[anchor, default: []].append(chant)
        }

        var result: [OfficeSection] = []
        var residualIndices: [Int] = []

        func appendResidual() {
            guard !residualIndices.isEmpty else { return }
            let suffix = result.isEmpty ? "" : "-continuation-\(result.count)"
            result.append(
                text.replacingPresentation(
                    id: "\(text.id)\(suffix)",
                    title: result.isEmpty ? presentationTitle : "",
                    rubric: result.isEmpty ? text.rubric : nil,
                    rubricEnglish: result.isEmpty
                        ? .some(text.rubricEnglish)
                        : .some(nil),
                    latin: residualIndices.map { latinParagraphs[$0] }
                        .joined(separator: "\n\n"),
                    english: translationsAlign
                        ? residualIndices.compactMap { englishParagraphs?[$0] }
                            .joined(separator: "\n\n")
                        : text.english
                )
            )
            residualIndices.removeAll(keepingCapacity: true)
        }

        func appendChants(_ sections: [OfficeSection], paragraphIndex: Int?) {
            appendResidual()
            for chant in sections {
                let english: String?
                if translationsAlign,
                   let paragraphIndex,
                   let englishParagraphs,
                   chantsCoveringText.contains(chant.id) {
                    english = presentationTranslation(
                        from: englishParagraphs[paragraphIndex]
                    )
                } else {
                    english = chant.english
                }
                result.append(
                    chant.replacingPresentation(
                        title: result.isEmpty ? presentationTitle : "",
                        titleEnglish: result.isEmpty
                            ? .some(text.titleEnglish)
                            : .some(nil),
                        rubric: result.isEmpty ? text.rubric : nil,
                        rubricEnglish: result.isEmpty
                            ? .some(text.rubricEnglish)
                            : .some(nil),
                        english: english
                    )
                )
            }
        }

        for paragraphIndex in latinParagraphs.indices {
            if let paragraphChants = chantsByParagraph[paragraphIndex] {
                appendChants(paragraphChants, paragraphIndex: paragraphIndex)
            }
            if !coveredIndices.contains(paragraphIndex) {
                residualIndices.append(paragraphIndex)
            }
        }
        appendResidual()
        if latinParagraphs.isEmpty {
            // A text left without words still gives its heading to its scores.
            appendChants(chants, paragraphIndex: nil)
        }
        return result
    }

    private static func presentationAnchor(
        for matches: [Int],
        in paragraphs: [String]
    ) -> Int? {
        guard matches.count > 1 else { return matches.first }

        // Compact office books print a repeated antiphon's full score after
        // the psalm or canticle, while omitting its prose announcement.
        if matches.allSatisfy({ isAntiphonParagraph(paragraphs[$0]) }) {
            return matches.last
        }
        return matches.first
    }

    private static func suppressingRepeatedHeadings(
        _ sections: [OfficeSection]
    ) -> [OfficeSection] {
        var lastVisibleHeading: String?
        return sections.map { section in
            let heading = normalizedTitle(section.title)
            guard !heading.isEmpty else {
                return section
            }
            defer { lastVisibleHeading = heading }
            guard heading == lastVisibleHeading else {
                return section
            }
            return section.replacingPresentation(title: "")
        }
    }

    private static func interleavingCompactPsalmody(
        _ source: [OfficeSection]
    ) -> [OfficeSection] {
        var result: [OfficeSection] = []
        var index = source.startIndex

        while index < source.endIndex {
            guard source[index].kind == .psalm else {
                result.append(source[index])
                index += 1
                continue
            }

            let blockStart = index
            while index < source.endIndex, source[index].kind == .psalm {
                index += 1
            }
            let block = Array(source[blockStart..<index])
            result.append(contentsOf: interleavingCompactPsalmBlock(block))
        }

        return result
    }

    private static func interleavingCompactPsalmBlock(
        _ block: [OfficeSection]
    ) -> [OfficeSection] {
        let chants = block.enumerated().filter { $0.element.chant != nil }
        let texts = block.enumerated().filter { $0.element.chant == nil }
        guard let firstTextIndex = texts.first?.offset,
              let lastChantIndex = chants.last?.offset,
              lastChantIndex < firstTextIndex,
              !chants.isEmpty,
              !texts.isEmpty
        else {
            return block
        }

        var chantsByTextID: [String: [OfficeSection]] = [:]
        var unmatchedChants: [OfficeSection] = []
        for (_, chant) in chants {
            guard let targetID = psalmContentTargetID(
                for: chant,
                in: texts.map(\.element)
            )
            else {
                unmatchedChants.append(chant)
                continue
            }
            chantsByTextID[targetID, default: []].append(chant)
        }

        var reordered = unmatchedChants
        for (_, text) in texts {
            var matchingChants = chantsByTextID.removeValue(forKey: text.id) ?? []
            if let coveringIndex = matchingChants.indices.max(by: {
                scoredWordCount(matchingChants[$0]) < scoredWordCount(matchingChants[$1])
            }), score(matchingChants[coveringIndex], covers: text) {
                matchingChants[coveringIndex] = matchingChants[coveringIndex]
                    .mergingTextMetadata(from: text)
                reordered.append(contentsOf: matchingChants)
            } else {
                reordered.append(
                    contentsOf: compactPsalmPresentation(
                        chants: matchingChants,
                        text: text,
                        reusableChants: chants.map(\.element)
                    )
                )
            }
        }
        reordered.append(contentsOf: chantsByTextID.values.flatMap { $0 })
        return reordered
    }

    private static func compactPsalmPresentation(
        chants: [OfficeSection],
        text: OfficeSection,
        reusableChants: [OfficeSection]
    ) -> [OfficeSection] {
        let latinParagraphs = paragraphs(in: text.latin)
        let englishParagraphs = text.english.map { paragraphs(in: $0) }
        let translationsAlign = englishParagraphs?.count == latinParagraphs.count
        var consumedIndices = Set(
            latinParagraphs.indices.filter {
                isPsalmHeading(latinParagraphs[$0])
            }
        )
        var preparedChants: [OfficeSection] = []

        for (chantIndex, chant) in chants.enumerated() {
            let paragraphIndex = bestParagraphIndex(
                matching: chant.latin,
                in: latinParagraphs,
                excluding: consumedIndices
            )
            if let paragraphIndex {
                consumedIndices.insert(paragraphIndex)
            }
            let english: String?
            if translationsAlign,
               let paragraphIndex,
               let englishParagraphs {
                english = presentationTranslation(
                    from: englishParagraphs[paragraphIndex]
                )
            } else {
                english = chant.english
            }
            let title = chantIndex > 0
                && normalizedTitle(chants[chantIndex - 1].title)
                    == normalizedTitle(chant.title)
                ? ""
                : chant.title
            preparedChants.append(
                chant.replacingPresentation(
                    title: title,
                    rubric: .some(nil),
                    english: english
                )
            )
        }

        var repeatedAntiphons: [OfficeSection] = []
        for paragraphIndex in latinParagraphs.indices
        where !consumedIndices.contains(paragraphIndex)
            && isAntiphonParagraph(latinParagraphs[paragraphIndex]) {
            guard let chant = reusableChants.max(by: {
                longestSharedRun(
                    normalizedLatinWords($0.latin),
                    normalizedLatinWords(latinParagraphs[paragraphIndex])
                ) < longestSharedRun(
                    normalizedLatinWords($1.latin),
                    normalizedLatinWords(latinParagraphs[paragraphIndex])
                )
            }),
            longestSharedRun(
                normalizedLatinWords(chant.latin),
                normalizedLatinWords(latinParagraphs[paragraphIndex])
            ) >= 4
            else {
                continue
            }
            consumedIndices.insert(paragraphIndex)
            let english: String?
            if translationsAlign, let englishParagraphs {
                english = presentationTranslation(
                    from: englishParagraphs[paragraphIndex]
                )
            } else {
                english = nil
            }
            repeatedAntiphons.append(
                chant.replacingPresentation(
                    id: "\(chant.id)-repeat-\(text.id)-\(paragraphIndex)",
                    title: "",
                    rubric: .some(nil),
                    english: english
                )
            )
        }

        let remainingIndices = latinParagraphs.indices.filter {
            !consumedIndices.contains($0)
        }
        var result = preparedChants
        if !remainingIndices.isEmpty {
            result.append(
                text.replacingPresentation(
                    title: "",
                    rubric: .some(nil),
                    latin: remainingIndices.map { latinParagraphs[$0] }
                        .joined(separator: "\n\n"),
                    english: translationsAlign
                        ? remainingIndices.compactMap { englishParagraphs?[$0] }
                            .joined(separator: "\n\n")
                        : text.english
                )
            )
        }
        result.append(contentsOf: repeatedAntiphons)
        return result
    }

    static func paragraphs(in value: String) -> [String] {
        value
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func bestParagraphIndex(
        matching incipit: String,
        in paragraphs: [String],
        excluding excludedIndices: Set<Int>
    ) -> Int? {
        let incipitWords = normalizedLatinWords(incipit)
        guard incipitWords.count >= 4 else { return nil }
        return paragraphs.indices
            .filter { !excludedIndices.contains($0) }
            .map {
                (
                    index: $0,
                    run: longestSharedRun(
                        incipitWords,
                        normalizedLatinWords(paragraphs[$0])
                    )
                )
            }
            .filter { $0.run >= 4 }
            .max(by: { $0.run < $1.run })?
            .index
    }

    private static func isPsalmHeading(_ paragraph: String) -> Bool {
        let value = normalizedTitle(paragraph)
        return value == "psalmi"
            || value.hasPrefix("psalmi ")
            || value == "psalms"
            || value.hasPrefix("psalms ")
            || value.hasPrefix("psalmus ")
            || value.hasPrefix("psalm ")
    }

    static func isAntiphonParagraph(_ paragraph: String) -> Bool {
        let value = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("Ant.") || value.hasPrefix("Ant ")
    }

    private static func presentationTranslation(from paragraph: String) -> String {
        var value = PsalmTextFormatter.strippingScriptureReference(from: paragraph)
        if value.hasPrefix("Ant. ") {
            value.removeFirst("Ant. ".count)
        } else if value.hasPrefix("Ant ") {
            value.removeFirst("Ant ".count)
        }
        return value
    }

    private static func psalmContentTargetID(
        for chant: OfficeSection,
        in sections: [OfficeSection]
    ) -> String? {
        let incipitWords = normalizedLatinWords(chant.latin)
        if incipitWords.count >= 4 {
            var best: (id: String, run: Int)?
            for section in sections {
                let run = longestSharedRun(
                    incipitWords,
                    normalizedLatinWords(section.latin)
                )
                if run >= 4, run > (best?.run ?? 3) {
                    best = (section.id, run)
                }
            }
            if let best {
                return best.id
            }
        }
        return contentTargetID(for: chant, in: sections)
    }

    private static func correctedSource(
        _ source: [OfficeSection],
        preservesUnnumberedAntiphons: Bool = false
    ) -> [OfficeSection] {
        let standaloneAntiphonTranslations = Set(
            source.compactMap { section -> String? in
                guard let english = section.english else { return nil }
                let values = paragraphs(in: english)
                guard values.count == 1,
                      isAntiphonParagraph(values[0]) else {
                    return nil
                }
                return presentationTranslation(from: values[0])
            }
        )
        var corrected = source.map { section in
            guard section.kind == .psalm,
                  section.chant != nil,
                  let english = section.english else {
                return section
            }
            let values = paragraphs(in: english)
            guard values.count > 1 else { return section }
            let retained = values.enumerated().compactMap { index, paragraph in
                guard isAntiphonParagraph(paragraph),
                      standaloneAntiphonTranslations.contains(
                        presentationTranslation(from: paragraph)
                      ) else {
                    return paragraph
                }
                if index > values.startIndex,
                   index < values.index(before: values.endIndex),
                   let previous = scriptureReference(in: values[index - 1]),
                   let next = scriptureReference(in: values[index + 1]),
                   previous.psalm == next.psalm {
                    if next.verse == previous.verse + 1 {
                        return nil
                    }
                    if next.verse == previous.verse + 2 {
                        return "\(previous.psalm):\(previous.verse + 1) "
                            + presentationTranslation(from: paragraph)
                    }
                }
                return preservesUnnumberedAntiphons ? paragraph : nil
            }
            guard retained != values else { return section }
            return section.replacingPresentation(
                english: .some(retained.joined(separator: "\n\n"))
            )
        }

        if let firstTextIndex = corrected.firstIndex(where: { $0.chant == nil }),
           normalizedTitle(corrected[firstTextIndex].title) == "incipit",
           normalizedLatinWords(corrected[firstTextIndex].latin).starts(
               with: ["incipit", "iube", "domine"]
           ),
           corrected.contains(where: {
               normalizedTitle($0.title) == "lectio brevis"
           }) {
            let section = corrected[firstTextIndex]
            corrected[firstTextIndex] = OfficeSection(
                id: section.id,
                kind: section.kind,
                title: "Lectio brevis",
                titleEnglish: section.titleEnglish,
                rubric: section.rubric,
                rubricEnglish: section.rubricEnglish,
                latin: withoutLeadingParagraph(section.latin, matching: ["Incipit"]),
                english: section.english.map {
                    withoutLeadingParagraph($0, matching: ["Start", "Beginning"])
                },
                chant: nil
            )
        }

        if let opening = corrected.first,
           opening.chant != nil,
           normalizedTitle(opening.title) == "incipit",
           let targetID = contentTargetID(for: opening, in: corrected),
           let targetIndexBeforeRemoval = corrected.firstIndex(where: { $0.id == targetID }),
           targetIndexBeforeRemoval > 1,
           text(corrected[targetIndexBeforeRemoval], opensWith: opening) {
            corrected.removeFirst()
            if let targetIndex = corrected.firstIndex(where: { $0.id == targetID }) {
                corrected.insert(opening, at: targetIndex)
            }
        }

        return corrected
    }

    private static func scriptureReference(
        in value: String
    ) -> (psalm: Int, verse: Int)? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = value.firstIndex(where: \.isWhitespace) else {
            return nil
        }
        // Empty pieces are kept, so that "76::15" is not read as "76:15".
        let parts = value[..<separator].split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let psalm = Int(parts[0]),
              let verse = Int(parts[1]) else {
            return nil
        }
        return (psalm, verse)
    }

    private static func contentTargetID(
        for chant: OfficeSection,
        in sections: [OfficeSection]
    ) -> String? {
        guard let gabc = chant.chant?.gabc else { return nil }
        let body = gabc.components(separatedBy: "%%").dropFirst().joined(separator: "%%")
        let scoredWords = normalizedLatinWords(
            body.isEmpty ? gabc : body
        )
        guard scoredWords.count >= 4 else { return nil }

        var best: (id: String, run: Int)?
        for section in sections where section.chant == nil {
            guard let run = substantialSharedRun(
                scoredWords,
                normalizedLatinWords(section.latin)
            ), run > (best?.run ?? 0) else { continue }
            best = (section.id, run)
        }
        return best?.id
    }

    private static func scoredWordCount(_ section: OfficeSection) -> Int {
        scoredWords(in: section).count
    }

    private static func scoredWords(in section: OfficeSection) -> [String] {
        guard let gabc = section.chant?.gabc else { return [] }
        let body = gabc.components(separatedBy: "%%").dropFirst().joined(separator: "%%")
        return normalizedLatinWords(body.isEmpty ? gabc : body)
    }

    private static func score(
        _ chant: OfficeSection,
        covers text: OfficeSection
    ) -> Bool {
        let scoredCount = scoredWordCount(chant)
        let textCount = normalizedLatinWords(text.latin).count
        guard textCount > 0 else { return true }
        return scoredCount >= 8 && Double(scoredCount) / Double(textCount) >= 0.7
    }

    private static func score(
        _ chant: OfficeSection,
        coversParagraph paragraph: String
    ) -> Bool {
        let scoreWords = scoredWords(in: chant)
        let paragraphWords = normalizedLatinWords(paragraph)
        guard !scoreWords.isEmpty, !paragraphWords.isEmpty else { return false }
        let sharedRun = longestSharedRun(scoreWords, paragraphWords)

        if paragraphWords.count <= 3 {
            return sharedRun == paragraphWords.count
        }
        return sharedRun >= 4
            && Double(sharedRun) / Double(paragraphWords.count) >= 0.7
    }

    private static func normalizedLatinWords(_ value: String) -> [String] {
        value
            .replacingOccurrences(
                of: #"\([^)]*\)"#,
                with: "",
                options: .regularExpression
            )
            // GABC emphasis may divide a single word, as in *tu*(k)um.
            // Remove its inline markers instead of treating them as word
            // boundaries, while the surrounding whitespace still separates
            // genuine flex/mediant markers in prose.
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "la")
            )
            .lowercased()
            .replacingOccurrences(of: "j", with: "i")
            .replacingOccurrences(of: "v", with: "u")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    /// The shared word run between a score and a text, when it is long
    /// enough to identify the one with the other: at least four words,
    /// covering at least half of the score or of the text. A common formula
    /// such as "in sǽcula sæculórum. Amen" or "Glória Patri" does not by
    /// itself make a score part of another prayer.
    static func substantialSharedRun(
        _ scoreWords: [String],
        _ textWords: [String]
    ) -> Int? {
        let run = longestSharedRun(scoreWords, textWords)
        guard run >= 4,
              run * 2 >= scoreWords.count || run * 2 >= textWords.count else {
            return nil
        }
        return run
    }

    static func longestSharedRun(_ left: [String], _ right: [String]) -> Int {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return left.count }
        let (scanned, indexed) = left.count >= right.count ? (left, right) : (right, left)
        let positions = Dictionary(grouping: indexed.indices, by: { indexed[$0] })
        var previous: [Int: Int] = [:]
        var longest = 0
        for word in scanned {
            // Only equal words can extend a contiguous run. Each length
            // extends the preceding row and column, never the current row;
            // mismatches therefore break a run rather than joining gaps.
            var current: [Int: Int] = [:]
            for index in positions[word] ?? [] {
                let length = (previous[index - 1] ?? 0) + 1
                current[index] = length
                longest = max(longest, length)
            }
            if longest == indexed.count { return longest }
            previous = current
        }
        return longest
    }

    private static func withoutLeadingParagraph(
        _ value: String,
        matching headings: [String]
    ) -> String {
        let paragraphs = value.components(separatedBy: "\n\n")
        guard paragraphs.count > 1,
              headings.contains(where: {
                  paragraphs[0].compare(
                      $0,
                      options: [.caseInsensitive, .diacriticInsensitive]
                  ) == .orderedSame
              })
        else {
            return value
        }
        return paragraphs.dropFirst().joined(separator: "\n\n")
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension OfficeSection {
    nonisolated func mergingTextMetadata(
        from textSection: OfficeSection
    ) -> OfficeSection {
        OfficeSection(
            id: id,
            kind: kind,
            title: title,
            titleEnglish: textSection.titleEnglish ?? titleEnglish,
            rubric: textSection.rubric ?? rubric,
            rubricEnglish: textSection.rubricEnglish ?? rubricEnglish,
            latin: latin,
            english: textSection.english ?? english,
            chant: chant
        )
    }

    /// A copy with some of its presentation replaced. An omitted argument keeps
    /// the section's own value; pass `.some(nil)` to remove a rubric.
    nonisolated func replacingPresentation(
        id: String? = nil,
        title: String? = nil,
        titleEnglish: String?? = nil,
        rubric: String?? = nil,
        rubricEnglish: String?? = nil,
        latin: String? = nil,
        english: String?? = nil
    ) -> OfficeSection {
        OfficeSection(
            id: id ?? self.id,
            kind: kind,
            title: title ?? self.title,
            titleEnglish: titleEnglish ?? (title == "" ? nil : self.titleEnglish),
            rubric: rubric ?? self.rubric,
            rubricEnglish: rubricEnglish ?? (rubric == .some(nil) ? nil : self.rubricEnglish),
            latin: latin ?? self.latin,
            english: english ?? self.english,
            chant: chant
        )
    }
}

private struct PrayerOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    /// Whether the reader holds a Mass, which has neither the Office's
    /// greetings for those present nor its psalmody.
    var isMass = false
    /// Whether the reader stands on an iPhone's display as large as an
    /// iPad's, whose size the options set.
    var isLargeDisplay = false
    let isPreparingPrint: Bool
    let isPrintingAvailable: Bool
    let onPrint: () -> Void
    let onClose: () -> Void

    var body: some View {
        @Bindable var model = model
        @Bindable var playback = playback

        NavigationStack {
            Form {
                if !isMass {
                    Section("Celebration") {
                        Picker(
                            "Priest or deacon present",
                            selection: $model.isPriestOrDeaconPresent
                        ) {
                            Text("No").tag(false)
                            Text("Yes").tag(true)
                        }
                        .pickerStyle(.menu)
                        .accessibilityValue(model.isPriestOrDeaconPresent ? "Yes" : "No")
                        .accessibilityIdentifier("priest-or-deacon-present")
                    }
                }

                Section("Display") {
                    LabeledContent("Text") {
                        Picker(
                            "Text",
                            selection: Binding(
                                get: { model.readerLanguage },
                                set: { language in
                                    model.readerLanguage = language
                                    tour.receive(.readerLanguageChanged(language))
                                }
                            )
                        ) {
                            ForEach(ReaderLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("reader-language")
                    }
                    .padding(.vertical, 4)
                    .appTourTarget(.readerEnglish)

                    // The English alone has no chant to show.
                    if model.showsLatin {
                        Toggle("Show chant", isOn: $model.showsChant)
                            .accessibilityIdentifier("chant-toggle")
                    }

                    if isMass {
                        Toggle(
                            "Show Ordinary",
                            isOn: $model.showsMassOrdinary
                        )
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("ordinary-toggle")

                        Text(
                            "Off, the Mass shows only its propers: the parts "
                                + "proper to the day."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !isMass, model.showsScores {
                        Toggle(
                            "Compact psalmody",
                            isOn: $model.usesCompactPsalmody
                        )
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("compact-psalmody-toggle")

                        Text(
                            "Show notation for the first verse, followed by "
                                + "pointed text for the remaining verses."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Reader size", systemImage: "textformat.size")
                            Spacer()
                            Text("\(Int((readerSize * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { readerSize },
                                set: { model.setNotationScale($0, onLargeDisplay: isLargeDisplay) }
                            ),
                            in: GregorianLayoutMetrics.notationScaleRange,
                            step: 0.1
                        )
                        .accessibilityLabel("Reader size")
                        .accessibilityIdentifier("neume-size-slider")
                    }

                    Button("Reset reader size") {
                        model.setNotationScale(
                            AppModel.defaultNotationScale(onLargeDisplay: isLargeDisplay),
                            onLargeDisplay: isLargeDisplay
                        )
                    }
                    .disabled(
                        readerSize == AppModel.defaultNotationScale(onLargeDisplay: isLargeDisplay)
                    )
                }

                Section {
                    Picker("Sound", selection: $playback.guideSound) {
                        ForEach(CantorGuideSound.allCases) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityValue(playback.guideSound.displayName)
                    .accessibilityIdentifier("prayer-cantor-sound")

                    Picker("Schola pitch", selection: $playback.scholaPitch) {
                        ForEach(ScholaPitch.allCases) { pitch in
                            Text(pitch.displayName).tag(pitch)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityValue(playback.scholaPitch.displayName)
                    .accessibilityIdentifier("prayer-schola-pitch")

                    Picker("Register", selection: $playback.chantRegister) {
                        ForEach(ChantRegister.allCases) { register in
                            Text(register.displayName).tag(register)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityValue(playback.chantRegister.displayName)
                    .accessibilityIdentifier("prayer-chant-register")
                } header: {
                    Text("Cantor guide")
                } footer: {
                    Text(
                        "Choose the sampled harp, modeled organ, or simple "
                            + "pitch-pipe tone. "
                            + "The reciting tone is placed at the selected "
                            + "schola pitch and register."
                    )
                }

                Section {
                    Button(action: onPrint) {
                        HStack {
                            Label(
                                isMass ? "Print this Mass" : "Print this hour",
                                systemImage: "printer"
                            )
                            Spacer()
                            if isPreparingPrint {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(
                        isPreparingPrint
                            || !isPrintingAvailable
                            || tour.isActive
                    )
                    .accessibilityIdentifier("prayer-print-hour")
                } header: {
                    Text("Printing")
                } footer: {
                    if !isPrintingAvailable {
                        Text("Printing is unavailable on this device.")
                    } else {
                        Text(
                            isMass
                                ? "Prints this Mass using the current display "
                                    + "settings."
                                : "Prints this hour using the current prayer "
                                    + "and display settings."
                        )
                    }
                }
            }
            .navigationTitle("Prayer options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !tour.isActive || tour.step == .closeReaderOptions {
                        SheetCloseButton(
                            accessibilityLabel: "Close Prayer Options",
                            accessibilityIdentifier: "prayer-options-close",
                            action: closeOptions
                        )
                        .appTourTarget(.readerOptionsClose)
                    }
                }
            }
        }
        .onAppear {
            tour.receive(.readerOptionsOpened)
            Task { @MainActor in
                await Task.yield()
                tour.receive(.readerLanguageChanged(model.readerLanguage))
            }
        }
        .onChange(of: model.readerLanguage) { _, language in
            tour.receive(.readerLanguageChanged(language))
        }
    }

    /// The reader's size on the display the options were opened from.
    private var readerSize: Double {
        model.notationScale(onLargeDisplay: isLargeDisplay)
    }

    private func closeOptions() {
        if tour.isActive {
            guard tour.step == .closeReaderOptions else { return }
        }
        onClose()
        dismiss()
    }
}

struct PsalmTextLine: Identifiable, Equatable {
    let id: Int
    let number: Int?
    let latin: String
    let english: String?
    let emphasizedRanges: [Range<String.Index>]
}

nonisolated enum PsalmTextFormatter {
    nonisolated static let missingTranslationPlaceholder = "\u{2063}"
    nonisolated static let emphasisStartMarker = "\u{F0000}"
    nonisolated static let emphasisEndMarker = "\u{F0001}"

    private static let latinDiphthongs: Set<String> = [
        "ae", "au", "oe"
    ]
    private static let inseparableConsonantPairs: Set<String> = [
        "bl", "br", "ch", "cl", "cr", "dr", "fl", "fr", "gl", "gn",
        "gr", "gu", "ph", "pl", "pr", "qu", "th", "tr"
    ]

    static func lines(
        latin: String,
        english: String?,
        startsAfterScoredVerse: Bool
    ) -> [PsalmTextLine] {
        let latinParagraphs = versesOfLines(paragraphs(in: latin))
        let englishParagraphs = english.map { versesOfLines(paragraphs(in: $0)) }
        let translationsAlign = englishParagraphs?.count == latinParagraphs.count
        var verseNumber = startsAfterScoredVerse ? 2 : 1

        return latinParagraphs.enumerated().map { index, paragraph in
            let latinVerse = versePrefix(in: paragraph)
            let pointedLatin = extractingEmphasis(from: latinVerse.text)
            let number: Int?
            if latinVerse.isNumbered {
                number = latinVerse.explicitNumber ?? verseNumber
                verseNumber = (number ?? verseNumber) + 1
            } else {
                number = nil
            }
            return PsalmTextLine(
                id: index,
                number: number,
                latin: pointedLatin.text,
                english: translationsAlign
                    ? englishParagraphs.flatMap { paragraphs in
                        let paragraph = paragraphs[index]
                        guard paragraph != missingTranslationPlaceholder else {
                            return nil
                        }
                        return strippingVersePrefix(from: paragraph)
                    }
                    : nil,
                emphasizedRanges: pointedLatin.ranges.isEmpty
                    ? emphasizedSyllableRanges(in: pointedLatin.text)
                    : pointedLatin.ranges
            )
        }
    }

    /// Whether a text is set a verse to a line, each opening with its
    /// reference, or with the mark of the doxology's versicle or response,
    /// as the 1954 edition sets its psalms and canticles.
    nonisolated static func isSetVerseByLine(_ text: String) -> Bool {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.count > 1
            && lines.contains { scriptureVerseNumber(from: $0) != nil }
            && lines.allSatisfy {
                scriptureVerseNumber(from: $0) != nil || $0.hasPrefix("℣.") || $0.hasPrefix("℟.")
            }
    }

    /// A text set a verse to a line, as a verse to a paragraph.
    private static func versesOfLines(_ paragraphs: [String]) -> [String] {
        guard paragraphs.count == 1, isSetVerseByLine(paragraphs[0]) else { return paragraphs }
        return paragraphs[0]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func removingEmphasisMarkers(
        from value: String
    ) -> String {
        value
            .replacingOccurrences(of: emphasisStartMarker, with: "")
            .replacingOccurrences(of: emphasisEndMarker, with: "")
    }

    private static func extractingEmphasis(
        from value: String
    ) -> (text: String, ranges: [Range<String.Index>]) {
        var text = ""
        var rangeOffsets: [Range<Int>] = []
        var rangeStart: Int?

        for character in value {
            if String(character) == emphasisStartMarker {
                rangeStart = text.count
            } else if String(character) == emphasisEndMarker {
                if let rangeStart, rangeStart < text.count {
                    rangeOffsets.append(rangeStart..<text.count)
                }
                rangeStart = nil
            } else {
                text.append(character)
            }
        }

        let ranges = rangeOffsets.map { offset in
            let lowerBound = text.index(text.startIndex, offsetBy: offset.lowerBound)
            let upperBound = text.index(text.startIndex, offsetBy: offset.upperBound)
            return lowerBound..<upperBound
        }
        return (text, ranges)
    }

    nonisolated static func scriptureVerseNumber(
        from value: String
    ) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: \.isWhitespace) else {
            return nil
        }
        let prefix = trimmed[..<separator]
        let parts = prefix.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return Int(parts[1])
    }

    static func emphasizedSyllableRanges(
        in value: String
    ) -> [Range<String.Index>] {
        // Point the prose text like the corresponding psalm-tone score:
        // emphasize the lexical accent nearest each half-verse cadence.
        // Liturgical Latin marks polysyllabic stress with an acute accent;
        // unmarked endings fall back to the natural penultimate syllable.
        let mediants = value.indices.filter { value[$0] == "*" }
        guard !mediants.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var segmentStart = value.startIndex
        for mediant in mediants {
            if let range = finalAccentRange(
                in: value,
                segment: segmentStart..<mediant
            ) {
                ranges.append(range)
            }
            segmentStart = value.index(after: mediant)
        }
        if let range = finalAccentRange(
            in: value,
            segment: segmentStart..<value.endIndex
        ) {
            ranges.append(range)
        }
        return ranges
    }

    private static func finalAccentRange(
        in value: String,
        segment: Range<String.Index>
    ) -> Range<String.Index>? {
        guard let finalLetter = value[segment].lastIndex(where: \.isLetter) else {
            return nil
        }

        var wordStart = finalLetter
        while wordStart > segment.lowerBound {
            let previous = value.index(before: wordStart)
            guard value[previous].isLetter else { break }
            wordStart = previous
        }
        let wordEnd = value.index(after: finalLetter)
        let wordRange = wordStart..<wordEnd
        let nuclei = vowelNuclei(in: value, wordRange: wordRange)
        guard !nuclei.isEmpty else { return wordRange }

        let accentedNucleus = nuclei.firstIndex {
            value[$0].containsAcuteAccent
        } ?? max(0, nuclei.count - 2)
        let lowerBound = accentedNucleus == 0
            ? wordRange.lowerBound
            : syllableBoundary(
                in: value,
                leftNucleus: nuclei[accentedNucleus - 1],
                rightNucleus: nuclei[accentedNucleus]
            )
        let upperBound = accentedNucleus == nuclei.count - 1
            ? wordRange.upperBound
            : syllableBoundary(
                in: value,
                leftNucleus: nuclei[accentedNucleus],
                rightNucleus: nuclei[accentedNucleus + 1]
            )
        return lowerBound..<upperBound
    }

    private static func vowelNuclei(
        in value: String,
        wordRange: Range<String.Index>
    ) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = wordRange.lowerBound

        while index < wordRange.upperBound {
            let character = value[index]
            guard character.isLatinVowel,
                  !isConsonantalVowel(
                    in: value,
                    at: index,
                    wordRange: wordRange
                  )
            else {
                index = value.index(after: index)
                continue
            }

            var upperBound = value.index(after: index)
            if upperBound < wordRange.upperBound {
                let pair = character.unaccentedLowercase
                    + value[upperBound].unaccentedLowercase
                if latinDiphthongs.contains(pair) {
                    upperBound = value.index(after: upperBound)
                }
            }
            result.append(index..<upperBound)
            index = upperBound
        }
        return result
    }

    private static func isConsonantalVowel(
        in value: String,
        at index: String.Index,
        wordRange: Range<String.Index>
    ) -> Bool {
        let vowel = value[index].unaccentedLowercase
        let previous = index > wordRange.lowerBound
            ? value[value.index(before: index)].unaccentedLowercase
            : nil
        let nextIndex = value.index(after: index)
        let nextIsVowel = nextIndex < wordRange.upperBound
            && value[nextIndex].isLatinVowel

        if vowel == "i", nextIsVowel {
            return index == wordRange.lowerBound
                || previous.map {
                    ["a", "e", "i", "o", "u", "y", "æ", "œ"].contains($0)
                } == true
        }
        return vowel == "u"
            && (previous == "q" || (previous == "g" && nextIsVowel))
    }

    private static func syllableBoundary(
        in value: String,
        leftNucleus: Range<String.Index>,
        rightNucleus: Range<String.Index>
    ) -> String.Index {
        let clusterRange = leftNucleus.upperBound..<rightNucleus.lowerBound
        let consonantIndices = Array(value.indices[clusterRange])
        guard !consonantIndices.isEmpty else {
            return rightNucleus.lowerBound
        }
        guard consonantIndices.count > 1 else {
            return consonantIndices[0]
        }

        let lastPair = consonantIndices.suffix(2)
            .map { value[$0].unaccentedLowercase }
            .joined()
        if inseparableConsonantPairs.contains(lastPair) {
            return lastPairStart(in: consonantIndices)
        }
        return consonantIndices[consonantIndices.count - 1]
    }

    private static func lastPairStart(
        in indices: [String.Index]
    ) -> String.Index {
        indices[indices.count - 2]
    }

    private static func paragraphs(in value: String) -> [String] {
        value
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The stored paragraphs follow chant divisions; explicit inline Scripture
    /// references come from the compiler's checked Bible concordance. Full-score
    /// translations follow those references instead, joining verse continuations.
    /// Never infer a missing reference from a mediant or a numerical gap here.
    nonisolated static func scriptureParagraphs(from value: String) -> String {
        let reference = try! NSRegularExpression(pattern: #"\b[0-9]+:[0-9]+[a-z]?\s+"#)
        var output: [(reference: String?, text: String)] = []
        for line in value.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            let matches = reference.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard matches.first?.range.location == 0 else {
                output.append((nil, line))
                continue
            }
            for (index, match) in matches.enumerated() {
                let label = nsLine.substring(with: match.range).trimmingCharacters(in: .whitespaces)
                let start = NSMaxRange(match.range)
                let end = index + 1 < matches.count ? matches[index + 1].range.location : nsLine.length
                let text = nsLine.substring(with: NSRange(location: start, length: end - start))
                    .replacingOccurrences(of: #"[†‡*]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if output.last?.reference == label {
                    output[output.count - 1].text += " " + text
                } else {
                    output.append((label, text))
                }
            }
        }
        return output.map { item in
            guard let reference = item.reference else { return item.text }
            // A biblical verse may begin inside a chant line (87:6, for
            // example). Capitalize its paragraph opening only after joining
            // continuations, retaining the source's case everywhere else.
            var text = item.text
            if let firstLetter = text.firstIndex(where: { $0.isLetter }) {
                text.replaceSubrange(firstLetter...firstLetter, with: text[firstLetter].uppercased())
            }
            return "\(reference) \(text)"
        }.joined(separator: "\n\n")
    }

    private nonisolated static func removingScriptureReferences(from value: String) -> String {
        value.replacingOccurrences(
            of: #"\b[0-9]+:[0-9]+[a-z]?\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    nonisolated static func strippingScriptureReference(
        from value: String
    ) -> String {
        let result = versePrefix(in: value)
        return result.isScriptureReference ? removingScriptureReferences(from: result.text) : value
    }

    nonisolated static func strippingVersePrefix(
        from value: String
    ) -> String {
        removingScriptureReferences(from: versePrefix(in: value).text)
    }

    private struct VersePrefix {
        let text: String
        let explicitNumber: Int?
        let isNumbered: Bool
        let isScriptureReference: Bool
    }

    private nonisolated static func versePrefix(
        in value: String
    ) -> VersePrefix {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: \.isWhitespace) else {
            return VersePrefix(
                text: trimmed,
                explicitNumber: nil,
                isNumbered: false,
                isScriptureReference: false
            )
        }
        let prefix = trimmed[..<separator]
        let remainder = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if prefix.hasSuffix("."),
           let number = Int(prefix.dropLast()),
           number > 0 {
            return VersePrefix(
                text: remainder,
                explicitNumber: number,
                isNumbered: true,
                isScriptureReference: false
            )
        }

        // A reference is two numbers and the one colon between them: empty
        // pieces are kept, so that "76::15" and "76:15:" are not references.
        let scriptureParts = prefix.split(separator: ":", omittingEmptySubsequences: false)
        if scriptureParts.count == 2,
           scriptureParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return VersePrefix(
                text: remainder,
                explicitNumber: nil,
                isNumbered: true,
                isScriptureReference: true
            )
        }
        return VersePrefix(
            text: trimmed,
            explicitNumber: nil,
            isNumbered: false,
            isScriptureReference: false
        )
    }
}

nonisolated private extension Character {
    var isLatinVowel: Bool {
        ["a", "e", "i", "o", "u", "y", "æ", "œ"]
            .contains(unaccentedLowercase)
    }

    var unaccentedLowercase: String {
        String(self)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "la")
            )
            .lowercased()
    }
}

nonisolated private extension Substring {
    var containsAcuteAccent: Bool {
        unicodeScalars.contains {
            $0.value == 0x0301
        } || decomposedStringWithCanonicalMapping.unicodeScalars.contains {
            $0.value == 0x0301
        }
    }
}

private struct PsalmTextSectionView: View {
    let section: OfficeSection
    /// Whether the page is the Latin; else each verse's English stands
    /// alone.
    var showsLatin = true
    let isPriestOrDeaconPresent: Bool
    let contentScale: CGFloat

    private var lines: [PsalmTextLine] {
        PsalmTextFormatter.lines(
            latin: OfficePrayerText.adjusted(
                section.latin,
                in: section,
                isPriestOrDeaconPresent: isPriestOrDeaconPresent
            ),
            english: section.english.map {
                OfficePrayerText.adjusted(
                    $0,
                    in: section,
                    isPriestOrDeaconPresent: isPriestOrDeaconPresent
                )
            },
            startsAfterScoredVerse: section.title.isEmpty
                && !PsalmTextFormatter.isSetVerseByLine(section.latin)
        )
    }

    /// The English in its own paragraphs, where its verses and the Latin's
    /// do not agree.
    private func unalignedEnglish(beside lines: [PsalmTextLine]) -> [String]? {
        guard let english = section.english,
              !lines.contains(where: { $0.english != nil }) else { return nil }
        let adjusted = OfficePrayerText.adjusted(
            english,
            in: section,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent
        )
        let paragraphs = (section.kind == .psalm
            ? PsalmTextFormatter.scriptureParagraphs(from: adjusted)
            : adjusted)
            .components(separatedBy: "\n\n")
            .map { PsalmTextFormatter.strippingScriptureReference(from: $0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return paragraphs.isEmpty ? nil : paragraphs
    }

    /// Whether the verses are pointed for singing, numbered after the verse
    /// sung from its score: the rest of a psalm in compact psalmody, which
    /// only the Latin page, sung from its chant, has. Else they are set as a
    /// psalter sets them (PsalterVerseView).
    private var isPointed: Bool {
        section.id.hasSuffix(OfficeReaderSectionBuilder.compactContinuationSuffix)
    }

    var body: some View {
        let lines = self.lines
        if isPointed {
            pointedVerses(lines)
        } else {
            psalterVerses(lines)
        }
    }

    /// The verses as a psalter sets them, a verse to a paragraph under its
    /// red capital, a hymn a stanza at a time, in the language of the page.
    private func psalterVerses(_ lines: [PsalmTextLine]) -> some View {
        let form: PsalterVerseView.Form = section.kind == .hymn ? .stanza : .verse
        let spacing: CGFloat = form == .stanza ? 18 : 12
        return VStack(alignment: .leading, spacing: spacing * contentScale) {
            if !showsLatin, let paragraphs = unalignedEnglish(beside: lines) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    PsalterVerseView(
                        text: paragraph,
                        fontSize: 21 * contentScale,
                        lineSpacing: 3 * contentScale,
                        form: form
                    )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .accessibilityLabel(paragraph)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(lines) { line in
                    // A verse the English lacks keeps its Latin.
                    let text = showsLatin
                        ? line.latin
                        : line.english.flatMap { $0.isEmpty ? nil : $0 } ?? line.latin
                    PsalterVerseView(
                        text: text,
                        fontSize: 21 * contentScale,
                        lineSpacing: 3 * contentScale,
                        form: form
                    )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .accessibilityLabel(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// The verses pointed for singing to the psalm's tone, numbered.
    private func pointedVerses(_ lines: [PsalmTextLine]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 7) {
                    if let number = line.number {
                        Text("\(number).")
                            .font(
                                .custom(
                                    "EBGaramond-Regular",
                                    size: 21 * contentScale,
                                    relativeTo: .body
                                )
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityHidden(true)
                    }

                    SelectableTextView(
                        text: line.latin,
                        fontSize: 21 * contentScale,
                        lineSpacing: 3 * contentScale,
                        emphasizedRanges: line.emphasizedRanges,
                        highlightsAsterisks: true,
                        marksRubrics: true
                    )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .accessibilityLabel(line.number.map { "\($0). \(line.latin)" } ?? line.latin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct OfficeSectionView: View {
    let section: OfficeSection
    /// Whether the section is a Mass's, set as a missal sets it
    /// (MissalTextView).
    var isMass = false
    let isFollowedByContinuation: Bool
    /// Whether the page is the Latin; else the English stands alone.
    var showsLatin = true
    /// Whether the Latin is sung from its score, where it has one.
    var showsChant = true
    let usesCompactPsalmody: Bool
    let isPriestOrDeaconPresent: Bool
    let contentScale: CGFloat
    let scorePreparation: GregorianScorePreparation?
    let isCantorGuideScore: Bool
    let isAppTourFirstChant: Bool
    let onTapEvent: (ChantScore, String) -> Void
    let onActiveNeumeFrameChange: (ActiveNeumeFrame) -> Void

    @ScaledMetric(relativeTo: .caption2)
    private var sectionHeadingSize = 11.0

    /// Whether the section is sung from its score.
    private var showsScore: Bool {
        OfficeReaderSectionBuilder.isSungFromScore(
            section,
            showsScores: showsLatin && showsChant,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent
        )
    }

    /// Whether the English stands alone, as the reader's text.
    private var showsEnglishAlone: Bool { !showsLatin }

    private var usesPointedPsalmodyLayout: Bool {
        OfficeReaderSectionBuilder.usesPointedPsalmodyLayout(
            section,
            isSungFromScore: showsScore,
            usesCompactPsalmody: usesCompactPsalmody
        )
    }

    private var isAntiphonText: Bool {
        OfficeReaderSectionBuilder.isAntiphonText(
            section,
            isSungFromScore: showsScore,
            isMass: isMass
        )
    }

    /// The heading's English: the edition's, or the usual English of a
    /// heading it prints in Latin alone.
    private var titleEnglish: String? {
        section.titleEnglish.flatMap { $0.isEmpty ? nil : $0 }
            ?? OfficeHeadingTranslation.english(for: section.title)
    }

    /// The heading in the language shown: the Latin, or the English alone.
    private var heading: String {
        guard showsEnglishAlone else { return section.title }
        return titleEnglish ?? section.title
    }

    /// The rubric in the language shown.
    private var displayedRubric: String? {
        guard showsEnglishAlone else { return section.userFacingRubric }
        guard section.userFacingRubric != nil else { return nil }
        return section.rubricEnglish.flatMap { $0.isEmpty ? nil : $0 } ?? section.userFacingRubric
    }

    /// The words in the language of the page: the Latin, or the English
    /// alone, the section's own English, else its Latin.
    private var prose: String {
        OfficePrayerText.adjusted(
            showsEnglishAlone
                ? section.english.flatMap { $0.isEmpty ? nil : $0 } ?? section.latin
                : section.latin,
            in: section,
            isPriestOrDeaconPresent: isPriestOrDeaconPresent
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !section.title.isEmpty {
                if section.kind == .psalm {
                    Text(heading)
                        .font(
                            .custom(
                                "EBGaramond-Regular",
                                size: 20 * contentScale,
                                relativeTo: .title3
                            )
                        )
                        .foregroundStyle(Color(red: 0.82, green: 0.13, blue: 0.08))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .accessibilityIdentifier(
                            "office-section-heading-\(section.id)"
                        )
                } else if isMass {
                    // A missal's heading: red capitals, spaced.
                    VStack(spacing: 6) {
                        Text(heading.uppercased())
                            .font(
                                .custom(
                                    "EBGaramond-Medium",
                                    size: 17 * contentScale,
                                    relativeTo: .headline
                                )
                            )
                            .tracking(3 * contentScale)
                            .foregroundStyle(Color(uiColor: MissalTypography.rubric))
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "office-section-heading-\(section.id)"
                    )
                } else {
                    VStack(spacing: 5) {
                        Text(heading.uppercased())
                            .font(
                                .system(
                                    size: sectionHeadingSize * contentScale,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .tracking(1.5 * contentScale)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier(
                        "office-section-heading-\(section.id)"
                    )
                }
            }

            if let rubric = displayedRubric {
                VStack(spacing: 8) {
                    Text(rubric)
                        .font(
                            .custom(
                                "EBGaramond-Regular",
                                size: 17 * contentScale,
                                relativeTo: .body
                            )
                            .italic()
                        )
                }
                .foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            if showsScore, let score = section.chant {
                let preparation = scorePreparation
                    ?? .failed("The chant layout was not prepared.")
                ZStack(alignment: .topLeading) {
                    if isCantorGuideScore {
                        ActiveCantorScoreView(
                            score: score,
                            preparation: preparation,
                            onTapEvent: { eventID in
                                onTapEvent(score, eventID)
                            },
                            onActiveNeumeFrameChange:
                                onActiveNeumeFrameChange
                        )
                    } else {
                        GregorianScoreView(
                            score: score,
                            preparation: preparation,
                            highlightedEventID: nil,
                            onTapEvent: { eventID in
                                onTapEvent(score, eventID)
                            },
                            onActiveNeumeFrameChange:
                                onActiveNeumeFrameChange
                        )
                    }

                    if isAppTourFirstChant,
                       case let .ready(preparedScore) = preparation,
                       let firstNeume = preparedScore.layout.neumes.first {
                        let focusFrame = firstNeume.inkFrame.insetBy(
                            dx: -6,
                            dy: -6
                        )
                        Button {
                            onTapEvent(score, firstNeume.id)
                        } label: {
                            Color.clear
                                .frame(
                                    width: max(28, focusFrame.width),
                                    height: max(28, focusFrame.height)
                                )
                                .contentShape(
                                    RoundedRectangle(
                                        cornerRadius: 8,
                                        style: .continuous
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: focusFrame.midX,
                            y: focusFrame.midY
                        )
                        .accessibilityLabel("First neume")
                        .accessibilityHint("Starts the Cantor Guide")
                        .accessibilityIdentifier("tour-reader-first-chant")
                        .appTourTarget(.readerFirstChant)
                    }
                }
            } else if usesPointedPsalmodyLayout {
                PsalmTextSectionView(
                    section: section,
                    showsLatin: showsLatin,
                    isPriestOrDeaconPresent: isPriestOrDeaconPresent,
                    contentScale: contentScale
                )
            } else if isMass {
                MissalTextView(
                    text: prose,
                    fontSize: 23 * contentScale,
                    lineSpacing: 7 * contentScale,
                    opensWithInitial: true,
                    isReading: section.kind.isMassReading
                )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            } else {
                SelectableTextView(
                    text: prose,
                    fontSize: (isAntiphonText ? 21 : 23) * contentScale,
                    isItalic: isAntiphonText,
                    lineSpacing: (isAntiphonText ? 3 : 7) * contentScale,
                    marksRubrics: true
                )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
        }
        .padding(
            .bottom,
            isFollowedByContinuation
                ? 24
                : section.kind == .psalm || usesPointedPsalmodyLayout ? 34 : 52
        )
        .animation(.easeInOut(duration: 0.2), value: isPriestOrDeaconPresent)
    }
}

private struct ActiveCantorScoreView: View {
    let score: ChantScore
    let preparation: GregorianScorePreparation
    let onTapEvent: (String) -> Void
    let onActiveNeumeFrameChange: (ActiveNeumeFrame) -> Void

    @Environment(ChantPlaybackController.self) private var playback

    var body: some View {
        GregorianScoreView(
            score: score,
            preparation: preparation,
            highlightedEventID: playback.currentEventID,
            onTapEvent: onTapEvent,
            onActiveNeumeFrameChange: onActiveNeumeFrameChange
        )
    }
}

private extension OfficeSectionKind {
    /// A part of the Mass that is read, announced by its first line.
    var isMassReading: Bool {
        switch self {
        case .reading, .epistle, .gospel, .lastGospel: true
        default: false
        }
    }
}
