import HoursCore
import Observation
import OSLog
import SwiftUI
import UIKit

struct OfficeReaderView: View {
    let office: OfficeDocument
    let displayMode: AppDisplayMode
    let restoredScrollOffset: Double?
    let restoredScrollAnchor: OfficeReaderScrollAnchor?
    let onScrollOffsetChange: (Double, OfficeReaderScrollAnchor?) -> Void

    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedScore: ChantScore?
    @State private var selectedScoreSectionID: String?
    @State private var showsSections = false
    @State private var pendingSectionJumpID: String?
    @State private var showsOptions = false
    @State private var isPreparingPrint = false
    @State private var printErrorMessage: String?
    @State private var cantorTracking = CantorGuideTrackingState()
    @State private var presentation: OfficeReaderPresentation?
    @State private var preparedScores: PreparedOfficeScores?
    @State private var transientState = OfficeReaderTransientState()

    private static let topAnchorID = "office-reader-top"

    private var readerScale: CGFloat {
        CGFloat(
            GregorianLayoutMetrics.clampedNotationScale(
                model.notationScale
            )
        )
    }

    init(
        office: OfficeDocument,
        displayMode: AppDisplayMode,
        restoredScrollOffset: Double? = nil,
        restoredScrollAnchor: OfficeReaderScrollAnchor? = nil,
        onScrollOffsetChange: @escaping (Double, OfficeReaderScrollAnchor?) -> Void = { _, _ in }
    ) {
        self.office = office
        self.displayMode = displayMode
        self.restoredScrollOffset = restoredScrollOffset
        self.restoredScrollAnchor = restoredScrollAnchor
        self.onScrollOffsetChange = onScrollOffsetChange
    }

