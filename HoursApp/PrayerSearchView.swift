import HoursCore
import SwiftUI
import UIKit

struct PrayerSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.dismiss) private var dismiss
    let onOpenOffice: (LiturgicalUsageContext) -> Void
    @AppStorage(AppTourPersistence.recentQueriesKey)
    private var recentQueriesJSON = "[]"
    @AppStorage(AppTourPersistence.recentHitsKey)
    private var recentHitsJSON = "[]"
    @State private var query = ""
    @State private var language = LiturgicalSearchLanguage.all
    @State private var category = PrayerSearchCategory.all
    @State private var hour: OfficeHour?
    @State private var searchPhase = PrayerSearchPhase.idle
    @State private var isSearching = false

    init(
        onOpenOffice: @escaping (LiturgicalUsageContext) -> Void = { _ in }
    ) {
        self.onOpenOffice = onOpenOffice
    }

    private var searchKey: SearchKey {
        SearchKey(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            category: category,
            hour: hour
        )
    }

    private var recentQueries: [String] {
        Self.decode([String].self, from: recentQueriesJSON) ?? []
    }

    private var recentHits: [LiturgicalSearchHit] {
        Self.decode([LiturgicalSearchHit].self, from: recentHitsJSON) ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    PrayerSearchBar(
                        text: $query,
                        shouldFocus: tour.shouldFocusSearchField,
                        onSubmit: submitSearch
                    )
                    .appTourTarget(.searchField)

                    SheetCloseButton(
                        accessibilityLabel: "Close Search",
                        accessibilityIdentifier: "prayer-search-close",
                        action: dismiss.callAsFunction
                    )
                    .appTourTarget(.searchClose)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if !searchKey.query.isEmpty {
                    PrayerSearchFilterBar(
                        category: $category,
                        hour: $hour,
                        language: $language,
                        isSearching: isSearching
                    )
                }
                searchContent
            }
                .background(Color.hoursBackground)
        }
        .task(id: searchKey) {
            await performSearch(for: searchKey)
        }
        .onAppear {
            tour.receive(.searchOpened)
        }
    }

    private func submitSearch() {
        recordRecentQuery(searchKey.query)
        tour.receive(.searchSubmitted(searchKey.query))
    }

    @ViewBuilder
    private var searchContent: some View {
        switch searchPhase {
        case .idle:
            recentContent
        case .failed(let message):
            ContentUnavailableView(
                "Search unavailable",
                systemImage: "exclamationmark.magnifyingglass",
                description: Text(message)
            )
        case .loadedContent(let results):
            if results.isEmpty {
                ContentUnavailableView.search(text: searchKey.query)
            } else {
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        NavigationLink {
                            PrayerSearchDetailView(
                                hit: result,
                                onOpenOffice: openOffice,
                                onPresented: {
                                    recordRecentQuery(searchKey.query)
                                    recordRecentlyViewed(result)
                                }
                            )
                        } label: {
                            PrayerSearchHitRow(hit: result)
                        }
                        .listRowBackground(Color.hoursBackground)
                        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                        .accessibilityIdentifier("search-result-\(index)")
                        .appTourTarget(
                            .searchResult,
                            when: index == 0
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.hoursBackground)
                .accessibilityIdentifier("prayer-search-results")
            }
        case .loadedTitles(let results):
            if results.isEmpty {
                ContentUnavailableView.search(text: searchKey.query)
            } else {
                List {
                    ForEach(results, id: \.self) { context in
                        Button {
                            recordRecentQuery(searchKey.query)
                            openOffice(context)
                        } label: {
                            PrayerSearchOfficeTitleRow(context: context)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.hoursBackground)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.hoursBackground)
                .accessibilityIdentifier("prayer-search-results")
            }
        }
    }

    @ViewBuilder
    private var recentContent: some View {
        if recentQueries.isEmpty && recentHits.isEmpty {
            ContentUnavailableView(
                "Search the Office",
                systemImage: "text.magnifyingglass",
                description: Text("Find feast days, prayers, readings, psalms, hymns, responsories, and chants in Latin or English.")
            )
        } else {
            List {
                if !recentQueries.isEmpty {
                    Section {
                        ForEach(recentQueries, id: \.self) { recent in
                            Button {
                                query = recent
                            } label: {
                                Label(recent, systemImage: "magnifyingglass")
                                    .foregroundStyle(.primary)
                            }
                            .listRowBackground(Color.hoursBackground)
                        }
                    } header: {
                        historyHeader("Recently Searched") {
                            recentQueriesJSON = "[]"
                        }
                    }
                }
                if !recentHits.isEmpty {
                    Section {
                        ForEach(recentHits) { hit in
                            NavigationLink {
                                PrayerSearchDetailView(
                                    hit: hit,
                                    onOpenOffice: openOffice,
                                    onPresented: {
                                        recordRecentlyViewed(hit)
                                    }
                                )
                            } label: {
                                PrayerSearchHitRow(hit: hit)
                            }
                            .listRowBackground(Color.hoursBackground)
                        }
                    } header: {
                        historyHeader("Recently Viewed") {
                            recentHitsJSON = "[]"
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.hoursBackground)
        }
    }

    private func historyHeader(
        _ title: String,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Button("Clear", action: clear)
                .font(.body)
                .textCase(nil)
        }
        .textCase(nil)
    }

    private func performSearch(for key: SearchKey) async {
        guard !key.query.isEmpty else {
            searchPhase = .idle
            isSearching = false
            return
        }
        var indicator: Task<Void, Never>?
        do {
            try await Task.sleep(for: .milliseconds(225))
            try Task.checkCancellation()
            indicator = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, searchKey == key else { return }
                isSearching = true
            }
            let phase: PrayerSearchPhase
            if key.category == .titles {
                phase = .loadedTitles(
                    try await model.searchOfficeTitles(
                        key.query,
                        language: key.language,
                        hour: key.hour
                    )
                )
            } else {
                phase = .loadedContent(
                    try await model.searchContent(
                        key.query,
                        language: key.language,
                        kind: key.category.kind,
                        hour: key.hour,
                        requiresScore: key.category.requiresScore
                    )
                )
            }
            indicator?.cancel()
            try Task.checkCancellation()
            guard searchKey == key else { return }
            isSearching = false
            searchPhase = phase
            switch phase {
            case .loadedContent(let results):
                tour.receive(
                    .searchResultsLoaded(
                        query: key.query,
                        count: results.count
                    )
                )
            case .loadedTitles(let results):
                tour.receive(
                    .searchResultsLoaded(
                        query: key.query,
                        count: results.count
                    )
                )
            case .idle, .failed:
                break
            }
        } catch is CancellationError {
            indicator?.cancel()
            return
        } catch {
            indicator?.cancel()
            guard !Task.isCancelled, searchKey == key else { return }
            isSearching = false
            searchPhase = .failed(error.localizedDescription)
        }
    }

    private func recordRecentQuery(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var values = recentQueries.filter {
            $0.caseInsensitiveCompare(trimmed) != .orderedSame
        }
        values.insert(trimmed, at: 0)
        recentQueriesJSON = Self.encode(Array(values.prefix(8)))
    }

    private func recordRecentlyViewed(_ hit: LiturgicalSearchHit) {
        var values = recentHits.filter { $0.id != hit.id }
        values.insert(hit, at: 0)
        recentHitsJSON = Self.encode(Array(values.prefix(8)))
    }

    private func openOffice(_ context: LiturgicalUsageContext) {
        dismiss()
        onOpenOffice(context)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(value.utf8))
    }
}

