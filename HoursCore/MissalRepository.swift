import Foundation
import SQLite3

/// One of the Masses a day has: Christmas and All Souls have three, Maundy
/// Thursday under the 1960 rubrics the Chrism Mass and the Mass of the
/// Lord's Supper; every other day one.
public struct MassListing: Hashable, Sendable, Identifiable {
    /// The Mass's place among the day's Masses, from zero.
    public let index: Int
    public let titleLatin: String
    public let titleEnglish: String?
    /// The name that tells the day's Masses apart ("Ad Missam in nocte").
    public let label: String?
    public let labelEnglish: String?

    public var id: Int { index }

    public init(
        index: Int,
        titleLatin: String,
        titleEnglish: String? = nil,
        label: String? = nil,
        labelEnglish: String? = nil
    ) {
        self.index = index
        self.titleLatin = titleLatin
        self.titleEnglish = titleEnglish
        self.label = label
        self.labelEnglish = labelEnglish
    }
}

/// A Mass found by its title, or one that says a part of the Mass that
/// search found, at its next occurrence, which the Mass reader opens.
public struct MassUsageContext: Codable, Hashable, Sendable {
    public let firstDate: LocalDay
    public let lastDate: LocalDay
    /// Its place among the Masses of its first day, from zero.
    public let index: Int
    public let titleLatin: String
    public let titleEnglish: String?
    /// The name that tells a day's Masses apart ("Ad Missam in nocte").
    public let label: String?
    public let labelEnglish: String?
    public let occurrenceCount: Int
    /// For a part of the Ordinary, the settings this Mass sings it to
    /// ("Kyrie XI"); empty otherwise.
    public let settings: [String]

    public init(
        firstDate: LocalDay,
        lastDate: LocalDay,
        index: Int,
        titleLatin: String,
        titleEnglish: String? = nil,
        label: String? = nil,
        labelEnglish: String? = nil,
        occurrenceCount: Int = 1,
        settings: [String] = []
    ) {
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.index = index
        self.titleLatin = titleLatin
        self.titleEnglish = titleEnglish
        self.label = label
        self.labelEnglish = labelEnglish
        self.occurrenceCount = occurrenceCount
        self.settings = settings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstDate = try container.decode(LocalDay.self, forKey: .firstDate)
        lastDate = try container.decode(LocalDay.self, forKey: .lastDate)
        index = try container.decode(Int.self, forKey: .index)
        titleLatin = try container.decode(String.self, forKey: .titleLatin)
        titleEnglish = try container.decodeIfPresent(String.self, forKey: .titleEnglish)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        labelEnglish = try container.decodeIfPresent(String.self, forKey: .labelEnglish)
        occurrenceCount = try container.decode(Int.self, forKey: .occurrenceCount)
        settings = try container.decodeIfPresent([String].self, forKey: .settings) ?? []
    }
}

/// What a search of titles finds: an Office at one of its Hours, or a Mass.
public enum LiturgicalTitleResult: Hashable, Sendable {
    case office(LiturgicalUsageContext)
    case mass(MassUsageContext)

    /// The Hour whose Office names the day a Mass is said on: the Mass of
    /// the day is sung after Terce.
    public static let massDayHour = OfficeHour.terce

    /// The Offices in the order found, which is the order of the Hours,
    /// with the Masses set after Terce, as the Mass of the day is sung.
    public static func merged(
        offices: [LiturgicalUsageContext],
        masses: [MassUsageContext]
    ) -> [LiturgicalTitleResult] {
        let hours = OfficeHour.allCases
        let after = hours.firstIndex(of: massDayHour) ?? hours.endIndex
        let split = offices.firstIndex {
            (hours.firstIndex(of: $0.hour) ?? hours.endIndex) > after
        } ?? offices.endIndex
        return offices[..<split].map(Self.office)
            + masses.map(Self.mass)
            + offices[split...].map(Self.office)
    }
}