    var body: some View {
        GeometryReader { geometry in
            if office.format == .contentUnavailable {
                unavailableOffice
            } else if let presentation,
                      presentation.officeID == office.id {
                let sections = presentation.sections
                let firstChantSectionID = sections.first(where: {
                    $0.chant != nil
                })?.id
                let scores = presentation.scores
                let scoreWidth = min(geometry.size.width, 820)
                let preparationKey = ScorePreparationKey(
                    officeID: office.id,
                    scoreSignature: presentation.scoreSignature,
                    width: Int(scoreWidth.rounded()),
                    notationScale: Int((model.notationScale * 100).rounded()),
                    lyricScale: Int(
                        (GregorianScoreView.lyricScale(for: dynamicTypeSize) * 100)
                            .rounded()
                    )
                )
                ZStack {
                    if let preparedScores,
                       preparedScores.key == preparationKey {
                        ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                officeHeader
                                    .id(Self.topAnchorID)
                                    .background {
                                        OfficeReaderScrollViewAccessor { scrollView, view in
                                            transientState.scrollView = scrollView
                                            transientState.registerSectionView(view, for: Self.topAnchorID)
                                        }
                                    }

                                ForEach(
                                    Array(sections.enumerated()),
                                    id: \.element.id
                                ) { index, section in
                                    OfficeSectionView(
                                        section: section,
                                        isFollowedByContinuation: sections.indices.contains(index + 1)
                                            && sections[index + 1].title.isEmpty,
                                        showsEnglish: model.showsEnglish,
                                        usesCompactPsalmody:
                                            model.usesCompactPsalmody,
                                        isPriestOrDeaconPresent: model.isPriestOrDeaconPresent,
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
                        .accessibilityIdentifier("office-reader-scroll")
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
                            }
                            if phase == .animating {
                                transientState.sectionJumpToken = nil
                                transientState.protectedAnchor = nil
                            }
                            guard phase == .idle, scenePhase == .active else { return }
                            // Let section frames catch up with the final scroll geometry.
                            DispatchQueue.main.async { saveScrollOffset() }
                        }
                        .task(id: scenePhase) {
                            guard scenePhase == .active else { return }
                            await restoreScrollPosition(sections: sections, using: proxy)
                        }
                        .task(id: tour.step) {
                            guard tour.step == .tapFirstNeume,
                                  let firstChantSectionID else { return }
                            await Task.yield()
                            transientState.protectedAnchor = nil
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(
                                    firstChantSectionID,
                                    anchor: .top
                                )
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if let selectedScore {
                                PlaybackControlsView(
                                    score: selectedScore,
                                    onClose: closeCantorGuide
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
                        .sheet(
                            isPresented: $showsSections,
                            onDismiss: {
                                jumpToPendingSection(using: proxy)
                            }
                        ) {
                            OfficeSectionsSheet(
                                entries: presentation.outlineEntries,
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
                    }
                    } else {
                        preparingOffice
                    }
                }
                .task(id: preparationKey) {
                    let metrics = GregorianLayoutMetrics(
                        notationScale: model.notationScale,
                        lyricScale: GregorianScoreView.lyricScale(
                            for: dynamicTypeSize
                        )
                    )
                    let scoresByID = await GregorianScorePreparer.prepare(
                        scores: scores,
                        width: scoreWidth,
                        metrics: metrics
                    )
                    guard !Task.isCancelled else { return }
                    preparedScores = PreparedOfficeScores(
                        key: preparationKey,
                        scores: scoresByID
                    )
                }
            } else {
                preparingOffice
            }
        }
        .background {
            if displayMode.showsAmbientSky {
                AmbientSkyView(
                    selection: office.hour
                )
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if office.format != .contentUnavailable {
                    HStack(spacing: 2) {
                        Button {
                            guard !tour.isActive
                                    || tour.step == .openReaderContents else {
                                return
                            }
                            showsSections = true
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 15, weight: .regular))
                                .frame(width: 34, height: 34)
                                .appTourTarget(.readerContents)
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
                                .appTourTarget(.readerOptions)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Prayer options")
                        .accessibilityIdentifier("prayer-options")
                    }
                }
            }
        }
        .onDisappear {
            transientState.sectionJumpToken = nil
            transientState.protectedAnchor = nil
            playback.stop()
        }
        .task(
            id: OfficeReaderPresentationKey(
                officeID: office.id,
                usesCompactPsalmody: model.usesCompactPsalmody
            )
        ) {
            guard office.format != .contentUnavailable else { return }
            presentation = nil
            preparedScores = nil

            let office = office
            let usesCompactPsalmody = model.usesCompactPsalmody
            let preparationTask = Task.detached(
                priority: .userInitiated
            ) {
                try OfficeReaderPresentation.prepare(
                    office: office,
                    usesCompactPsalmody: usesCompactPsalmody
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
        .onChange(of: model.isPriestOrDeaconPresent) { _, _ in
            closeCantorGuide()
        }
        .onChange(of: model.usesCompactPsalmody) { _, _ in
            closeCantorGuide()
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

    private var unavailableOffice: some View {
        ScrollView {
            VStack(spacing: 0) {
                officeHeader
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

    private func jumpToPendingSection(using proxy: ScrollViewProxy) {
        guard let sectionID = pendingSectionJumpID else { return }
        pendingSectionJumpID = nil
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
            withTransaction(transaction) { proxy.scrollTo(sectionID, anchor: .top) }
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
                    withTransaction(transaction) { proxy.scrollTo(sectionID, anchor: .top) }
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

    private func closeCantorGuide() {
        playback.stop()
        selectedScore = nil
        selectedScoreSectionID = nil
        cantorTracking.reset()
        tour.receive(.cantorGuideClosed)
    }

    private func printCurrentOffice() {
        guard !isPreparingPrint, !tour.isActive else { return }
        let snapshot = OfficePrintSnapshot(
            office: office,
            showsEnglish: model.showsEnglish,
            usesCompactPsalmody: model.usesCompactPsalmody,
            isPriestOrDeaconPresent: model.isPriestOrDeaconPresent,
            readerScale: model.notationScale
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
        onScrollOffsetChange(offset, anchor)
    }

    private func restoreScrollPosition(
        sections: [OfficeSection],
        using proxy: ScrollViewProxy
    ) async {
        // This task also runs when score preparation recreates the ScrollView.
        // Capture the last settled position before new layout can overwrite it.
        let savedOffset = transientState.savedOffset ?? restoredScrollOffset ?? 0
        let savedAnchor = transientState.savedAnchor ?? restoredScrollAnchor
        transientState.protectedAnchor = nil
        transientState.hasAppliedInitialScroll = false
        transientState.userInterruptedRestoration = false
        await Task.yield()
        guard !Task.isCancelled else { return }

        if let testScoreID = Self.uiTestScoreID,
           let section = sections.first(where: { $0.chant?.id == testScoreID }) {
            proxy.scrollTo(section.id, anchor: .top)
            transientState.hasAppliedInitialScroll = true
            return
        } else if let testSectionID = Self.uiTestSectionID {
            proxy.scrollTo(testSectionID, anchor: .top)
            transientState.hasAppliedInitialScroll = true
            return
        }

        let anchor = savedAnchor.flatMap { saved in
            saved.sectionID == Self.topAnchorID || sections.contains(where: { $0.id == saved.sectionID })
                ? saved : nil
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        if let anchor, transientState.sectionFrames[anchor.sectionID] == nil {
            // Resolve the actual section first; a lazy stack's total height is
            // only an estimate until the surrounding chant views are laid out.
            withTransaction(transaction) { proxy.scrollTo(anchor.sectionID, anchor: .top) }
        }

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
            let maximum = max(0, scrollView.contentSize.height
                + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height)
            let target: CGFloat
            if let anchor {
                guard let frame = transientState.sectionFrames[anchor.sectionID] else {
                    withTransaction(transaction) { proxy.scrollTo(anchor.sectionID, anchor: .top) }
                    continue
                }
                target = OfficeReaderScrollRestoration.offset(
                    Double(currentOffset + frame.minY) - anchor.viewportY,
                    maximumOffset: maximum
                )
            } else {
                target = OfficeReaderScrollRestoration.offset(
                    savedOffset,
                    maximumOffset: maximum
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

    private var officeHeader: some View {
        let observanceLatin = ObservanceTitle.latin(
            office.observance?.titleLatin ?? office.contextLabel
        )
        let observanceEnglish = office.observance?.titleEnglish.map(
            ObservanceTitle.english
        )
        return VStack(spacing: 10) {
            if model.isDevelopmentCorpus {
                Text("DEVELOPMENT CORPUS")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("development-corpus-banner")
            }

            Text(
                office.observance?.rankLabel
                    ?? model.selectedDay?.rankLabel
                    ?? office.hour.englishTitle
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

            Text(office.titleLatin)
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

            if model.showsEnglish,
               let titleEnglish = OfficeBilingualText.distinctEnglish(
                office.titleEnglish,
                from: office.titleLatin
               ) {
                Text(titleEnglish)
                    .font(
                        .custom(
                            "EBGaramond-Regular",
                            size: 23 * readerScale,
                            relativeTo: .title3
                        )
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text(observanceLatin)
                .font(
                    .custom(
                        "EBGaramond-Regular",
                        size: 19 * readerScale,
                        relativeTo: .body
                    )
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.showsEnglish,
               let titleEnglish = OfficeBilingualText.distinctEnglish(
                observanceEnglish,
                from: observanceLatin
               ) {
                Text(titleEnglish)
                    .font(
                        .custom(
                            "EBGaramond-Regular",
                            size: 18 * readerScale,
                            relativeTo: .body
                        )
                    )
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 38)
        .frame(maxWidth: .infinity)
    }
}

private struct OfficeReaderPresentationKey: Hashable {
    let officeID: String
    let usesCompactPsalmody: Bool
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

    static func prepare(
        office: OfficeDocument,
        usesCompactPsalmody: Bool = false
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
            usesCompactPsalmody: usesCompactPsalmody
        )
        try Task.checkCancellation()

        var seenScoreIDs: Set<String> = []
        let scores = sections.compactMap(\.chant).filter {
            seenScoreIDs.insert($0.id).inserted
        }
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

private struct ScorePreparationKey: Hashable {
    let officeID: String
    let scoreSignature: Int
    let width: Int
    let notationScale: Int
    let lyricScale: Int
}

private struct PreparedOfficeScores {
    let key: ScorePreparationKey
    let scores: [String: GregorianScorePreparation]
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
    static func displaySections(
        from source: [OfficeSection],
        format: OfficeDocument.Format?,
        usesCompactPsalmody: Bool = false
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
            return section.replacingPresentation(title: title, latin: latin, english: .some(english))
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
            id: "\(section.id)-compact-continuation",
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

    private struct PsalmodyEnglishAlignment {
        let verses: [String?]
        let trailing: [String]
    }

    private static func aligningPsalmodyEnglish(
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

    private static func serializedPsalmodyEnglish(
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

    private static func scoredVerseElements(
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

    private static func pointedLyricText(
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

    private static func normalizingTrailingVerseOrdinals(
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

    private static func paragraphs(in value: String) -> [String] {
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

    private static func isAntiphonParagraph(_ paragraph: String) -> Bool {
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
        let parts = value[..<separator].split(separator: ":")
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
    let isPreparingPrint: Bool
    let isPrintingAvailable: Bool
    let onPrint: () -> Void
    let onClose: () -> Void

    var body: some View {
        @Bindable var model = model
        @Bindable var playback = playback

        NavigationStack {
            Form {
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

                Section("Display") {
                    Toggle(
                        "Show English",
                        isOn: Binding(
                            get: { model.showsEnglish },
                            set: { isVisible in
                                model.showsEnglish = isVisible
                                tour.receive(
                                    .englishVisibilityChanged(isVisible)
                                )
                            }
                        )
                    )
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("translation-toggle")
                    .appTourTarget(.readerEnglish)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard tour.step == .enableEnglish else { return }
                            model.showsEnglish = true
                            tour.receive(.englishVisibilityChanged(true))
                        }
                    )

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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Reader size", systemImage: "textformat.size")
                            Spacer()
                            Text("\(Int((model.notationScale * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $model.notationScale,
                            in: GregorianLayoutMetrics.notationScaleRange,
                            step: 0.1
                        )
                        .accessibilityLabel("Reader size")
                        .accessibilityIdentifier("neume-size-slider")
                    }

                    Button("Reset reader size") {
                        model.notationScale = AppModel.defaultNotationScale
                    }
                    .disabled(
                        model.notationScale == AppModel.defaultNotationScale
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
                            Label("Print this hour", systemImage: "printer")
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
                            "Prints this hour using the current prayer "
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
                if model.showsEnglish {
                    tour.receive(.englishVisibilityChanged(true))
                }
            }
        }
        .onChange(of: model.showsEnglish) { _, isVisible in
            tour.receive(.englishVisibilityChanged(isVisible))
        }
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
        let latinParagraphs = paragraphs(in: latin)
        let englishParagraphs = english.map { paragraphs(in: $0) }
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
        let parts = prefix.split(separator: ":")
        guard parts.count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
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

        let scriptureParts = prefix.split(separator: ":")
        if scriptureParts.count == 2,
           scriptureParts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
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
    let showsEnglish: Bool
    let isPriestOrDeaconPresent: Bool
    let contentScale: CGFloat

    private var lines: [PsalmTextLine] {
        PsalmTextFormatter.lines(
            latin: OfficePrayerText.adjusted(
                section.latin,
                isPriestOrDeaconPresent: isPriestOrDeaconPresent
            ),
            english: section.english.map {
                OfficePrayerText.adjusted(
                    $0,
                    isPriestOrDeaconPresent: isPriestOrDeaconPresent
                )
            },
            startsAfterScoredVerse: section.title.isEmpty
        )
    }

    var body: some View {
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

                    VStack(alignment: .leading, spacing: 8) {
                        let displayedLatin = line.number.map {
                            "\($0). \(line.latin)"
                        } ?? line.latin
                        SelectableTextView(
                            text: line.latin,
                            fontSize: 21 * contentScale,
                            lineSpacing: 3 * contentScale,
                            emphasizedRanges: line.emphasizedRanges,
                            highlightsAsterisks: true
                        )
                        .accessibilityIdentifier("selectable-prayer-text")
                        .accessibilityLabel(displayedLatin)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if showsEnglish,
                           let english = OfficeBilingualText.distinctEnglish(
                            line.english,
                            from: line.latin
                           ) {
                            SelectableTextView(
                                text: english,
                                fontSize: 18 * contentScale,
                                isItalic: true,
                                foreground: .secondary,
                                lineSpacing: 3 * contentScale
                            )
                            .accessibilityIdentifier("selectable-prayer-text")
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct OfficeSectionView: View {
    let section: OfficeSection
    let isFollowedByContinuation: Bool
    let showsEnglish: Bool
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
    @ScaledMetric(relativeTo: .caption)
    private var sectionTranslationHeadingSize = 12.0

    private var translationFont: Font {
        let base = Font.custom(
            "EBGaramond-Regular",
            size: 19 * contentScale,
            relativeTo: .body
        )
        return section.chant == nil ? base : base.italic()
    }

    private var usesPointedPsalmodyLayout: Bool {
        section.chant == nil
            && (section.kind == .psalm
                || usesCompactPsalmody && section.kind == .canticle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !section.title.isEmpty {
                if section.kind == .psalm {
                    Text(section.title)
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
                } else {
                    VStack(spacing: 5) {
                        Text(section.title.uppercased())
                            .font(
                                .system(
                                    size: sectionHeadingSize * contentScale,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .tracking(1.5 * contentScale)

                        if showsEnglish,
                           let titleEnglish = OfficeBilingualText.distinctEnglish(
                            section.titleEnglish,
                            from: section.title
                           ) {
                            Text(titleEnglish)
                                .font(
                                    .system(
                                        size: sectionTranslationHeadingSize
                                            * contentScale,
                                        design: .rounded
                                    )
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
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

            if let rubric = section.userFacingRubric {
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

                    if showsEnglish,
                       let rubricEnglish = OfficeBilingualText.distinctEnglish(
                        section.rubricEnglish,
                        from: rubric
                       ) {
                        Text(rubricEnglish)
                            .font(translationFont.italic())
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            if let score = section.chant,
               !OfficePrayerText.requiresTextFallback(section.latin, isPriestOrDeaconPresent: isPriestOrDeaconPresent) {
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
                    showsEnglish: showsEnglish,
                    isPriestOrDeaconPresent: isPriestOrDeaconPresent,
                    contentScale: contentScale
                )
            } else {
                SelectableTextView(
                    text: OfficePrayerText.adjusted(
                        section.latin,
                        isPriestOrDeaconPresent: isPriestOrDeaconPresent
                    ),
                    fontSize: 23 * contentScale,
                    lineSpacing: 7 * contentScale
                )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            if !usesPointedPsalmodyLayout,
               let english = displayedEnglish {
                SelectableTextView(
                    text: english,
                    fontSize: 19 * contentScale,
                    isItalic: section.chant != nil,
                    foreground: .secondary,
                    lineSpacing: 5 * contentScale
                )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(
            .bottom,
            isFollowedByContinuation
                ? 24
                : section.kind == .psalm || usesPointedPsalmodyLayout ? 34 : 52
        )
        .animation(.easeInOut(duration: 0.2), value: showsEnglish)
        .animation(.easeInOut(duration: 0.2), value: isPriestOrDeaconPresent)
    }

    private var displayedEnglish: String? {
        guard showsEnglish,
              let english = section.english else { return nil }
        return OfficeBilingualText.distinctEnglish(
            OfficePrayerText.adjusted(
                section.kind == .psalm ? PsalmTextFormatter.scriptureParagraphs(from: english) : english,
                isPriestOrDeaconPresent: isPriestOrDeaconPresent
            ),
            from: OfficePrayerText.adjusted(
                section.latin,
                isPriestOrDeaconPresent: isPriestOrDeaconPresent
            )
        )
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