private struct PrayerSearchBar: UIViewRepresentable {
    @Binding var text: String
    let shouldFocus: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Prayer, feast, reading, or chant"
        searchBar.returnKeyType = .search
        searchBar.autocapitalizationType = .none
        searchBar.delegate = context.coordinator
        searchBar.accessibilityIdentifier = "prayer-search-field-region"
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if searchBar.text != text {
            searchBar.text = text
        }
        guard shouldFocus,
              !searchBar.searchTextField.isFirstResponder else { return }
        DispatchQueue.main.async {
            searchBar.searchTextField.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        // Avoid the synthesized isolated-deinit runtime crash on iOS 26.2.
        // https://github.com/swiftlang/swift/issues/88036
        nonisolated deinit {}

        var parent: PrayerSearchBar

        init(parent: PrayerSearchBar) {
            self.parent = parent
        }

        func searchBar(
            _ searchBar: UISearchBar,
            textDidChange searchText: String
        ) {
            parent.text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.searchTextField.resignFirstResponder()
            parent.onSubmit()
        }
    }
}

private enum PrayerSearchPhase {
    case idle
    case loadedContent([LiturgicalSearchHit])
    case loadedTitles([LiturgicalUsageContext])
    case failed(String)
}

private struct SearchKey: Equatable {
    let query: String
    let language: LiturgicalSearchLanguage
    let category: PrayerSearchCategory
    let hour: OfficeHour?
}

