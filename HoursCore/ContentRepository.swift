import Foundation
import OSLog
import SQLite3

public enum ContentRepositoryError: LocalizedError, Equatable {
    case databaseUnavailable(String)
    case contentUnavailable(LocalDay, OfficeHour?)
    case invalidContent(String)
    case dateOutOfCoverage(LocalDay, ClosedRange<LocalDay>)

    public var errorDescription: String? {
        switch self {
        case .databaseUnavailable(let detail):
            "The office corpus could not be opened. \(detail)"
        case .contentUnavailable(let day, let hour):
            if let hour {
                "\(hour.englishTitle) is not available for \(day)."
            } else {
                "Liturgical content is not available for \(day)."
            }
        case .invalidContent(let detail):
            "The office corpus is invalid. \(detail)"
        case .dateOutOfCoverage(let day, let coverage):
            "\(day) is outside this corpus’s supported range, \(coverage.lowerBound) through \(coverage.upperBound)."
        }
    }
}

public enum LiturgicalDayDirection: Equatable, Sendable {
    case previous
    case next
}

public protocol LiturgicalOrdoProvider: Sendable {
    func coverageRange() async throws -> ClosedRange<LocalDay>
    func day(on date: LocalDay) async throws -> LiturgicalDay
    func days(in range: ClosedRange<LocalDay>) async throws -> [LiturgicalDay]
    func adjacentDay(to date: LocalDay, direction: LiturgicalDayDirection) async throws -> LiturgicalDay
    func office(on date: LocalDay, hour: OfficeHour) async throws -> OfficeDocument
}

public protocol ContentRepository: LiturgicalOrdoProvider {
    func availableDays() async throws -> [LiturgicalDay]
    func searchOfficeTitles(
        query: String,
        language: LiturgicalSearchLanguage,
        hour: OfficeHour?,
        usageRange: ClosedRange<LocalDay>?,
        limit: Int
    ) async throws -> [LiturgicalUsageContext]
    func searchHits(
        query: String,
        language: LiturgicalSearchLanguage,
        kind: OfficeSectionKind?,
        limit: Int
    ) async throws -> [LiturgicalSearchHit]
    func searchHits(
        query: String,
        language: LiturgicalSearchLanguage,
        kind: OfficeSectionKind?,
        hour: OfficeHour?,
        requiresScore: Bool,
        limit: Int
    ) async throws -> [LiturgicalSearchHit]
    func searchDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult
    func search(
        query: String,
        language: LiturgicalSearchLanguage,
        kind: OfficeSectionKind?,
        limit: Int
    ) async throws -> [LiturgicalSearchResult]
}

public extension ContentRepository {
    func searchOfficeTitles(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        hour: OfficeHour? = nil,
        usageRange: ClosedRange<LocalDay>? = nil,
        limit: Int = 50
    ) async throws -> [LiturgicalUsageContext] {
        []
    }

    func searchHits(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        []
    }

    func searchDetail(id: String) async throws -> LiturgicalSearchResult {
        try await searchDetail(id: id, usageRange: nil)
    }

    func searchDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult {
        throw ContentRepositoryError.invalidContent(
            "Search detail \(id) is unavailable from this repository."
        )
    }

    func searchHits(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        hour: OfficeHour?,
        requiresScore: Bool,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        try await searchHits(
            query: query,
            language: language,
            kind: kind,
            limit: limit
        ).filter { !requiresScore || $0.hasScoredRealizations }
    }

    func coverageRange() async throws -> ClosedRange<LocalDay> {
        let days = try await availableDays()
        guard let first = days.first?.date, let last = days.last?.date else {
            throw ContentRepositoryError.databaseUnavailable("The office corpus is empty.")
        }
        return first...last
    }

    func days(in range: ClosedRange<LocalDay>) async throws -> [LiturgicalDay] {
        try await availableDays().filter { range.contains($0.date) }
    }

    func adjacentDay(
        to date: LocalDay,
        direction: LiturgicalDayDirection
    ) async throws -> LiturgicalDay {
        let days = try await availableDays()
        let candidate = direction == .previous
            ? days.last(where: { $0.date < date })
            : days.first(where: { $0.date > date })
        guard let candidate else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return candidate
    }

    func search(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchResult] {
        let hits = try await searchHits(
            query: query,
            language: language,
            kind: kind,
            limit: limit
        )
        var results: [LiturgicalSearchResult] = []
        for hit in hits {
            try Task.checkCancellation()
            results.append(try await searchDetail(id: hit.id))
        }
        return results
    }
}

