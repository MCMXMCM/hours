import HoursCore
import Observation
import OSLog
import SwiftUI

struct OfficeReaderView: View {
    let office: OfficeDocument
    let displayMode: AppDisplayMode
    let restoredScrollOffset: Double?
    let onScrollOffsetChange: (Double) -> Void

    @Environment(AppModel.self) private var model
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedScore: ChantScore?
    @State private var selectedScoreSectionID: String?
    @State private var showsSections = false
    @State private var showsOptions = false
    @State private var cantorTracking = CantorGuideTrackingState()
    @State private var presentation: OfficeReaderPresentation?
    @State private var preparedScores: PreparedOfficeScores?
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var hasAppliedInitialScroll = false
    @State private var transientState = OfficeReaderTransientState()

    private static let topAnchorID = "office-reader-top"

    init(
        office: OfficeDocument,
        displayMode: AppDisplayMode,
        restoredScrollOffset: Double? = nil,
        onScrollOffsetChange: @escaping (Double) -> Void = { _ in }
    ) {
        self.office = office
        self.displayMode = displayMode
        self.restoredScrollOffset = restoredScrollOffset
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
                            VStack(spacing: 0) {
                                officeHeader
                                    .id(Self.topAnchorID)

                                ForEach(
                                    Array(sections.enumerated()),
                                    id: \.element.id
                                ) { index, section in
                                    OfficeSectionView(
                                        section: section,
                                        isFollowedByContinuation: sections.indices.contains(index + 1)
                                            && sections[index + 1].title.isEmpty,
                                        showsEnglish: model.showsEnglish,
                                        isPriestOrDeaconPresent: model.isPriestOrDeaconPresent,
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
                                }
                            }
                            .frame(maxWidth: 820)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 100)
                        }
                        .scrollPosition($scrollPosition)
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            max(0, geometry.visibleRect.minY)
                        } action: { _, offset in
                            transientState.latestScrollOffset = offset
                        }
                        .onScrollPhaseChange { _, phase in
                            guard phase == .idle else { return }
                            saveScrollOffset()
                        }
                        .task {
                            await Task.yield()
                            if let testScoreID = Self.uiTestScoreID,
                               let testSection = sections.first(where: {
                                   $0.chant?.id == testScoreID
                               }) {
                                proxy.scrollTo(testSection.id, anchor: .top)
                            } else if let testSectionID = Self.uiTestSectionID {
                                proxy.scrollTo(testSectionID, anchor: .top)
                            } else if let restoredScrollOffset {
                                transientState.latestScrollOffset = CGFloat(
                                    restoredScrollOffset
                                )
                                scrollPosition.scrollTo(
                                    y: restoredScrollOffset
                                )
                            } else {
                                proxy.scrollTo(Self.topAnchorID, anchor: .top)
                            }
                            await Task.yield()
                            hasAppliedInitialScroll = true
                        }
                        .task(id: tour.step) {
                            guard tour.step == .tapFirstNeume,
                                  let firstChantSectionID else { return }
                            await Task.yield()
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
                        .sheet(isPresented: $showsSections) {
                            OfficeSectionsSheet(
                                entries: presentation.outlineEntries,
                                onSelect: { entry in
                                    withAnimation(
                                        .easeInOut(duration: 0.3)
                                    ) {
                                        proxy.scrollTo(
                                            entry.id,
                                            anchor: .top
                                        )
                                    }
                                    tour.receive(
                                        .readerSectionSelected(entry.title)
                                    )
                                    showsSections = false
                                }
                            )
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                            .appTourOverlayHost(.reader)
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
            PrayerOptionsView {
                showsOptions = false
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.hoursBackground)
                .appTourOverlayHost(.reader)
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
            playback.stop()
        }
        .task(id: office.id) {
            guard office.format != .contentUnavailable else { return }
            presentation = nil
            preparedScores = nil

            let office = office
            let preparationTask = Task.detached(
                priority: .userInitiated
            ) {
                try OfficeReaderPresentation.prepare(office: office)
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
            saveScrollOffset()
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

    private func closeCantorGuide() {
        playback.stop()
        selectedScore = nil
        selectedScoreSectionID = nil
        cantorTracking.reset()
        tour.receive(.cantorGuideClosed)
    }

    private func saveScrollOffset() {
        guard hasAppliedInitialScroll else { return }
        onScrollOffsetChange(
            Double(transientState.latestScrollOffset)
        )
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
        VStack(spacing: 10) {
            if model.isDevelopmentCorpus {
                Text("DEVELOPMENT CORPUS")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("development-corpus-banner")
            }

            Text(
                office.observance?.rank?.displayName
                    ?? model.selectedDay?.rank?.displayName
                    ?? office.hour.englishTitle
            )
                .font(.custom("EBGaramond-Regular", size: 18, relativeTo: .body))
                .foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))

            Text(office.titleLatin)
                .font(.custom("EBGaramond-Regular", size: 43, relativeTo: .largeTitle))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineSpacing(-4)
                .accessibilityIdentifier("office-reader-title")

            if model.showsEnglish,
               let titleEnglish = office.titleEnglish,
               !titleEnglish.isEmpty {
                Text(titleEnglish)
                    .font(.custom("EBGaramond-Regular", size: 23, relativeTo: .title3))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text(office.observance?.titleLatin ?? office.contextLabel)
                .font(.custom("EBGaramond-Regular", size: 19, relativeTo: .body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.showsEnglish,
               let titleEnglish = office.observance?.titleEnglish,
               !titleEnglish.isEmpty {
                Text(titleEnglish)
                    .font(.custom("EBGaramond-Regular", size: 18, relativeTo: .body))
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
        office: OfficeDocument
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
            format: office.format
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

private final class OfficeReaderTransientState {
    var latestScrollOffset: CGFloat = 0
}

nonisolated struct OfficeReaderOutlineEntry: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
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
                List(entries) { entry in
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
                    .id(entry.id)
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
                        proxy.scrollTo(entry.id, anchor: .center)
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
        format: OfficeDocument.Format?
    ) -> [OfficeSection] {
        if format == .authoritativeOrdered {
            // The authoritative corpus repeats a part's title on each atomic
            // prayer or score across every hour. Preserve its order, fold
            // prose that is actually covered by a score into that score, and
            // present one heading for the whole office part.
            return suppressingRepeatedHeadings(
                interleavingTextWithNonPsalmChants(
                    source,
                    allowsTitleFallback: false
                )
            )
        }
        return sections(from: source)
    }

    static func sections(from source: [OfficeSection]) -> [OfficeSection] {
        let source = interleavingTextWithNonPsalmChants(
            interleavingCompactPsalmody(correctedSource(source))
        )
        return suppressingRepeatedHeadings(source)
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

    private static func bestTextIndex(
        matching chant: OfficeSection,
        at chantIndex: Int,
        in source: [OfficeSection],
        candidates: [Int]
    ) -> Int? {
        let scoreWords = scoredWords(in: chant)
        guard scoreWords.count >= 4 else { return nil }

        return candidates
            .map {
                (
                    index: $0,
                    run: longestSharedRun(
                        scoreWords,
                        normalizedLatinWords(source[$0].latin)
                    )
                )
            }
            .filter { $0.run >= 4 }
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
                    rubric: nil,
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
                    rubric: nil,
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
                    rubric: nil,
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

    private static func correctedSource(_ source: [OfficeSection]) -> [OfficeSection] {
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
            let retained = values.filter { paragraph in
                !isAntiphonParagraph(paragraph)
                    || !standaloneAntiphonTranslations.contains(
                        presentationTranslation(from: paragraph)
                    )
            }
            guard retained.count != values.count else { return section }
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
           targetIndexBeforeRemoval > 1 {
            corrected.removeFirst()
            if let targetIndex = corrected.firstIndex(where: { $0.id == targetID }) {
                corrected.insert(opening, at: targetIndex)
            }
        }

        return corrected
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
            let run = longestSharedRun(scoredWords, normalizedLatinWords(section.latin))
            if run >= 4, run > (best?.run ?? 3) {
                best = (section.id, run)
            }
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

    private static func longestSharedRun(_ left: [String], _ right: [String]) -> Int {
        var longest = 0
        for leftIndex in left.indices {
            for rightIndex in right.indices {
                var length = 0
                while leftIndex + length < left.count,
                      rightIndex + length < right.count,
                      left[leftIndex + length] == right[rightIndex + length] {
                    length += 1
                }
                longest = max(longest, length)
            }
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

enum OfficePrayerText {
    private static let layLatinGreeting = """
    ℣. Dómine, exáudi oratiónem meam.

    ℟. Et clamor meus ad te véniat.
    """
    private static let clericalLatinGreeting = """
    ℣. Dóminus vobíscum.

    ℟. Et cum spíritu tuo.
    """
    private static let layEnglishGreeting = """
    ℣. O Lord, hear my prayer.

    ℟. And let my cry come unto thee.
    """
    private static let clericalEnglishGreeting = """
    ℣. The Lord be with you.

    ℟. And with thy spirit.
    """

    static func adjusted(_ text: String, isPriestOrDeaconPresent: Bool) -> String {
        guard isPriestOrDeaconPresent else { return text }

        return text
            .replacingOccurrences(
                of: layLatinGreeting,
                with: clericalLatinGreeting
            )
            .replacingOccurrences(
                of: layEnglishGreeting,
                with: clericalEnglishGreeting
            )
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

    nonisolated func replacingPresentation(
        id: String? = nil,
        title: String? = nil,
        titleEnglish: String?? = nil,
        rubric: String? = nil,
        rubricEnglish: String?? = nil,
        latin: String? = nil,
        english: String?? = nil
    ) -> OfficeSection {
        OfficeSection(
            id: id ?? self.id,
            kind: kind,
            title: title ?? self.title,
            titleEnglish: titleEnglish ?? (title == "" ? nil : self.titleEnglish),
            rubric: rubric,
            rubricEnglish: rubricEnglish ?? (rubric == nil ? nil : self.rubricEnglish),
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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Neume size", systemImage: "textformat.size")
                            Spacer()
                            Text("\(Int((model.notationScale * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $model.notationScale,
                            in: 0.8...1.6,
                            step: 0.1
                        )
                        .accessibilityLabel("Neume size")
                        .accessibilityIdentifier("neume-size-slider")
                    }

                    Button("Reset neume size") {
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
}

enum PsalmTextFormatter {
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
            let stripped = strippingScriptureReference(from: paragraph)
            let isNumberedVerse = stripped != paragraph
            let number = isNumberedVerse ? verseNumber : nil
            if isNumberedVerse {
                verseNumber += 1
            }
            return PsalmTextLine(
                id: index,
                number: number,
                latin: stripped,
                english: translationsAlign
                    ? englishParagraphs.map {
                        strippingScriptureReference(from: $0[index])
                    }
                    : nil
            )
        }
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

    nonisolated static func strippingScriptureReference(
        from value: String
    ) -> String {
        guard let separator = value.firstIndex(where: \.isWhitespace) else {
            return value
        }
        let prefix = value[..<separator]
        let parts = prefix.split(separator: ":")
        guard parts.count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else {
            return value
        }
        return value[value.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Character {
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

private extension Substring {
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let number = line.number {
                            Text("\(number).")
                                .frame(width: 30, alignment: .trailing)
                        }
                        SelectableTextView(
                            text: line.latin,
                            fontSize: 21,
                            lineSpacing: 3,
                            emphasizedRanges:
                                PsalmTextFormatter.emphasizedSyllableRanges(
                                    in: line.latin
                                ),
                            highlightsAsterisks: true
                        )
                            .accessibilityIdentifier("selectable-prayer-text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.custom("EBGaramond-Regular", size: 21, relativeTo: .body))

                    if showsEnglish, let english = line.english {
                        SelectableTextView(
                            text: english,
                            fontSize: 18,
                            isItalic: true,
                            foreground: .secondary,
                            lineSpacing: 3
                        )
                            .accessibilityIdentifier("selectable-prayer-text")
                            .padding(.leading, line.number == nil ? 0 : 40)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
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
    let isPriestOrDeaconPresent: Bool
    let scorePreparation: GregorianScorePreparation?
    let isCantorGuideScore: Bool
    let isAppTourFirstChant: Bool
    let onTapEvent: (ChantScore, String) -> Void
    let onActiveNeumeFrameChange: (ActiveNeumeFrame) -> Void

    private var translationFont: Font {
        let base = Font.custom(
            "EBGaramond-Regular",
            size: 19,
            relativeTo: .body
        )
        return section.chant == nil ? base : base.italic()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !section.title.isEmpty {
                if section.kind == .psalm {
                    Text(section.title)
                        .font(
                            .custom(
                                "EBGaramond-Regular",
                                size: 20,
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
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .tracking(1.5)

                        if showsEnglish,
                           let titleEnglish = section.titleEnglish,
                           !titleEnglish.isEmpty {
                            Text(titleEnglish)
                                .font(.system(.caption, design: .rounded))
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
                        .font(.custom("EBGaramond-Regular", size: 17, relativeTo: .body).italic())

                    if showsEnglish,
                       let rubricEnglish = section.rubricEnglish,
                       !rubricEnglish.isEmpty {
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

            if let score = section.chant {
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
            } else if section.kind == .psalm {
                PsalmTextSectionView(
                    section: section,
                    showsEnglish: showsEnglish,
                    isPriestOrDeaconPresent: isPriestOrDeaconPresent
                )
            } else {
                SelectableTextView(
                    text: OfficePrayerText.adjusted(
                        section.latin,
                        isPriestOrDeaconPresent: isPriestOrDeaconPresent
                    ),
                    fontSize: 23,
                    lineSpacing: 7
                )
                    .accessibilityIdentifier("selectable-prayer-text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            if showsEnglish,
               section.chant != nil || section.kind != .psalm,
               let english = section.english {
                SelectableTextView(
                    text: OfficePrayerText.adjusted(
                        english,
                        isPriestOrDeaconPresent: isPriestOrDeaconPresent
                    ),
                    fontSize: 19,
                    isItalic: section.chant != nil,
                    foreground: .secondary,
                    lineSpacing: 5
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
            isFollowedByContinuation ? 24 : section.kind == .psalm ? 34 : 52
        )
        .animation(.easeInOut(duration: 0.2), value: showsEnglish)
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