enum PrayerSearchCategory: String, CaseIterable, Identifiable {
    case all
    case titles
    case readings
    case hymns
    case chants
    case psalms
    case antiphons
    case responsories
    case collects

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .titles: "Titles"
        case .readings: "Readings"
        case .hymns: "Hymns"
        case .chants: "Chants"
        case .psalms: "Psalms"
        case .antiphons: "Antiphons"
        case .responsories: "Responsories"
        case .collects: "Collects"
        }
    }

    var kind: OfficeSectionKind? {
        switch self {
        case .all, .titles, .chants: nil
        case .readings: .reading
        case .hymns: .hymn
        case .psalms: .psalm
        case .antiphons: .antiphon
        case .responsories: .responsory
        case .collects: .collect
        }
    }

    var requiresScore: Bool { self == .chants }
}

private struct PrayerSearchFilterBar: View {
    @Binding var category: PrayerSearchCategory
    @Binding var hour: OfficeHour?
    @Binding var language: LiturgicalSearchLanguage
    let isSearching: Bool
    @Environment(AppTourCoordinator.self) private var tour

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PrayerSearchCategory.allCases) { option in
                        Button(option.title) {
                            category = option
                            tour.receive(
                                .searchCategorySelected(
                                    option.rawValue
                                )
                            )
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(chipForeground(isActive: category == option))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(chipBackground(isActive: category == option))
                        .clipShape(.capsule)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "search-category-\(option.rawValue)"
                        )
                        .id(option)
                        .modifier(
                            SearchChantsTourTargetModifier(
                                isChants: option == .chants
                            )
                        )
                    }
                    Menu {
                        Picker("Office", selection: $hour) {
                            Text("Any Office").tag(OfficeHour?.none)
                            ForEach(OfficeHour.allCases, id: \.self) { option in
                                Text(option.englishTitle).tag(Optional(option))
                            }
                        }
                    } label: {
                        filterMenuLabel(hour?.englishTitle ?? "Any Office", isActive: hour != nil)
                    }
                    .accessibilityIdentifier("search-office-filter")
                    Menu {
                        Picker("Language", selection: $language) {
                            Text("Both Languages").tag(LiturgicalSearchLanguage.all)
                            Text("Latin").tag(LiturgicalSearchLanguage.latin)
                            Text("English").tag(LiturgicalSearchLanguage.english)
                        }
                    } label: {
                        filterMenuLabel(languageTitle, isActive: language != .all)
                    }
                    .accessibilityIdentifier("search-language-filter")
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 6)
                            .accessibilityLabel("Searching")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .task(id: tour.step) {
                guard tour.step == .chooseChants else { return }
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(
                        PrayerSearchCategory.chants,
                        anchor: .center
                    )
                }
            }
        }
        .background(Color.hoursBackground)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("prayer-search-filter-bar")
    }

    private var languageTitle: String {
        switch language {
        case .all: "Both Languages"
        case .latin: "Latin"
        case .english: "English"
        @unknown default: "Both Languages"
        }
    }

    private func filterMenuLabel(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(chipForeground(isActive: isActive))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(chipBackground(isActive: isActive))
        .clipShape(.capsule)
    }

    private func chipForeground(isActive: Bool) -> Color {
        isActive ? Color.hoursBackground : Color.hoursPrimaryText
    }

    private func chipBackground(isActive: Bool) -> Color {
        isActive ? Color.hoursPrimaryText : Color.secondary.opacity(0.14)
    }
}

private struct SearchChantsTourTargetModifier: ViewModifier {
    let isChants: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isChants {
            content.appTourTarget(.searchCategoryChants)
        } else {
            content
        }
    }
}