public actor InMemoryContentRepository: ContentRepository {
    private let days: [LocalDay: LiturgicalDay]
    private let offices: [OfficeKey: OfficeDocument]

    public init(days: [LiturgicalDay], offices: [OfficeDocument]) {
        self.days = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        self.offices = Dictionary(
            uniqueKeysWithValues: offices.map {
                (OfficeKey(date: $0.date, hour: $0.hour), $0)
            }
        )
    }

    public func availableDays() -> [LiturgicalDay] {
        days.values.sorted { $0.date < $1.date }
    }

    public func searchOfficeTitles(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        hour: OfficeHour? = nil,
        usageRange: ClosedRange<LocalDay>? = nil,
        limit: Int = 50
    ) -> [LiturgicalUsageContext] {
        guard query.contains(where: { $0.isLetter || $0.isNumber }) else {
            return []
        }
        let contexts = offices.values.compactMap { office -> LiturgicalUsageContext? in
            guard hour == nil || office.hour == hour,
                  usageRange?.contains(office.date) != false,
                  let observance = office.observance,
                  Self.matchesOfficeTitle(
                    latin: observance.titleLatin,
                    english: observance.titleEnglish,
                    query: query,
                    language: language
                  ) else {
                return nil
            }
            return LiturgicalUsageContext(
                observanceID: observance.observanceID,
                firstDate: office.date,
                lastDate: office.date,
                hour: office.hour,
                observanceTitleLatin: observance.titleLatin,
                observanceTitleEnglish: observance.titleEnglish
                    ?? days[office.date]?.titleEnglish,
                occurrenceCount: 1
            )
        }
        return Array(groupedUsageContexts(contexts).prefix(max(1, min(limit, 50))))
    }

    public func day(on date: LocalDay) throws -> LiturgicalDay {
        guard let day = days[date] else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return day
    }

    public func office(on date: LocalDay, hour: OfficeHour) throws -> OfficeDocument {
        guard let office = offices[OfficeKey(date: date, hour: hour)] else {
            throw ContentRepositoryError.contentUnavailable(date, hour)
        }
        return office
    }

    public func search(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        limit: Int = 50
    ) async -> [LiturgicalSearchResult] {
        let needle = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "la")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var resources: [String: LiturgicalSearchResult] = [:]
        for office in offices.values {
            for section in office.sections where kind == nil || section.kind == kind {
                let fields: [String]
                switch language {
                case .latin:
                    fields = [section.title, section.rubric, section.latin].compactMap { $0 }
                case .english:
                    fields = [section.titleEnglish, section.rubricEnglish, section.english].compactMap { $0 }
                case .all:
                    fields = [
                        section.title, section.titleEnglish, section.rubric,
                        section.rubricEnglish, section.latin, section.english
                    ].compactMap { $0 }
                }
                guard fields.contains(where: {
                    $0.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "la")
                    ).contains(needle)
                }) else { continue }
                let id = InMemoryContentRepository.searchResourceID(section)
                let context = LiturgicalUsageContext(
                    date: office.date,
                    hour: office.hour,
                    dayTitleLatin: days[office.date]?.titleLatin
                        ?? office.observance?.titleLatin
                        ?? office.contextLabel,
                    dayTitleEnglish: days[office.date]?.titleEnglish
                        ?? office.observance?.titleEnglish,
                    settingModes: [section.chant?.mode].compactMap { $0 }
                )
                if let existing = resources[id] {
                    resources[id] = LiturgicalSearchResult(
                        id: id,
                        kind: existing.kind,
                        titleLatin: existing.titleLatin,
                        titleEnglish: existing.titleEnglish,
                        rubricLatin: existing.rubricLatin,
                        rubricEnglish: existing.rubricEnglish,
                        latin: existing.latin,
                        english: existing.english,
                        scoredRealizations: Array(
                            Set(existing.scoredRealizations + [section.chant].compactMap { $0 })
                        ),
                        contexts: existing.contexts + [context]
                    )
                } else {
                    resources[id] = LiturgicalSearchResult(
                        id: id,
                        kind: section.kind,
                        titleLatin: section.title,
                        titleEnglish: section.titleEnglish,
                        rubricLatin: section.rubric,
                        rubricEnglish: section.rubricEnglish,
                        latin: section.latin,
                        english: section.english,
                        scoredRealizations: [section.chant].compactMap { $0 },
                        contexts: [context]
                    )
                }
            }
        }
        return Array(
            resources.values.map { result in
                LiturgicalSearchResult(
                    id: result.id,
                    kind: result.kind,
                    titleLatin: result.titleLatin,
                    titleEnglish: result.titleEnglish,
                    rubricLatin: result.rubricLatin,
                    rubricEnglish: result.rubricEnglish,
                    latin: result.latin,
                    english: result.english,
                    scoredRealizations: result.scoredRealizations,
                    contexts: groupedUsageContexts(result.contexts)
                )
            }.prefix(max(0, min(limit, 50)))
        )
    }

    public func searchHits(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        limit: Int = 50
    ) async -> [LiturgicalSearchHit] {
        let results = await search(query: query, language: language, kind: kind, limit: limit)
        return results.map { result in
            let usesEnglish = language == .english && result.english != nil
            return LiturgicalSearchHit(
                id: result.id,
                kind: result.kind,
                titleLatin: result.titleLatin,
                titleEnglish: result.titleEnglish,
                snippet: usesEnglish ? result.english! : result.latin,
                snippetLanguage: usesEnglish ? .english : .latin,
                hasScoredRealizations: !result.scoredRealizations.isEmpty
            )
        }
    }

    public func searchHits(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        hour: OfficeHour?,
        requiresScore: Bool,
        limit: Int = 50
    ) async -> [LiturgicalSearchHit] {
        let source: InMemoryContentRepository
        if let hour {
            source = InMemoryContentRepository(
                days: Array(days.values),
                offices: offices.values.filter { $0.hour == hour }
            )
        } else {
            source = self
        }
        let results = await source.search(
            query: query,
            language: language,
            kind: kind,
            limit: limit
        )
        return results.lazy
            .filter { !requiresScore || !$0.scoredRealizations.isEmpty }
            .prefix(limit)
            .map { result in
                let usesEnglish = language == .english && result.english != nil
                return LiturgicalSearchHit(
                    id: result.id,
                    kind: result.kind,
                    titleLatin: result.titleLatin,
                    titleEnglish: result.titleEnglish,
                    snippet: usesEnglish ? result.english! : result.latin,
                    snippetLanguage: usesEnglish ? .english : .latin,
                    hasScoredRealizations: !result.scoredRealizations.isEmpty
                )
            }
    }

    public func searchDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult {
        var result: LiturgicalSearchResult?
        for office in offices.values {
            for section in office.sections where Self.searchResourceID(section) == id {
                let contexts: [LiturgicalUsageContext]
                if usageRange?.contains(office.date) != false {
                    contexts = [LiturgicalUsageContext(
                        date: office.date,
                        hour: office.hour,
                        dayTitleLatin: days[office.date]?.titleLatin
                            ?? office.observance?.titleLatin
                            ?? office.contextLabel,
                        dayTitleEnglish: days[office.date]?.titleEnglish
                            ?? office.observance?.titleEnglish,
                        settingModes: [section.chant?.mode].compactMap { $0 }
                    )]
                } else {
                    contexts = []
                }
                if let existing = result {
                    result = LiturgicalSearchResult(
                        id: id,
                        kind: existing.kind,
                        titleLatin: existing.titleLatin,
                        titleEnglish: existing.titleEnglish,
                        rubricLatin: existing.rubricLatin,
                        rubricEnglish: existing.rubricEnglish,
                        latin: existing.latin,
                        english: existing.english,
                        scoredRealizations: Array(Set(
                            existing.scoredRealizations + [section.chant].compactMap { $0 }
                        )),
                        contexts: existing.contexts + contexts
                    )
                } else {
                    result = LiturgicalSearchResult(
                        id: id,
                        kind: section.kind,
                        titleLatin: section.title,
                        titleEnglish: section.titleEnglish,
                        rubricLatin: section.rubric,
                        rubricEnglish: section.rubricEnglish,
                        latin: section.latin,
                        english: section.english,
                        scoredRealizations: [section.chant].compactMap { $0 },
                        contexts: contexts
                    )
                }
            }
        }
        guard let result else {
            throw ContentRepositoryError.invalidContent("Search resource \(id) is missing.")
        }
        return LiturgicalSearchResult(
            id: result.id,
            kind: result.kind,
            titleLatin: result.titleLatin,
            titleEnglish: result.titleEnglish,
            rubricLatin: result.rubricLatin,
            rubricEnglish: result.rubricEnglish,
            latin: result.latin,
            english: result.english,
            scoredRealizations: result.scoredRealizations,
            contexts: groupedUsageContexts(result.contexts)
        )
    }

    private static func searchResourceID(_ section: OfficeSection) -> String {
        [
            section.kind.rawValue, section.title, section.titleEnglish ?? "",
            section.rubric ?? "", section.rubricEnglish ?? "",
            section.latin, section.english ?? ""
        ].joined(separator: "\u{1f}")
    }

    private static func matchesOfficeTitle(
        latin: String,
        english: String?,
        query: String,
        language: LiturgicalSearchLanguage
    ) -> Bool {
        switch language {
        case .latin:
            matches([latin], query: query, latin: true)
        case .english:
            matches([english].compactMap { $0 }, query: query, latin: false)
        case .all:
            matches([latin], query: query, latin: true)
                || matches([english].compactMap { $0 }, query: query, latin: false)
        }
    }

    private static func searchNormalized(_ value: String, latin: Bool) -> String {
        var normalized = value
            .replacingOccurrences(of: "æ", with: "ae", options: .caseInsensitive)
            .replacingOccurrences(of: "œ", with: "oe", options: .caseInsensitive)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: latin ? "la" : "en")
            )
            .lowercased()
        if latin {
            normalized = normalized.replacingOccurrences(of: "j", with: "i")
        }
        return normalized
    }

    private static func matches(
        _ fields: [String],
        query: String,
        latin: Bool
    ) -> Bool {
        let haystack = searchNormalized(fields.joined(separator: " "), latin: latin)
        return query.split { !$0.isLetter && !$0.isNumber }.allSatisfy { token in
            haystack.contains(searchNormalized(String(token), latin: latin))
        }
    }
}