/// The Mass of each day of an edition.
public protocol MissalProvider: Sendable {
    var tradition: OfficeTradition { get }
    /// The Masses of a day, in the Missal's order; empty for a day the
    /// edition does not serve.
    func masses(on day: LocalDay) async throws -> [MassListing]
    /// A Mass of a day, as the reader shows it.
    func mass(on day: LocalDay, index: Int) async throws -> OfficeDocument
    /// Each Mass whose title the query matches, or that is said on one of
    /// `officeDays` (the days whose Office the query matches), once, at its
    /// first occurrence in the range.
    func searchMassTitles(
        query: String,
        language: LiturgicalSearchLanguage,
        usageRange: ClosedRange<LocalDay>?,
        officeDays: Set<LocalDay>,
        limit: Int
    ) async throws -> [MassUsageContext]
    /// The parts of the Mass, ordinary and proper, whose words hold the
    /// query's, as the Office's search finds its texts.
    func searchMassParts(
        query: String,
        language: LiturgicalSearchLanguage,
        filter: MassPartFilter,
        limit: Int
    ) async throws -> [LiturgicalSearchHit]
    /// A part of the Mass that search found: its words, the settings it is
    /// sung to, and the Masses within the range that say it.
    func massPartDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult
    /// Reads what a search of the Mass's parts reads, ahead of the first.
    func prepareMassPartSearch() async throws
}

public extension MissalProvider {
    func searchMassTitles(
        query: String,
        language: LiturgicalSearchLanguage,
        usageRange: ClosedRange<LocalDay>?,
        officeDays: Set<LocalDay>,
        limit: Int
    ) async throws -> [MassUsageContext] {
        []
    }

    func searchMassParts(
        query: String,
        language: LiturgicalSearchLanguage,
        filter: MassPartFilter,
        limit: Int
    ) async throws -> [LiturgicalSearchHit] {
        []
    }

    func massPartDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult {
        throw ContentRepositoryError.invalidContent("Search resource \(id) is missing.")
    }

    func prepareMassPartSearch() async throws {}
}