private struct PrayerSearchHitRow: View {
    let hit: LiturgicalSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(SearchResultPresentation.title(for: hit))
                    .font(.system(.headline, design: .serif))
                if hit.hasScoredRealizations {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Chant settings available")
                }
            }
            Text(hit.snippet)
                .font(.system(
                    .caption,
                    design: hit.snippetLanguage == .latin ? .serif : .default
                ))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PrayerSearchOfficeTitleRow: View {
    let context: LiturgicalUsageContext

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ObservanceTitle.latin(context.observanceTitleLatin))
                    .font(.system(.headline, design: .serif))
                if let english = context.observanceTitleEnglish,
                   english != context.observanceTitleLatin {
                    Text(ObservanceTitle.english(english))
                        .font(.subheadline)
                }
                Text(officeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this office")
    }

    private var officeSummary: String {
        guard let date = context.firstDate.date else {
            return context.hour.englishTitle
        }
        return "\(context.hour.englishTitle) · "
            + date.formatted(.dateTime.month(.wide).day())
    }
}

private struct PrayerSearchDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.dismiss) private var dismiss
    let hit: LiturgicalSearchHit
    let onOpenOffice: (LiturgicalUsageContext) -> Void
    let onPresented: () -> Void
    @State private var phase = PrayerSearchDetailPhase.loading
    @State private var didNotifyPresentation = false

    init(
        hit: LiturgicalSearchHit,
        onOpenOffice: @escaping (LiturgicalUsageContext) -> Void,
        onPresented: @escaping () -> Void = {}
    ) {
        self.hit = hit
        self.onOpenOffice = onOpenOffice
        self.onPresented = onPresented
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading result…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView(
                    "Result unavailable",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text(message)
                )
            case .loaded(let presentation):
                PrayerSearchDetailContent(
                    presentation: presentation,
                    onOpenOffice: onOpenOffice
                )
            }
        }
        .navigationTitle(SearchResultPresentation.title(for: hit))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(
            tour.isActive && tour.currentLayer == .search
        )
        .toolbar {
            if tour.isActive, tour.currentLayer == .search {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        returnToResults()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .frame(minWidth: 60, minHeight: 44)
                            .contentShape(Rectangle())
                            .appTourTarget(.searchDetailBack)
                    }
                    .accessibilityIdentifier("tour-search-detail-back")
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            returnToResults()
                        }
                    )
                }
            }
        }
        .onAppear {
            guard !didNotifyPresentation else { return }
            didNotifyPresentation = true
            onPresented()
            tour.receive(.searchResultOpened)
        }
        .task(id: hit.id) {
            guard case .loading = phase else { return }
            phase = .loading
            do {
                let result = try await model.searchContentDetail(id: hit.id)
                phase = .loaded(
                    PrayerSearchDetailPresentation(result: result)
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func returnToResults() {
        guard tour.step == .returnToSearchResults else { return }
        tour.receive(.searchDetailClosed)
        dismiss()
    }
}

private enum PrayerSearchDetailPhase {
    case loading
    case loaded(PrayerSearchDetailPresentation)
    case failed(String)
}

private struct PrayerSearchDetailContent: View {
    @Environment(AppTourCoordinator.self) private var tour
    let presentation: PrayerSearchDetailPresentation
    let onOpenOffice: (LiturgicalUsageContext) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section("Latin") {
                    Text(presentation.latinText)
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                }
                if let english = presentation.result.english {
                    Section("English") {
                        Text(english)
                            .textSelection(.enabled)
                    }
                }
                if !presentation.chantSettings.isEmpty {
                    Section("Chant settings") {
                        ForEach(presentation.chantSettings) { setting in
                            NavigationLink {
                                SearchChantView(score: setting.score)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(setting.score.incipit)
                                        .font(.system(.body, design: .serif))
                                    Text(setting.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(setting.score.provenance.sourceBook)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .id(setting.id)
                            .accessibilityIdentifier(
                                "search-chant-setting-\(setting.score.id)"
                            )
                            .appTourTarget(
                                .searchChantSetting,
                                when: setting.id == intendedSettingID
                            )
                        }
                    }
                }
                ForEach(
                    Array(presentation.usageGroups.enumerated()),
                    id: \.element.id
                ) { index, group in
                    Section {
                        ForEach(group.contexts, id: \.self) { context in
                            Button {
                                onOpenOffice(context)
                            } label: {
                                PrayerSearchUsageRow(context: context)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            if index == 0 {
                                Text("Used in the Office")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(group.hour.englishTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .textCase(nil)
                    }
                }
            }
            .task(id: tour.step) {
                guard let intendedSettingID else { return }
                await Task.yield()
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(intendedSettingID, anchor: .center)
                }
            }
        }
    }

    private var intendedSettingID: String? {
        tour.intendedSearchChantSettingID(
            from: presentation.chantSettings.map(\.id)
        )
    }
}

private struct PrayerSearchDetailPresentation {
    let result: LiturgicalSearchResult
    let chantSettings: [PrayerSearchChantSetting]
    let usageGroups: [PrayerSearchUsageGroup]
    let latinText: String

    init(result: LiturgicalSearchResult) {
        self.result = result
        chantSettings = PrayerSearchChantSetting.settings(
            from: result.scoredRealizations
        )

        let contextsByHour = Dictionary(
            grouping: result.contexts,
            by: \.hour
        )
        usageGroups = OfficeHour.allCases.compactMap { hour in
            guard let contexts = contextsByHour[hour] else { return nil }
            return PrayerSearchUsageGroup(
                hour: hour,
                contexts: contexts.sorted { $0.date < $1.date }
            )
        }

        let scoredLatin = result.scoredRealizations.compactMap { score in
            try? GregorianScoreParser.parse(
                gabc: score.gabc,
                timeline: score.timeline
            ).lyricText
        }
        .max(by: { $0.count < $1.count })
        latinText = if let scoredLatin,
                       scoredLatin.count > result.latin.count {
            scoredLatin
        } else {
            result.latin
        }
    }
}

private struct PrayerSearchChantSetting: Identifiable {
    let score: ChantScore
    let variantIndex: Int
    let variantCount: Int

    var id: String { score.id }

    var label: String {
        let mode = score.mode.map { "Mode \($0)" } ?? "Mode unspecified"
        guard variantCount > 1 else { return mode }
        return "\(mode) · Setting \(variantIndex) of \(variantCount)"
    }

    static func settings(
        from scores: [ChantScore]
    ) -> [PrayerSearchChantSetting] {
        let counts = Dictionary(grouping: scores, by: \.mode)
            .mapValues(\.count)
        var indices: [String?: Int] = [:]
        return scores.map { score in
            let index = indices[score.mode, default: 0] + 1
            indices[score.mode] = index
            return PrayerSearchChantSetting(
                score: score,
                variantIndex: index,
                variantCount: counts[score.mode, default: 1]
            )
        }
    }
}

private struct PrayerSearchUsageGroup: Identifiable {
    let hour: OfficeHour
    let contexts: [LiturgicalUsageContext]

    var id: OfficeHour { hour }
}

private struct PrayerSearchUsageRow: View {
    let context: LiturgicalUsageContext

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ObservanceTitle.latin(context.dayTitleLatin))
                    .font(.system(.body, design: .serif))
                if let english = context.dayTitleEnglish,
                   english != context.dayTitleLatin {
                    Text(ObservanceTitle.english(english))
                        .font(.subheadline)
                }
                Text(settingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            "Opens \(context.hour.englishTitle) for this church-calendar day"
        )
    }

    private var settingSummary: String {
        guard !context.settingModes.isEmpty else {
            return "No chant setting"
        }
        return context.settingModes
            .map { "Mode \($0)" }
            .joined(separator: " · ")
    }
}

enum SearchResultPresentation {
    static func title(for hit: LiturgicalSearchHit) -> String {
        title(for: LiturgicalSearchResult(
            id: hit.id,
            kind: hit.kind,
            titleLatin: hit.titleLatin,
            titleEnglish: hit.titleEnglish,
            latin: hit.snippetLanguage == .latin ? hit.snippet : "",
            english: hit.snippetLanguage == .english ? hit.snippet : nil
        ))
    }

    static func title(for result: LiturgicalSearchResult) -> String {
        if isLikelyMatinsReading(result) {
            return readingTitle(for: result)
        }
        switch result.kind {
        case .opening:
            return normalized(result.titleLatin) == "incipit"
                ? "Incipit"
                : "Opening"
        case .invitatory:
            return "Invitatory"
        case .prayer:
            let latin = normalized(result.latin)
            if latin.hasPrefix("confiteor deo") { return "Confiteor" }
            if latin.hasPrefix("pater noster") { return "Our Father" }
            return "Prayer"
        case .rubric:
            return "Rubric"
        case .reading:
            return readingTitle(for: result)
        case .absolution:
            return "Absolution"
        case .blessing:
            return "Blessing"
        case .psalm:
            return normalized(result.titleLatin).hasPrefix("psalm")
                ? result.titleLatin
                : "Psalm"
        case .antiphon:
            return normalized(result.titleLatin).contains("antiphona finalis")
                ? "Marian Antiphon"
                : "Antiphon"
        case .chapter:
            return "Chapter"
        case .responsory:
            return "Responsory"
        case .hymn:
            return "Hymn"
        case .versicle:
            return "Versicle"
        case .canticle:
            return normalized(result.titleLatin).hasPrefix("canticum")
                ? result.titleLatin
                : "Canticle"
        case .collect:
            return "Collect"
        case .preces:
            return "Preces"
        case .conclusion:
            return "Conclusion"
        case .marianAntiphon:
            return "Marian Antiphon"
        @unknown default:
            return "Office Text"
        }
    }

    private static func readingTitle(for result: LiturgicalSearchResult) -> String {
        let hours = Set(result.contexts.map(\.hour))
        guard hours.count == 1, let hour = hours.first else {
            return "Reading"
        }
        return "\(hour.englishTitle) Reading"
    }

    private static func isLikelyMatinsReading(
        _ result: LiturgicalSearchResult
    ) -> Bool {
        guard Set(result.contexts.map(\.hour)) == [.matins] else {
            return false
        }
        if result.kind == .reading {
            return true
        }
        let title = normalized(result.titleLatin)
        if result.kind == .blessing, title.contains("lectio") {
            return true
        }
        guard result.kind == .prayer, title == "pater" else {
            return false
        }
        let latin = normalized(result.latin)
        return !latin.hasPrefix("pater noster")
            && !latin.hasPrefix("confiteor deo")
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "la")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SearchChantView: View {
    let score: ChantScore
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.dismiss) private var dismiss
    @State private var preparation: GregorianScorePreparation?
    @State private var showsCantorGuide = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if let preparation {
                    GregorianScoreView(
                        score: score,
                        preparation: preparation,
                        highlightedEventID: showsCantorGuide
                            ? playback.currentEventID
                            : nil,
                        onTapEvent: { eventID in
                            showsCantorGuide = true
                            playback.play(
                                score: score,
                                fromEventID: eventID
                            )
                        },
                        onActiveNeumeFrameChange: { _ in }
                    )
                    .padding(.horizontal, 16)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .safeAreaPadding(.bottom, showsCantorGuide ? 150 : 0)
            .overlay(alignment: .bottom) {
                if showsCantorGuide {
                    PlaybackControlsView(
                        score: score,
                        onClose: closeCantorGuide
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsCantorGuide)
            .task(id: Int(proxy.size.width.rounded())) {
                preparation = await GregorianScorePreparer.prepare(
                    scores: [score],
                    width: max(280, proxy.size.width - 32),
                    metrics: GregorianLayoutMetrics()
                )[score.id]
            }
        }
        .navigationTitle(score.incipit)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(
            tour.isActive && tour.currentLayer == .search
        )
        .toolbar {
            if tour.isActive, tour.currentLayer == .search {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        returnFromChant()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .frame(minWidth: 60, minHeight: 44)
                            .contentShape(Rectangle())
                            .appTourTarget(.searchChantBack)
                    }
                    .accessibilityIdentifier("tour-search-chant-back")
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            returnFromChant()
                        }
                    )
                }
            }
        }
        .onAppear {
            tour.receive(.searchChantOpened(score.id))
        }
        .onDisappear {
            if showsCantorGuide {
                playback.stop()
            }
        }
    }

    private func closeCantorGuide() {
        playback.stop()
        showsCantorGuide = false
    }

    private func returnFromChant() {
        guard tour.step == .returnFromFirstChant
                || tour.step == .returnFromSecondChant else {
            return
        }
        tour.receive(.searchChantClosed(score.id))
        dismiss()
    }
}