public actor SQLiteContentRepository: ContentRepository {
    private static let signposter = OSSignposter(
        subsystem: "com.matthewmccarty.hours",
        category: "ContentRepository"
    )
    private static let recipeHeaderCacheLimit = 4_096

    private let connection: SQLiteConnection
    private let decoder: JSONDecoder
    private let schemaVersion: Int
    public nonisolated let tradition: OfficeTradition
    private let coverage: ClosedRange<LocalDay>
    private var recipeHeaderCache: [Int64: StoredRecipeHeader] = [:]
    private var recipeHeaderInsertionOrder: [Int64] = []
    private var recipeHeaderCacheHitCount = 0

    public init(databaseURL: URL, expectedTradition: OfficeTradition? = nil) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:))
                ?? "SQLite returned \(result)."
            if let database {
                sqlite3_close(database)
            }
            throw ContentRepositoryError.databaseUnavailable(message)
        }
        self.connection = SQLiteConnection(pointer: database)
        self.decoder = JSONDecoder.hoursContentDecoder
        do {
            try SharedContentDatabase.prepare(database, at: databaseURL)
            let manifest = try Self.readManifest(
                database: database,
                decoder: self.decoder
            )
            guard let tradition = OfficeTradition(rubrics: manifest.rubrics),
                  expectedTradition == nil || expectedTradition == tradition else {
                throw ContentRepositoryError.invalidContent("The corpus has incorrect office rubrics.")
            }
            self.tradition = tradition
            self.schemaVersion = manifest.schemaVersion
            self.coverage = try Self.readCoverageRange(database: database)
        } catch {
            throw error
        }
    }

    public func coverageRange() throws -> ClosedRange<LocalDay> {
        coverage
    }

    public func contentSchemaVersion() -> Int {
        schemaVersion
    }

    func cacheMetricsForTesting() -> SQLiteContentRepositoryCacheMetrics {
        SQLiteContentRepositoryCacheMetrics(
            recipeHeaderEntries: recipeHeaderCache.count,
            recipeHeaderHits: recipeHeaderCacheHitCount
        )
    }

    /// Tooling-only corpus traversal that streams the deduplicated score table
    /// instead of retaining every large timeline in memory at once.
    @discardableResult
    public func forEachScoredRealization(
        _ body: @Sendable (ChantScore) throws -> Void
    ) throws -> Int {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT payload FROM scores ORDER BY id",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw ContentRepositoryError.databaseUnavailable(
                String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }

        var count = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return count }
            guard result == SQLITE_ROW else {
                throw ContentRepositoryError.databaseUnavailable(
                    String(cString: sqlite3_errmsg(database))
                )
            }
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                throw ContentRepositoryError.invalidContent(
                    "A scored realization has a null payload."
                )
            }
            let payload = Data(
                bytes: bytes,
                count: Int(sqlite3_column_bytes(statement, 0))
            )
            try autoreleasepool {
                let score = try decoder.decode(
                    ChantScore.self,
                    from: ContentPayloadCodec.decode(payload)
                )
                try body(score)
            }
            count += 1
        }
    }

    public func availableDays() throws -> [LiturgicalDay] {
        let payloads = try query(
            sql: "SELECT payload FROM days ORDER BY date ASC",
            bindings: []
        )
        return try payloads.enumerated().map { index, payload in
            do {
                return try decoder.decode(
                    LiturgicalDay.self,
                    from: ContentPayloadCodec.decode(payload)
                )
            } catch {
                throw ContentRepositoryError.invalidContent(
                    "Day row \(index + 1) could not be decoded: "
                        + error.localizedDescription
                )
            }
        }
    }

    public func days(in range: ClosedRange<LocalDay>) throws -> [LiturgicalDay] {
        let payloads = try query(
            sql: "SELECT payload FROM days WHERE date BETWEEN ? AND ? ORDER BY date ASC",
            bindings: [range.lowerBound.description, range.upperBound.description]
        )
        return try payloads.map {
            try decoder.decode(LiturgicalDay.self, from: ContentPayloadCodec.decode($0))
        }
    }

    public func adjacentDay(
        to date: LocalDay,
        direction: LiturgicalDayDirection
    ) throws -> LiturgicalDay {
        let comparison = direction == .previous ? "<" : ">"
        let order = direction == .previous ? "DESC" : "ASC"
        let payloads = try query(
            sql: "SELECT payload FROM days WHERE date \(comparison) ? ORDER BY date \(order) LIMIT 1",
            bindings: [date.description]
        )
        guard let payload = payloads.first else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return try decoder.decode(
            LiturgicalDay.self,
            from: ContentPayloadCodec.decode(payload)
        )
    }

    public func day(on date: LocalDay) throws -> LiturgicalDay {
        guard coverage.contains(date) else {
            throw ContentRepositoryError.dateOutOfCoverage(date, coverage)
        }
        let payloads = try query(
            sql: "SELECT payload FROM days WHERE date = ? LIMIT 1",
            bindings: [date.description]
        )
        guard let payload = payloads.first else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return try decoder.decode(
            LiturgicalDay.self,
            from: ContentPayloadCodec.decode(payload)
        )
    }

    public func office(on date: LocalDay, hour: OfficeHour) throws -> OfficeDocument {
        let interval = Self.signposter.beginInterval("OfficeRead")
        defer {
            Self.signposter.endInterval("OfficeRead", interval)
        }
        guard coverage.contains(date) else {
            throw ContentRepositoryError.dateOutOfCoverage(date, coverage)
        }
        if schemaVersion >= 2 {
            return try normalizedOffice(on: date, hour: hour)
        }
        let row = try officeRow(
            sql: """
            SELECT documents.id, documents.payload
            FROM office_index
            JOIN documents ON documents.id = office_index.document_id
            WHERE office_index.date = ? AND office_index.hour = ?
            LIMIT 1
            """,
            bindings: [date.description, hour.rawValue]
        )
        guard let row else {
            throw ContentRepositoryError.contentUnavailable(date, hour)
        }
        let stored = try decoder.decode(
            OfficeDocument.self,
            from: ContentPayloadCodec.decode(row.payload)
        )
        guard stored.hour == hour else {
            throw ContentRepositoryError.invalidContent(
                "Office index points to \(stored.hour.rawValue) for \(date):\(hour.rawValue)."
            )
        }
        let scores = try scoresBySection(documentID: row.documentID)
        let sections = stored.sections.map { section in
            OfficeSection(
                id: section.id,
                kind: section.kind,
                title: section.title,
                titleEnglish: section.titleEnglish,
                rubric: section.rubric,
                rubricEnglish: section.rubricEnglish,
                latin: section.latin,
                english: section.english,
                chant: scores[section.id] ?? section.chant
            )
        }
        let office = OfficeDocument(
            id: "\(tradition == .roman1960 ? "" : tradition.rawValue + ":")\(date)-\(hour.rawValue)",
            date: date,
            hour: stored.hour,
            titleLatin: stored.titleLatin,
            titleEnglish: stored.titleEnglish,
            contextLabel: stored.contextLabel,
            sourceVersion: stored.sourceVersion,
            format: stored.format,
            visibleContentDigest: stored.visibleContentDigest,
            observance: stored.observance,
            sections: sections
        )
        try VisibleContentDigest.validate(office)
        return tradition == .roman1960 ? RomanMartyrologyCalendar.materialize(office) : office
    }

    public func searchOfficeTitles(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        hour: OfficeHour? = nil,
        usageRange: ClosedRange<LocalDay>? = nil,
        limit: Int = 50
    ) async throws -> [LiturgicalUsageContext] {
        guard schemaVersion >= 2,
              query.contains(where: { $0.isLetter || $0.isNumber }) else {
            return []
        }
        try Task.checkCancellation()
        let database = connection.pointer
        var conditions: [String] = []
        var bindings: [String] = []
        if let hour {
            conditions.append("office_schedule.hour = ?")
            bindings.append(hour.rawValue)
        }
        if let usageRange {
            conditions.append("office_schedule.date BETWEEN ? AND ?")
            bindings.append(usageRange.lowerBound.description)
            bindings.append(usageRange.upperBound.description)
        }
        let whereClause = conditions.isEmpty
            ? ""
            : "WHERE " + conditions.joined(separator: " AND ")
        let sql = """
        SELECT recipes.id, MIN(office_schedule.date), MAX(office_schedule.date),
               COUNT(*), recipes.payload
        FROM office_schedule
        JOIN recipes ON recipes.id = office_schedule.recipe_id
        \(whereClause)
        GROUP BY recipes.id
        ORDER BY MIN(office_schedule.date), recipes.id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(
                String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        if !bindings.isEmpty {
            try bind(bindings, to: statement)
        }

        var contexts: [LiturgicalUsageContext] = []
        while true {
            try Task.checkCancellation()
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW,
                  let firstDateValue = sqlite3_column_text(statement, 1),
                  let firstDate = LocalDay(iso8601: String(cString: firstDateValue)),
                  let lastDateValue = sqlite3_column_text(statement, 2),
                  let lastDate = LocalDay(iso8601: String(cString: lastDateValue)) else {
                throw ContentRepositoryError.invalidContent(
                    "An office title search row is malformed."
                )
            }
            let recipeID = sqlite3_column_int64(statement, 0)
            let header = try decodedRecipeHeader(
                id: recipeID,
                statement: statement,
                payloadColumn: 4
            )
            guard let observance = header.observance,
                  Self.matchesOfficeTitle(
                    latin: observance.titleLatin,
                    english: observance.titleEnglish,
                    query: query,
                    language: language
                  ) else {
                continue
            }
            contexts.append(
                LiturgicalUsageContext(
                    observanceID: observance.observanceID,
                    firstDate: firstDate,
                    lastDate: lastDate,
                    hour: header.hour,
                    observanceTitleLatin: observance.titleLatin,
                    observanceTitleEnglish: observance.titleEnglish,
                    occurrenceCount: Int(sqlite3_column_int64(statement, 3))
                )
            )
        }
        return Array(
            groupedUsageContexts(contexts).prefix(max(1, min(limit, 50)))
        )
    }

    public func searchHits(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        try await searchHits(
            query: query,
            language: language,
            kind: kind,
            hour: nil,
            requiresScore: false,
            limit: limit
        )
    }

    public func searchHits(
        query: String,
        language: LiturgicalSearchLanguage = .all,
        kind: OfficeSectionKind? = nil,
        hour: OfficeHour?,
        requiresScore: Bool,
        limit: Int = 50
    ) async throws -> [LiturgicalSearchHit] {
        guard schemaVersion >= 2 else { return [] }
        try Task.checkCancellation()
        let match = Self.ftsQuery(query, language: language, schemaVersion: schemaVersion)
        guard !match.isEmpty else { return [] }
        let cappedLimit = max(1, min(limit, 50))
        let database = connection.pointer
        let kindClause = kind == nil ? "" : "AND text_resources.kind = ?"
        let incipitsColumn = schemaVersion >= 3 ? "text_resources.incipits_latin" : "''"
        let scoreExistence = schemaVersion >= 3
            ? "EXISTS(SELECT 1 FROM text_scores WHERE text_scores.text_id = text_resources.id)"
            : "EXISTS(SELECT 1 FROM recipe_sections WHERE recipe_sections.text_id = text_resources.id AND recipe_sections.score_id IS NOT NULL)"
        let scoreClause = requiresScore ? "AND \(scoreExistence)" : ""
        let hourRelation = schemaVersion >= 3 ? "text_recipes" : "recipe_sections"
        let hourClause = hour == nil ? "" : """
        AND EXISTS(
          SELECT 1
          FROM \(hourRelation)
          JOIN office_schedule ON office_schedule.recipe_id = \(hourRelation).recipe_id
          WHERE \(hourRelation).text_id = text_resources.id
            AND office_schedule.hour = ?
        )
        """
        let weights = schemaVersion >= 3
            ? "24.0, 14.0, 14.0, 4.0, 4.0, 1.0, 1.0"
            : "12.0, 12.0, 3.0, 3.0, 1.0, 1.0"
        let sql = """
        SELECT text_resources.id, text_resources.stable_key, text_resources.payload,
               \(incipitsColumn), bm25(text_fts, \(weights)), \(scoreExistence)
        FROM text_fts
        JOIN text_resources ON text_resources.id = text_fts.rowid
        WHERE text_fts MATCH ?
          \(kindClause)
          \(scoreClause)
          \(hourClause)
        ORDER BY bm25(text_fts, \(weights)), length(text_resources.payload)
        LIMIT ?
        """
        // Several resources can print one passage; they are collapsed after
        // ranking. Widen the candidate set only when that leaves the page short.
        func rankedHits(candidateLimit: Int) throws -> (hits: [LiturgicalSearchHit], exhausted: Bool) {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, 1, match, -1, transient) == SQLITE_OK else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            var bindingIndex: Int32 = 2
            if let kind {
                guard sqlite3_bind_text(statement, bindingIndex, kind.rawValue, -1, transient) == SQLITE_OK else {
                    throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
                }
                bindingIndex += 1
            }
            if let hour {
                guard sqlite3_bind_text(statement, bindingIndex, hour.rawValue, -1, transient) == SQLITE_OK else {
                    throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
                }
                bindingIndex += 1
            }
            guard sqlite3_bind_int(statement, bindingIndex, Int32(candidateLimit)) == SQLITE_OK else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }

            var candidates: [LiturgicalSearchCandidate] = []
            while true {
                try Task.checkCancellation()
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else {
                    throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
                }
                guard let stableKeyValue = sqlite3_column_text(statement, 1),
                      let payloadValue = sqlite3_column_blob(statement, 2) else {
                    throw ContentRepositoryError.invalidContent("A search row is malformed.")
                }
                let id = String(cString: stableKeyValue)
                let payload = Data(
                    bytes: payloadValue,
                    count: Int(sqlite3_column_bytes(statement, 2))
                )
                let resource = try decoder.decode(
                    StoredTextResource.self,
                    from: ContentPayloadCodec.decode(payload)
                )
                let incipits = Self.optionalText(statement, column: 3) ?? ""
                let snippetLanguage = Self.matchedLanguage(
                    resource,
                    query: query,
                    requested: language
                )
                candidates.append(
                    LiturgicalSearchCandidate(
                        rank: Self.phraseRank(
                            resource,
                            incipits: incipits,
                            query: query,
                            language: snippetLanguage
                        ),
                        databaseRank: sqlite3_column_double(statement, 4),
                        hit: LiturgicalSearchHit(
                            id: id,
                            kind: resource.kind,
                            titleLatin: resource.title,
                            titleEnglish: resource.titleEnglish,
                            snippet: Self.snippet(
                                for: resource,
                                query: query,
                                language: snippetLanguage
                            ),
                            snippetLanguage: snippetLanguage,
                            hasScoredRealizations: sqlite3_column_int(statement, 5) != 0
                        )
                    )
                )
            }
            let ranked = candidates.sorted { left, right in
                if left.rank != right.rank { return left.rank < right.rank }
                if left.databaseRank != right.databaseRank {
                    return left.databaseRank < right.databaseRank
                }
                return left.hit.id < right.hit.id
            }.map(\.hit)
            return (ranked, candidates.count < candidateLimit)
        }

        var candidateLimit = min(cappedLimit * 5, 250)
        while true {
            let (ranked, exhausted) = try rankedHits(candidateLimit: candidateLimit)
            let hits = Self.deduplicatedSearchHits(ranked, limit: cappedLimit)
            if hits.count >= cappedLimit || exhausted || candidateLimit >= 2_000 {
                return hits
            }
            candidateLimit = min(candidateLimit * 4, 2_000)
        }
    }

    public func searchDetail(
        id: String,
        usageRange: ClosedRange<LocalDay>?
    ) async throws -> LiturgicalSearchResult {
        try Task.checkCancellation()
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT id, payload FROM text_resources WHERE stable_key = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind([id], to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payloadValue = sqlite3_column_blob(statement, 1) else {
            throw ContentRepositoryError.invalidContent("Search resource \(id) is missing.")
        }
        let numericID = sqlite3_column_int64(statement, 0)
        let payload = Data(
            bytes: payloadValue,
            count: Int(sqlite3_column_bytes(statement, 1))
        )
        let resource = try decoder.decode(
            StoredTextResource.self,
            from: ContentPayloadCodec.decode(payload)
        )
        let scores = try scores(forTextResource: numericID)
        try Task.checkCancellation()
        let contexts = try contexts(
            forTextResource: numericID,
            usageRange: usageRange
        )
        try Task.checkCancellation()
        return LiturgicalSearchResult(
            id: id,
            kind: resource.kind,
            titleLatin: resource.title,
            titleEnglish: resource.titleEnglish,
            rubricLatin: resource.rubric,
            rubricEnglish: resource.rubricEnglish,
            latin: resource.latin,
            english: resource.english,
            scoredRealizations: scores,
            contexts: contexts
        )
    }

    private func normalizedOffice(
        on date: LocalDay,
        hour: OfficeHour
    ) throws -> OfficeDocument {
        let row = try officeRow(
            sql: """
            SELECT recipes.id, recipes.payload
            FROM office_schedule
            JOIN recipes ON recipes.id = office_schedule.recipe_id
            WHERE office_schedule.date = ? AND office_schedule.hour = ?
            LIMIT 1
            """,
            bindings: [date.description, hour.rawValue]
        )
        guard let row else {
            throw ContentRepositoryError.contentUnavailable(date, hour)
        }
        let header = try decoder.decode(
            StoredRecipeHeader.self,
            from: ContentPayloadCodec.decode(row.payload)
        )
        guard header.hour == hour else {
            throw ContentRepositoryError.invalidContent(
                "Office schedule points to \(header.hour.rawValue) for \(date):\(hour.rawValue)."
            )
        }
        let sections = try normalizedSections(
            recipeID: row.documentID,
            date: date,
            hour: hour
        )
        let office = OfficeDocument(
            id: "\(tradition == .roman1960 ? "" : tradition.rawValue + ":")\(date)-\(hour.rawValue)",
            date: date,
            hour: header.hour,
            titleLatin: header.titleLatin,
            titleEnglish: header.titleEnglish,
            contextLabel: header.contextLabel,
            sourceVersion: header.sourceVersion,
            format: header.format,
            visibleContentDigest: header.visibleContentDigest,
            observance: header.observance,
            sections: sections
        )
        try VisibleContentDigest.validate(office)
        return tradition == .roman1960 ? RomanMartyrologyCalendar.materialize(office) : office
    }

    private func normalizedSections(
        recipeID: String,
        date: LocalDay,
        hour: OfficeHour
    ) throws -> [OfficeSection] {
        let database = connection.pointer
        let sql = """
        SELECT recipe_sections.position, text_resources.payload, scores.payload
        FROM recipe_sections
        JOIN text_resources ON text_resources.id = recipe_sections.text_id
        LEFT JOIN scores ON scores.id = recipe_sections.score_id
        WHERE recipe_sections.recipe_id = ?
        ORDER BY recipe_sections.position
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind([recipeID], to: statement)
        var sections: [OfficeSection] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return sections }
            guard step == SQLITE_ROW else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            guard let textValue = sqlite3_column_blob(statement, 1) else {
                throw ContentRepositoryError.invalidContent("A normalized recipe section is malformed.")
            }
            let position = Int(sqlite3_column_int64(statement, 0))
            let textPayload = Data(
                bytes: textValue,
                count: Int(sqlite3_column_bytes(statement, 1))
            )
            let text = try decoder.decode(
                StoredTextResource.self,
                from: ContentPayloadCodec.decode(textPayload)
            )
            let chant: ChantScore?
            if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                chant = nil
            } else if let bytes = sqlite3_column_blob(statement, 2) {
                let payload = Data(
                    bytes: bytes,
                    count: Int(sqlite3_column_bytes(statement, 2))
                )
                chant = try decoder.decode(
                    ChantScore.self,
                    from: ContentPayloadCodec.decode(payload)
                )
            } else {
                throw ContentRepositoryError.invalidContent("A scored realization payload is malformed.")
            }
            sections.append(
                OfficeSection(
                    id: "\(date)-\(hour.rawValue)-section-\(position)",
                    kind: text.kind,
                    title: text.title,
                    titleEnglish: text.titleEnglish,
                    rubric: text.rubric,
                    rubricEnglish: text.rubricEnglish,
                    latin: text.latin,
                    english: text.english,
                    chant: chant
                )
            )
        }
    }

    private func scores(forTextResource textID: Int64) throws -> [ChantScore] {
        let scoreRelation = schemaVersion >= 3 ? "text_scores" : "recipe_sections"
        let payloads = try queryInteger(
            sql: """
            SELECT DISTINCT scores.payload
            FROM \(scoreRelation)
            JOIN scores ON scores.id = \(scoreRelation).score_id
            WHERE \(scoreRelation).text_id = ?
            ORDER BY \(scoreRelation).score_id
            """,
            binding: textID
        )
        return try payloads.map {
            try decoder.decode(ChantScore.self, from: ContentPayloadCodec.decode($0))
        }
    }

    private func contexts(
        forTextResource textID: Int64,
        usageRange: ClosedRange<LocalDay>?
    ) throws -> [LiturgicalUsageContext] {
        let database = connection.pointer
        let relation: String
        let scoreJoin: String
        let scoreID: String
        if schemaVersion >= 3 {
            relation = "text_recipes"
            scoreJoin = """
            JOIN recipe_sections
              ON recipe_sections.recipe_id = text_recipes.recipe_id
             AND recipe_sections.text_id = text_recipes.text_id
            """
            scoreID = "recipe_sections.score_id"
        } else {
            relation = "recipe_sections AS text_recipes"
            scoreJoin = ""
            scoreID = "text_recipes.score_id"
        }
        let rangeClause = usageRange == nil
            ? ""
            : "AND office_schedule.date BETWEEN ? AND ?"
        let sql = """
        SELECT office_schedule.date, office_schedule.hour, days.payload,
               scores.payload
        FROM \(relation)
        JOIN office_schedule ON office_schedule.recipe_id = text_recipes.recipe_id
        JOIN days ON days.date = office_schedule.date
        \(scoreJoin)
        LEFT JOIN scores ON scores.id = \(scoreID)
        WHERE text_recipes.text_id = ?
          \(rangeClause)
        ORDER BY office_schedule.date, office_schedule.hour, scores.id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int64(statement, 1, textID) == SQLITE_OK else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        if let usageRange {
            try bind(
                [
                    usageRange.lowerBound.description,
                    usageRange.upperBound.description
                ],
                to: statement,
                startingAt: 2
            )
        }
        var contexts: [LiturgicalUsageContext] = []
        while true {
            try Task.checkCancellation()
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return groupedUsageContexts(contexts) }
            guard step == SQLITE_ROW else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            guard let dateValue = sqlite3_column_text(statement, 0),
                  let date = LocalDay(iso8601: String(cString: dateValue)),
                  let hourValue = sqlite3_column_text(statement, 1),
                  let hour = OfficeHour(rawValue: String(cString: hourValue)),
                  let dayBytes = sqlite3_column_blob(statement, 2) else {
                throw ContentRepositoryError.invalidContent("A search context is malformed.")
            }
            let dayPayload = Data(
                bytes: dayBytes,
                count: Int(sqlite3_column_bytes(statement, 2))
            )
            let day = try decoder.decode(
                LiturgicalDay.self,
                from: ContentPayloadCodec.decode(dayPayload)
            )
            let settingModes: [String]
            if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                settingModes = []
            } else if let scoreBytes = sqlite3_column_blob(statement, 3) {
                let scorePayload = Data(
                    bytes: scoreBytes,
                    count: Int(sqlite3_column_bytes(statement, 3))
                )
                let score = try decoder.decode(
                    ChantScore.self,
                    from: ContentPayloadCodec.decode(scorePayload)
                )
                settingModes = [score.mode].compactMap { $0 }
            } else {
                throw ContentRepositoryError.invalidContent(
                    "A search context score is malformed."
                )
            }
            contexts.append(
                LiturgicalUsageContext(
                    observanceID: day.observanceID,
                    firstDate: date,
                    lastDate: date,
                    hour: hour,
                    observanceTitleLatin: day.titleLatin,
                    observanceTitleEnglish: day.titleEnglish,
                    occurrenceCount: 1,
                    settingModes: settingModes
                )
            )
        }
    }

    private static func ftsQuery(
        _ query: String,
        language: LiturgicalSearchLanguage,
        schemaVersion: Int
    ) -> String {
        let rawTokens = query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !rawTokens.isEmpty else { return "" }
        func expression(columns: String, tokens: [String]) -> String {
            tokens.map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "{\(columns)} : \"\(escaped)\"*"
            }.joined(separator: " AND ")
        }
        let latinColumns = schemaVersion >= 3
            ? "incipits_latin title_latin rubric_latin latin"
            : "title_latin rubric_latin latin"
        let latin = expression(
            columns: latinColumns,
            tokens: rawTokens.map { searchNormalized($0, latin: true) }
        )
        let english = expression(
            columns: "title_english rubric_english english",
            tokens: rawTokens.map { searchNormalized($0, latin: false) }
        )
        switch language {
        case .latin: return latin
        case .english: return english
        case .all: return "(\(latin)) OR (\(english))"
        }
    }

    private static func searchNormalized(_ value: String, latin: Bool) -> String {
        var normalized = value
            .replacingOccurrences(of: "æ", with: "ae", options: .caseInsensitive)
            .replacingOccurrences(of: "œ", with: "oe", options: .caseInsensitive)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: latin ? "la" : "en")
            )
            .lowercased()
        if latin {
            normalized = normalized.replacingOccurrences(of: "j", with: "i")
        }
        return normalized
    }

    private static func matches(
        _ fields: [String],
        query: String,
        latin: Bool
    ) -> Bool {
        let haystack = searchNormalized(fields.joined(separator: " "), latin: latin)
        return query.split { !$0.isLetter && !$0.isNumber }.allSatisfy { token in
            haystack.contains(searchNormalized(String(token), latin: latin))
        }
    }

    private static func matchesOfficeTitle(
        latin: String,
        english: String?,
        query: String,
        language: LiturgicalSearchLanguage
    ) -> Bool {
        switch language {
        case .latin:
            matches([latin], query: query, latin: true)
        case .english:
            matches([english].compactMap { $0 }, query: query, latin: false)
        case .all:
            matches([latin], query: query, latin: true)
                || matches([english].compactMap { $0 }, query: query, latin: false)
        }
    }

    private static func matchedLanguage(
        _ resource: StoredTextResource,
        query: String,
        requested: LiturgicalSearchLanguage
    ) -> LiturgicalSearchLanguage {
        if requested != .all { return requested }
        let latinFields = [resource.title, resource.rubric, resource.latin].compactMap { $0 }
        if matches(latinFields, query: query, latin: true) { return .latin }
        return .english
    }

    private static func phraseRank(
        _ resource: StoredTextResource,
        incipits: String,
        query: String,
        language: LiturgicalSearchLanguage
    ) -> Int {
        let latin = language != .english
        let needle = searchNormalized(query, latin: latin)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = searchNormalized(
            language == .english ? resource.titleEnglish ?? "" : resource.title,
            latin: latin
        )
        let incipit = latin ? searchNormalized(incipits, latin: true) : ""
        let body = searchNormalized(
            language == .english ? resource.english ?? "" : resource.latin,
            latin: latin
        )
        if title == needle || incipit.split(separator: "\n").contains(where: { $0 == needle }) {
            return 0
        }
        if title.hasPrefix(needle) || incipit.hasPrefix(needle) { return 1 }
        if title.contains(needle) || incipit.contains(needle) { return 2 }
        if body.contains(needle) { return 3 }
        return 4
    }

    private static func snippet(
        for resource: StoredTextResource,
        query: String,
        language: LiturgicalSearchLanguage
    ) -> String {
        let latin = language != .english
        let body = language == .english ? resource.english ?? resource.latin : resource.latin
        let paragraphs = body.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        let needle = searchNormalized(query, latin: latin)
        let tokens = query.split { !$0.isLetter && !$0.isNumber }
            .map { searchNormalized(String($0), latin: latin) }
        let selected = paragraphs.max { left, right in
            func score(_ value: String) -> Int {
                let normalized = searchNormalized(value, latin: latin)
                return (normalized.contains(needle) ? 100 : 0)
                    + tokens.filter(normalized.contains).count
            }
            return score(left) < score(right)
        } ?? body
        let collapsed = selected.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > 240 else { return collapsed }
        return String(collapsed.prefix(239)) + "…"
    }

    private static func deduplicatedSearchHits(
        _ hits: [LiturgicalSearchHit],
        limit: Int
    ) -> [LiturgicalSearchHit] {
        var resultIndexByPassage: [String: Int] = [:]
        var results: [LiturgicalSearchHit] = []
        results.reserveCapacity(min(hits.count, limit))

        for hit in hits {
            // The same passage may be printed with the source's line labels in
            // one resource and with verified Scripture references, or chant
            // pointing, in another. Neither makes it a different passage.
            let normalizedSnippet = searchNormalized(
                hit.snippet,
                latin: hit.snippetLanguage != .english
            )
            .replacingOccurrences(
                of: #"\b\d{1,3}:\d{1,3}[a-z]?\b|[*†‡✠]"#,
                with: " ",
                options: .regularExpression
            )
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let passageKey = [
                hit.kind.rawValue,
                hit.snippetLanguage.rawValue,
                normalizedSnippet
            ].joined(separator: "\u{1f}")
            if let index = resultIndexByPassage[passageKey] {
                // Keep the passage's rank, but prefer a representation with notation.
                if hit.hasScoredRealizations && !results[index].hasScoredRealizations {
                    results[index] = hit
                }
                continue
            }
            guard results.count < limit else { continue }
            resultIndexByPassage[passageKey] = results.count
            results.append(hit)
        }
        return results
    }

    private static func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }

    private static func readManifest(
        database: OpaquePointer,
        decoder: JSONDecoder
    ) throws -> ContentManifest {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM meta WHERE key = 'manifest' LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            throw ContentRepositoryError.invalidContent("The corpus manifest is missing.")
        }
        let data = Data(String(cString: value).utf8)
        return try decoder.decode(ContentManifest.self, from: data)
    }

    private static func readCoverageRange(
        database: OpaquePointer
    ) throws -> ClosedRange<LocalDay> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT MIN(date), MAX(date) FROM days",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw ContentRepositoryError.databaseUnavailable(
                String(cString: sqlite3_errmsg(database))
            )
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let firstValue = sqlite3_column_text(statement, 0),
              let first = LocalDay(
                iso8601: String(cString: firstValue)
              ),
              let lastValue = sqlite3_column_text(statement, 1),
              let last = LocalDay(
                iso8601: String(cString: lastValue)
              ) else {
            throw ContentRepositoryError.invalidContent(
                "Corpus coverage bounds are missing."
            )
        }
        return first...last
    }

    private func decodedRecipeHeader(
        id: Int64,
        statement: OpaquePointer,
        payloadColumn: Int32
    ) throws -> StoredRecipeHeader {
        if let cached = recipeHeaderCache[id] {
            recipeHeaderCacheHitCount += 1
            return cached
        }

        guard let payloadValue = sqlite3_column_blob(
            statement,
            payloadColumn
        ) else {
            throw ContentRepositoryError.invalidContent(
                "An office title search payload is missing."
            )
        }
        let payload = Data(
            bytes: payloadValue,
            count: Int(sqlite3_column_bytes(statement, payloadColumn))
        )
        let header = try decoder.decode(
            StoredRecipeHeader.self,
            from: ContentPayloadCodec.decode(payload)
        )
        recipeHeaderCache[id] = header
        recipeHeaderInsertionOrder.append(id)

        if recipeHeaderInsertionOrder.count
            > Self.recipeHeaderCacheLimit {
            let evictedID = recipeHeaderInsertionOrder.removeFirst()
            recipeHeaderCache.removeValue(forKey: evictedID)
        }
        return header
    }

    private func officeRow(
        sql: String,
        bindings: [String]
    ) throws -> (documentID: String, payload: Data)? {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            return nil
        }
        guard step == SQLITE_ROW else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        guard let id = sqlite3_column_text(statement, 0),
              let bytes = sqlite3_column_blob(statement, 1) else {
            throw ContentRepositoryError.invalidContent("Office index row is incomplete.")
        }
        return (
            String(cString: id),
            Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
        )
    }

    private func scoresBySection(documentID: String) throws -> [String: ChantScore] {
        let database = connection.pointer
        let sql = """
        SELECT section_scores.section_id, scores.payload
        FROM section_scores
        JOIN scores ON scores.id = section_scores.score_id
        WHERE section_scores.document_id = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        try bind([documentID], to: statement)
        var result: [String: ChantScore] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw ContentRepositoryError.databaseUnavailable(
                    String(cString: sqlite3_errmsg(database))
                )
            }
            guard let section = sqlite3_column_text(statement, 0),
                  let bytes = sqlite3_column_blob(statement, 1) else {
                throw ContentRepositoryError.invalidContent(
                    "A section score row is malformed."
                )
            }
            let payload = Data(
                bytes: bytes,
                count: Int(sqlite3_column_bytes(statement, 1))
            )
            result[String(cString: section)] = try decoder.decode(
                ChantScore.self,
                from: ContentPayloadCodec.decode(payload)
            )
        }
        return result
    }

    private func query(sql: String, bindings: [String]) throws -> [Data] {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        var rows: [Data] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                throw ContentRepositoryError.invalidContent("A content row has a null payload.")
            }
            rows.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        }
        return rows
    }

    private func queryInteger(sql: String, binding: Int64) throws -> [Data] {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int64(statement, 1, binding) == SQLITE_OK else {
            throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        var rows: [Data] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                throw ContentRepositoryError.invalidContent("A content row has a null payload.")
            }
            rows.append(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        }
    }

    private func bind(
        _ bindings: [String],
        to statement: OpaquePointer,
        startingAt firstIndex: Int32 = 1
    ) throws {
        let database = connection.pointer
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, binding) in bindings.enumerated() {
            guard sqlite3_bind_text(
                statement,
                firstIndex + Int32(index),
                binding,
                -1,
                transient
            ) == SQLITE_OK else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
        }
    }
}