/// The Missal database of an edition: each stored day's Masses, each Mass
/// kept once, with its texts and chants.
public actor SQLiteMissalRepository: MissalProvider {
    /// The schema this reader knows.
    public static let schema = 1

    public nonisolated let tradition: OfficeTradition
    private let connection: SQLiteConnection
    private let decoder = JSONDecoder.hoursContentDecoder
    private let yearPlan: PerennialYearPlan?
    private var headerCache: [Int: StoredMass] = [:]
    /// The titles of each Mass a search has read; there are a few thousand.
    private var titleCache: [Int: StoredMassTitles] = [:]
    /// The settings of the Ordinary that search offers beside the Missal's.
    private let kyriale: KyrialeCatalog?
    /// Every part of the Mass, as search finds them: read on the first
    /// search, and kept.
    private var partIndex: MassPartIndex?

    /// - Parameter kyriale: the Kyriale's settings of the Ordinary, which
    ///   a search of its parts offers; without it, the settings the Missal
    ///   sings alone.
    public init(
        databaseURL: URL,
        expectedTradition: OfficeTradition? = nil,
        kyriale: KyrialeCatalog? = nil
    ) throws {
        self.kyriale = kyriale
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:))
                ?? "SQLite returned \(result)."
            if let database { sqlite3_close(database) }
            throw ContentRepositoryError.databaseUnavailable(message)
        }
        connection = SQLiteConnection(pointer: database)
        let manifest = try Self.manifest(of: database, decoder: decoder)
        guard manifest.schema == Self.schema else {
            throw ContentRepositoryError.invalidContent("The Missal has schema \(manifest.schema); this app reads \(Self.schema).")
        }
        guard let tradition = OfficeTradition(rubrics: manifest.rubrics),
              expectedTradition == nil || expectedTradition == tradition else {
            throw ContentRepositoryError.invalidContent("The Missal has incorrect rubrics.")
        }
        self.tradition = tradition
        if let storedYears = manifest.coverage.storedYears {
            yearPlan = try PerennialYearPlan(
                servedYears: manifest.coverage.startYear...manifest.coverage.endYear,
                storedYears: storedYears
            )
        } else {
            yearPlan = nil
        }
    }

    public func masses(on day: LocalDay) throws -> [MassListing] {
        try storedMasses(on: day).enumerated().map { index, mass in
            MassListing(
                index: index,
                titleLatin: mass.titleLatin,
                titleEnglish: mass.titleEnglish,
                label: mass.label,
                labelEnglish: mass.labelEnglish
            )
        }
    }

    public func mass(on day: LocalDay, index: Int) throws -> OfficeDocument {
        let masses = try storedMasses(on: day)
        guard masses.indices.contains(index) else {
            throw ContentRepositoryError.contentUnavailable(day, nil)
        }
        return try document(of: masses[index], index: index, on: day)
    }

    public func searchMassTitles(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        usageRange: ClosedRange<LocalDay>?,
        officeDays: Set<LocalDay> = [],
        limit: Int = 50
    ) async throws -> [MassUsageContext] {
        guard query.contains(where: { $0.isLetter || $0.isNumber }) else {
            return []
        }
        try Task.checkCancellation()
        let days = try servedDays(in: usageRange)
        try loadTitles(of: days.flatMap(\.ids))
        var titleMatches: [Int: Bool] = [:]
        var grouped: [MassTitleKey: MassUsageContext] = [:]
        for (date, ids) in days {
            let isOfficeDay = officeDays.contains(date)
            for (index, id) in ids.enumerated() {
                let titles = try storedTitles(id)
                let matched: Bool
                if let known = titleMatches[id] {
                    matched = known
                } else {
                    matched = SQLiteContentRepository.matchesOfficeTitle(
                        latin: titles.titleLatin,
                        english: titles.titleEnglish,
                        query: query,
                        language: language
                    )
                    titleMatches[id] = matched
                }
                guard matched || isOfficeDay else { continue }
                let key = MassTitleKey(
                    title: ObservanceTitle.latin(titles.titleLatin),
                    label: titles.label ?? ""
                )
                guard let existing = grouped[key] else {
                    grouped[key] = MassUsageContext(
                        firstDate: date,
                        lastDate: date,
                        index: index,
                        titleLatin: titles.titleLatin,
                        titleEnglish: titles.titleEnglish,
                        label: titles.label,
                        labelEnglish: titles.labelEnglish
                    )
                    continue
                }
                // The Mass is named as its first occurrence is, which is
                // the one opened.
                let first = date < existing.firstDate
                grouped[key] = MassUsageContext(
                    firstDate: first ? date : existing.firstDate,
                    lastDate: max(existing.lastDate, date),
                    index: first ? index : existing.index,
                    titleLatin: first ? titles.titleLatin : existing.titleLatin,
                    titleEnglish: first ? titles.titleEnglish : existing.titleEnglish,
                    label: first ? titles.label : existing.label,
                    labelEnglish: first ? titles.labelEnglish : existing.labelEnglish,
                    occurrenceCount: existing.occurrenceCount + 1
                )
            }
        }
        // By the day found, then the Missal's order.
        let sorted = grouped.values.sorted { left, right in
            if left.firstDate != right.firstDate { return left.firstDate < right.firstDate }
            if left.index != right.index { return left.index < right.index }
            return left.titleLatin.localizedStandardCompare(right.titleLatin) == .orderedAscending
        }
        return Array(sorted.prefix(max(1, min(limit, 50))))
    }

    public func searchMassParts(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        filter: MassPartFilter = .everyPart,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        guard query.contains(where: { $0.isLetter || $0.isNumber }) else {
            return []
        }
        try Task.checkCancellation()
        return try loadedPartIndex().search(
            query: query,
            language: language,
            filter: filter,
            limit: limit
        )
    }

    public func prepareMassPartSearch() async throws {
        _ = try loadedPartIndex()
    }

    public func massPartDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult {
        try Task.checkCancellation()
        let index = try loadedPartIndex()
        guard let entry = index.entry(id) else {
            throw ContentRepositoryError.invalidContent("Search resource \(id) is missing.")
        }
        let stored = try payloads(in: "scores", ids: Set(entry.scoreIDs))
        var missalScores: [Int: ChantScore] = [:]
        for (scoreID, payload) in stored {
            missalScores[scoreID] = try decoder.decode(ChantScore.self, from: payload)
        }
        var scores: [ChantScore]
        var notes: [String: String] = [:]
        // The name of each setting a Mass sings a part of the Ordinary to.
        var settingNames: [Int: String] = [:]
        if let part = entry.part, let kyriale {
            let settings = try kyriale.settings(of: part)
            var byChant: [String: ChantScore] = [:]
            for setting in settings {
                if let note = setting.note { notes[setting.score.id] = note }
                if let url = setting.score.provenance.sourceURL?.absoluteString {
                    byChant[url] = setting.score
                }
            }
            scores = settings.map(\.score)
            // A chant the Missal sings that the Kyriale does not give is
            // offered after the book's own.
            for scoreID in entry.scoreIDs {
                guard let score = missalScores[scoreID] else { continue }
                if let url = score.provenance.sourceURL?.absoluteString, let named = byChant[url] {
                    settingNames[scoreID] = named.incipit
                } else {
                    settingNames[scoreID] = score.incipit
                    scores.append(score)
                }
            }
        } else {
            scores = entry.scoreIDs.compactMap { missalScores[$0] }
            if entry.part != nil {
                for (scoreID, score) in missalScores { settingNames[scoreID] = score.incipit }
            }
        }
        try Task.checkCancellation()
        return LiturgicalSearchResult(
            id: entry.id,
            kind: entry.kind,
            titleLatin: entry.title,
            titleEnglish: entry.titleEnglish,
            rubricLatin: entry.rubric,
            rubricEnglish: entry.rubricEnglish,
            latin: entry.latin,
            english: entry.english,
            scoredRealizations: scores,
            massContexts: try massContexts(of: entry, in: index, usageRange: usageRange, settingNames: settingNames),
            settingNotes: notes
        )
    }

    /// The Masses within the range that say a part, each once, at its first
    /// occurrence, in the order of the days; for a part of the Ordinary,
    /// with the settings each sings it to.
    private func massContexts(
        of entry: MassPartEntry,
        in index: MassPartIndex,
        usageRange: ClosedRange<LocalDay>?,
        settingNames: [Int: String]
    ) throws -> [MassUsageContext] {
        var scoresByMass: [Int: Set<Int>] = [:]
        for text in entry.textIDs {
            for use in index.uses[text] ?? [] {
                scoresByMass[use.mass, default: []].formUnion(use.score.map { [$0] } ?? [])
            }
        }
        guard !scoresByMass.isEmpty else { return [] }
        let days = try servedDays(in: usageRange)
        try loadTitles(of: days.flatMap(\.ids).filter { scoresByMass[$0] != nil })
        var grouped: [MassTitleKey: MassUsageContext] = [:]
        for (date, ids) in days {
            for (position, id) in ids.enumerated() {
                guard let used = scoresByMass[id] else { continue }
                let titles = try storedTitles(id)
                let settings = Set(used.compactMap { settingNames[$0] })
                let key = MassTitleKey(
                    title: ObservanceTitle.latin(titles.titleLatin),
                    label: titles.label ?? ""
                )
                guard let existing = grouped[key] else {
                    grouped[key] = MassUsageContext(
                        firstDate: date,
                        lastDate: date,
                        index: position,
                        titleLatin: titles.titleLatin,
                        titleEnglish: titles.titleEnglish,
                        label: titles.label,
                        labelEnglish: titles.labelEnglish,
                        settings: settings.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    )
                    continue
                }
                // The Mass is named as its first occurrence is, which is
                // the one opened.
                let first = date < existing.firstDate
                grouped[key] = MassUsageContext(
                    firstDate: first ? date : existing.firstDate,
                    lastDate: max(existing.lastDate, date),
                    index: first ? position : existing.index,
                    titleLatin: first ? titles.titleLatin : existing.titleLatin,
                    titleEnglish: first ? titles.titleEnglish : existing.titleEnglish,
                    label: first ? titles.label : existing.label,
                    labelEnglish: first ? titles.labelEnglish : existing.labelEnglish,
                    occurrenceCount: existing.occurrenceCount + 1,
                    settings: Set(existing.settings).union(settings)
                        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                )
            }
        }
        return grouped.values.sorted { left, right in
            if left.firstDate != right.firstDate { return left.firstDate < right.firstDate }
            if left.index != right.index { return left.index < right.index }
            return left.titleLatin.localizedStandardCompare(right.titleLatin) == .orderedAscending
        }
    }

    /// Every part of the Mass, read from the Missal's texts and Masses on
    /// the first search.
    private func loadedPartIndex() throws -> MassPartIndex {
        if let partIndex { return partIndex }
        let database = connection.pointer
        func rows(_ table: String) throws -> [(id: Int, payload: Data)] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT id, payload FROM \(table) ORDER BY id", -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            var result: [(id: Int, payload: Data)] = []
            while true {
                try Task.checkCancellation()
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { return result }
                guard step == SQLITE_ROW else {
                    throw ContentRepositoryError.databaseUnavailable(
                        "Reading \(table): \(String(cString: sqlite3_errmsg(database))) (\(step))"
                    )
                }
                guard let bytes = sqlite3_column_blob(statement, 1) else {
                    throw ContentRepositoryError.invalidContent("A row of \(table) has no payload.")
                }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
                result.append((Int(sqlite3_column_int64(statement, 0)), try ContentPayloadCodec.decode(data)))
            }
        }
        // Read as objects rather than decoded: some thousands of each are
        // read before the first search answers.
        func object(_ payload: Data, _ table: String) throws -> [String: Any] {
            guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw ContentRepositoryError.invalidContent("A row of \(table) is not an object.")
            }
            return object
        }
        let texts = try rows("texts").map { row in
            let text = try object(row.payload, "texts")
            guard let kindValue = text["kind"] as? String,
                  let kind = OfficeSectionKind(rawValue: kindValue),
                  let title = text["title"] as? String,
                  let latin = text["latin"] as? String else {
                throw ContentRepositoryError.invalidContent("A text of the Missal is malformed.")
            }
            return MissalSearchText(
                id: row.id,
                kind: kind,
                title: title,
                titleEnglish: text["titleEnglish"] as? String,
                rubric: text["rubric"] as? String,
                rubricEnglish: text["rubricEnglish"] as? String,
                latin: latin,
                english: text["english"] as? String,
                ordinary: text["ordinary"] as? Bool ?? false
            )
        }
        var sections: [Int: [(text: Int, score: Int?)]] = [:]
        for row in try rows("masses") {
            guard let references = try object(row.payload, "masses")["sections"] as? [[Int]],
                  references.allSatisfy({ $0.count == 2 }) else {
                throw ContentRepositoryError.invalidContent("A Mass of the Missal is malformed.")
            }
            sections[row.id] = references.map { ($0[0], $0[1] == 0 ? nil : $0[1]) }
        }
        let index = MassPartIndex(
            texts: texts,
            sections: sections,
            kyrialeParts: kyriale?.parts ?? []
        )
        partIndex = index
        return index
    }

    /// The stored ranges that hold a range of served days. A Missal that
    /// stores what it serves has the range itself. A perennial Missal has
    /// one range for each civil year touched; searched whole, it has each
    /// stored year, dated as the first year it serves.
    private func segments(
        for usageRange: ClosedRange<LocalDay>?
    ) -> [(stored: ClosedRange<LocalDay>?, servedYear: Int?)] {
        guard let yearPlan else { return [(usageRange, nil)] }
        if let usageRange {
            return yearPlan.storedRanges(for: usageRange).map { ($0.stored, $0.servedYear) }
        }
        return yearPlan.storedYears.compactMap { stored -> (stored: ClosedRange<LocalDay>?, servedYear: Int?)? in
            guard let served = yearPlan.firstServedYear(storedAs: stored) else { return nil }
            return (
                LocalDay(year: stored, month: 1, day: 1)...LocalDay(year: stored, month: 12, day: 31),
                served
            )
        }.sorted { ($0.servedYear ?? 0) < ($1.servedYear ?? 0) }
    }

    /// The days of a range of served days, each with its Masses in the
    /// Missal's order, dated as they are served: every stored day read once.
    private func servedDays(
        in usageRange: ClosedRange<LocalDay>?
    ) throws -> [(date: LocalDay, ids: [Int])] {
        let database = connection.pointer
        var days: [(date: LocalDay, ids: [Int])] = []
        for segment in segments(for: usageRange) {
            let sql = segment.stored == nil
                ? "SELECT date, masses FROM days ORDER BY date"
                : "SELECT date, masses FROM days WHERE date BETWEEN ? AND ? ORDER BY date"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            if let stored = segment.stored {
                sqlite3_bind_text(statement, 1, stored.lowerBound.description, -1, sqliteTransient)
                sqlite3_bind_text(statement, 2, stored.upperBound.description, -1, sqliteTransient)
            }
            while true {
                try Task.checkCancellation()
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW,
                      let dateValue = sqlite3_column_text(statement, 0),
                      let list = sqlite3_column_text(statement, 1),
                      let stored = LocalDay(iso8601: String(cString: dateValue)) else {
                    throw ContentRepositoryError.invalidContent("A day of the Missal is malformed.")
                }
                let ids = try decoder.decode([Int].self, from: Data(String(cString: list).utf8))
                let date = segment.servedYear.map {
                    LocalDay(year: $0, month: stored.month, day: stored.day)
                } ?? stored
                days.append((date, ids))
            }
        }
        return days
    }

    /// Reads at once the titles of the Masses not read before, so that a
    /// search asks the database once, not once for each Mass.
    private func loadTitles(of ids: [Int]) throws {
        let unread = Set(ids).subtracting(titleCache.keys)
        guard !unread.isEmpty else { return }
        for (id, payload) in try payloads(in: "masses", ids: unread) {
            titleCache[id] = try decoder.decode(StoredMassTitles.self, from: payload)
        }
    }

    private func storedTitles(_ id: Int) throws -> StoredMassTitles {
        if let cached = titleCache[id] { return cached }
        guard let payload = try payloads(in: "masses", ids: [id])[id] else {
            throw ContentRepositoryError.invalidContent("The Missal has no Mass \(id).")
        }
        let titles = try decoder.decode(StoredMassTitles.self, from: payload)
        titleCache[id] = titles
        return titles
    }

    /// Reads every Mass of every stored day as the reader reads it, checking
    /// each against its digest, and gives each distinct chant once to
    /// `score`: for the notation validator.
    public func validateEveryMass(
        _ score: @Sendable (ChantScore) throws -> Void
    ) throws -> (days: Int, masses: Int, scores: Int, failures: [String]) {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT date, masses FROM days ORDER BY date", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var days = 0
        var masses = 0
        var validated: Set<Int> = []
        var scored: Set<String> = []
        var failures: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW,
                  let date = sqlite3_column_text(statement, 0),
                  let list = sqlite3_column_text(statement, 1),
                  let day = LocalDay(iso8601: String(cString: date)) else {
                throw ContentRepositoryError.invalidContent("A day of the Missal is malformed.")
            }
            days += 1
            let ids = try decoder.decode([Int].self, from: Data(String(cString: list).utf8))
            guard !ids.isEmpty else {
                throw ContentRepositoryError.invalidContent("\(day) has no Mass.")
            }
            for (index, id) in ids.enumerated() {
                masses += 1
                guard validated.insert(id).inserted else { continue }
                let document = try document(of: storedMass(id), index: index, on: day)
                for chant in document.sections.compactMap(\.chant) where scored.insert(chant.id).inserted {
                    do {
                        try score(chant)
                    } catch {
                        failures.append("\(chant.id) (\(day), \(chant.provenance.sourceURL?.absoluteString ?? chant.provenance.sourceBook)): \(error.localizedDescription)")
                    }
                }
            }
        }
        return (days, masses, scored.count, failures)
    }

    private func document(of mass: StoredMass, index: Int, on day: LocalDay) throws -> OfficeDocument {
        let texts = try payloads(in: "texts", ids: Set(mass.sections.map(\.text)))
        let scores = try payloads(in: "scores", ids: Set(mass.sections.compactMap(\.score)))
        var sections: [OfficeSection] = []
        sections.reserveCapacity(mass.sections.count)
        for (position, reference) in mass.sections.enumerated() {
            guard let textPayload = texts[reference.text] else {
                throw ContentRepositoryError.invalidContent("A section of the Mass of \(day) has no text.")
            }
            let text = try decoder.decode(StoredMissalText.self, from: textPayload)
            var chant: ChantScore?
            if let scoreID = reference.score {
                guard let scorePayload = scores[scoreID] else {
                    throw ContentRepositoryError.invalidContent("A chant of the Mass of \(day) is missing.")
                }
                chant = try decoder.decode(ChantScore.self, from: scorePayload)
            }
            sections.append(OfficeSection(
                id: "\(day)-missa\(index + 1)-section-\(position)",
                kind: text.kind,
                title: text.title,
                titleEnglish: text.titleEnglish,
                rubric: text.rubric,
                rubricEnglish: text.rubricEnglish,
                latin: text.latin,
                english: text.english,
                chant: chant,
                ordinary: text.ordinary
            ))
        }
        let document = OfficeDocument(
            id: "missa:\(tradition.rawValue):\(day):\(index + 1)",
            date: day,
            // A document is of an Hour: the Mass of the day is sung after
            // Terce. Nothing names it for Terce or lights it by Terce (see
            // englishName, and the reader's skyHour).
            hour: .terce,
            titleLatin: "Sancta Missa",
            titleEnglish: "Holy Mass",
            contextLabel: mass.label ?? "Missa",
            sourceVersion: mass.sourceVersion,
            format: .missal,
            visibleContentDigest: mass.visibleContentDigest,
            observance: OfficeObservance(
                observanceID: "missa:\(mass.titleLatin)",
                titleLatin: mass.titleLatin,
                titleEnglish: mass.titleEnglish,
                rank: mass.rank,
                sourceRank: mass.sourceRank,
                color: mass.color
            ),
            sections: sections
        )
        try VisibleContentDigest.validate(document)
        return document
    }

    /// The Masses stored for the day a served day is read from.
    private func storedMasses(on day: LocalDay) throws -> [StoredMass] {
        let stored: LocalDay
        if let yearPlan {
            guard let day = yearPlan.storedDay(for: day) else { return [] }
            stored = day
        } else {
            stored = day
        }
        guard let ids = try massIDs(on: stored) else { return [] }
        return try ids.map(storedMass)
    }

    private func massIDs(on day: LocalDay) throws -> [Int]? {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT masses FROM days WHERE date = ?", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let date = "\(day)"
        sqlite3_bind_text(statement, 1, date, -1, sqliteTransient)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else { return [] }
            return try decoder.decode([Int].self, from: Data(String(cString: text).utf8))
        case SQLITE_DONE:
            return nil
        default:
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func storedMass(_ id: Int) throws -> StoredMass {
        if let cached = headerCache[id] { return cached }
        guard let payload = try payloads(in: "masses", ids: [id])[id] else {
            throw ContentRepositoryError.invalidContent("The Missal has no Mass \(id).")
        }
        let mass = try decoder.decode(StoredMass.self, from: payload)
        if headerCache.count > 256 { headerCache.removeAll(keepingCapacity: true) }
        headerCache[id] = mass
        return mass
    }

    /// The decoded payloads of rows of a table, by their ids.
    private func payloads(in table: String, ids: Set<Int>) throws -> [Int: Data] {
        guard !ids.isEmpty else { return [:] }
        let database = connection.pointer
        let sorted = ids.sorted()
        var result: [Int: Data] = [:]
        // SQLite binds at most 32,766 values to one statement.
        for start in stride(from: 0, to: sorted.count, by: 500) {
            let batch = sorted[start..<min(start + 500, sorted.count)]
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT id, payload FROM \(table) WHERE id IN (\(placeholders))",
                -1,
                &statement,
                nil
            ) == SQLITE_OK, let statement else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            for (offset, id) in batch.enumerated() {
                sqlite3_bind_int64(statement, Int32(offset + 1), Int64(id))
            }
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else {
                    throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
                }
                let id = Int(sqlite3_column_int64(statement, 0))
                guard let bytes = sqlite3_column_blob(statement, 1) else {
                    throw ContentRepositoryError.invalidContent("A row of \(table) has no payload.")
                }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
                result[id] = try ContentPayloadCodec.decode(data)
            }
        }
        return result
    }

    private static func manifest(of database: OpaquePointer, decoder: JSONDecoder) throws -> MissalManifest {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM meta WHERE key = 'manifest'", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw ContentRepositoryError.invalidContent("The Missal has no manifest.")
        }
        return try decoder.decode(MissalManifest.self, from: Data(String(cString: text).utf8))
    }
}

public extension OfficeTradition {
    /// The name of the edition's bundled Missal.
    var missalResourceName: String {
        switch self {
        case .roman1954: "roman-1954-missal"
        case .roman1960: "roman-1960-missal"
        }
    }

    /// The Missal of the edition: under the 1960 rubrics the Missal of 1962,
    /// under the 1954 rubrics the Missal as it stood before the reforms of
    /// 1955.
    var missalTitle: String {
        switch self {
        case .roman1954: "Roman Missal 1954"
        case .roman1960: "Roman Missal 1962"
        }
    }

    func missalURL(in bundle: Bundle = .main) throws -> URL {
        for subdirectory in ["Resources/Missal", "Missal", "Resources", nil] as [String?] {
            if let url = bundle.url(forResource: missalResourceName, withExtension: "sqlite", subdirectory: subdirectory) {
                return url
            }
        }
        throw ContentRepositoryError.databaseUnavailable("The bundled \(missalTitle) is missing.")
    }
}

private struct MissalManifest: Decodable {
    struct Coverage: Decodable {
        let startDate: String
        let endDate: String
        let storedYears: [Int]?

        var startYear: Int { Int(startDate.prefix(4)) ?? 0 }
        var endYear: Int { Int(endDate.prefix(4)) ?? 0 }
    }