struct SQLiteContentRepositoryCacheMetrics: Equatable, Sendable {
    let recipeHeaderEntries: Int
    let recipeHeaderHits: Int
}

private struct StoredRecipeHeader: Decodable {
    let hour: OfficeHour
    let titleLatin: String
    let titleEnglish: String?
    let contextLabel: String
    let sourceVersion: String
    let format: OfficeDocument.Format?
    let visibleContentDigest: String?
    let observance: OfficeObservance?
}

private struct LiturgicalUsageContextKey: Hashable {
    let observanceID: String?
    let hour: OfficeHour
    let observanceTitleLatin: String
}

private func groupedUsageContexts(
    _ contexts: [LiturgicalUsageContext]
) -> [LiturgicalUsageContext] {
    var grouped: [LiturgicalUsageContextKey: LiturgicalUsageContext] = [:]
    for context in contexts {
        let key = LiturgicalUsageContextKey(
            observanceID: context.observanceID,
            hour: context.hour,
            observanceTitleLatin: context.observanceTitleLatin
        )
        if let existing = grouped[key] {
            grouped[key] = LiturgicalUsageContext(
                observanceID: context.observanceID,
                firstDate: min(existing.firstDate, context.firstDate),
                lastDate: max(existing.lastDate, context.lastDate),
                hour: context.hour,
                observanceTitleLatin: context.observanceTitleLatin,
                observanceTitleEnglish: existing.observanceTitleEnglish
                    ?? context.observanceTitleEnglish,
                occurrenceCount: existing.occurrenceCount + context.occurrenceCount,
                settingModes: Array(
                    Set(existing.settingModes + context.settingModes)
                ).sorted()
            )
        } else {
            grouped[key] = context
        }
    }
    let hourOrder = Dictionary(
        uniqueKeysWithValues: OfficeHour.allCases.enumerated().map {
            ($0.element, $0.offset)
        }
    )
    return grouped.values.sorted { left, right in
        let leftHour = hourOrder[left.hour] ?? 0
        let rightHour = hourOrder[right.hour] ?? 0
        if leftHour != rightHour { return leftHour < rightHour }
        return left.observanceTitleLatin.localizedStandardCompare(
            right.observanceTitleLatin
        ) == .orderedAscending
    }
}

private struct LiturgicalSearchCandidate {
    let rank: Int
    let databaseRank: Double
    let hit: LiturgicalSearchHit
}

private struct StoredTextResource: Decodable {
    let kind: OfficeSectionKind
    let title: String
    let titleEnglish: String?
    let rubric: String?
    let rubricEnglish: String?
    let latin: String
    let english: String?
}

private final class SQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}

private struct OfficeKey: Hashable, Sendable {
    let date: LocalDay
    let hour: OfficeHour
}

public extension JSONDecoder {
    static var hoursContentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension JSONEncoder {
    static var hoursContentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