    let schema: Int
    let rubrics: String
    let coverage: Coverage
}

/// A Mass as the Missal database keeps it: its header, and each section as
/// the text and the chant it is made of.
private struct StoredMass: Decodable {
    struct Reference: Decodable {
        let text: Int
        let score: Int?

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            text = try container.decode(Int.self)
            let score = try container.decode(Int.self)
            self.score = score == 0 ? nil : score
        }
    }

    let titleLatin: String
    let titleEnglish: String?
    let label: String?
    let labelEnglish: String?
    let rank: LiturgicalRank?
    let sourceRank: String?
    let color: LiturgicalColor?
    let kyriale: String?
    let sourceVersion: String
    let visibleContentDigest: String
    let sections: [Reference]
}

/// What the search of titles reads of a Mass.
private struct StoredMassTitles: Decodable {
    let titleLatin: String
    let titleEnglish: String?
    let label: String?
    let labelEnglish: String?
}

/// A Mass as a search of titles groups it: by its title and its name among
/// the day's Masses.
private struct MassTitleKey: Hashable {
    let title: String
    let label: String
}

private struct StoredMissalText: Decodable {
    let kind: OfficeSectionKind
    let title: String
    let titleEnglish: String?
    let rubric: String?
    let rubricEnglish: String?
    let latin: String
    let english: String?
    let ordinary: Bool?
}
