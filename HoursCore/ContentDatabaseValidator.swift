import Foundation
import SQLite3

public enum ContentDatabaseValidator {
    private static let legacyRequiredTables: Set<String> = [
        "meta",
        "days",
        "documents",
        "scores",
        "section_scores",
        "office_index"
    ]
    private static let legacyRequiredColumns: [String: [String]] = [
        "meta": ["key", "value"],
        "days": ["date", "payload"],
        "documents": ["id", "payload"],
        "scores": ["id", "payload"],
        "section_scores": ["document_id", "section_id", "score_id"],
        "office_index": ["date", "hour", "document_id"]
    ]
    private static let normalizedRequiredTables: Set<String> = [
        "meta", "days", "text_resources", "text_fts", "text_fts_data",
        "text_fts_idx", "text_fts_docsize", "text_fts_config", "scores",
        "recipes", "recipe_sections", "office_schedule", "widget_calendar"
    ]
    private static let normalizedRequiredColumns: [String: [String]] = [
        "meta": ["key", "value"],
        "days": ["date", "payload"],
        "text_resources": ["id", "stable_key", "kind", "payload"],
        "scores": ["id", "stable_key", "payload"],
        "recipes": ["id", "stable_key", "payload"],
        "recipe_sections": ["recipe_id", "position", "text_id", "score_id"],
        "office_schedule": ["date", "hour", "recipe_id"],
        "widget_calendar": ["date", "title_latin", "rank"]
    ]
    private static let searchOptimizedRequiredTables: Set<String> = normalizedRequiredTables
        .union(["text_scores", "text_recipes"])
    private static let searchOptimizedRequiredColumns: [String: [String]] = [
        "meta": ["key", "value"],
        "days": ["date", "payload"],
        "text_resources": ["id", "stable_key", "kind", "incipits_latin", "payload"],
        "scores": ["id", "stable_key", "payload"],
        "recipes": ["id", "stable_key", "payload"],
        "recipe_sections": ["recipe_id", "position", "text_id", "score_id"],
        "office_schedule": ["date", "hour", "recipe_id"],
        "text_scores": ["text_id", "score_id"],
        "text_recipes": ["text_id", "recipe_id"],
        "widget_calendar": ["date", "title_latin", "rank"]
    ]

    public static func validate(
        databaseURL: URL,
        expectedManifest: ContentManifest? = nil,
        validatesNotation: Bool = true
    ) throws {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "SQLite returned \(openResult)."
            if let database {
                sqlite3_close(database)
            }
            throw ContentRepositoryError.databaseUnavailable(message)
        }
        defer { sqlite3_close(database) }

        let integrity = try textRows(database, sql: "PRAGMA quick_check")
        guard integrity == ["ok"] else {
            throw ContentRepositoryError.invalidContent(
                "SQLite integrity check failed: \(integrity.joined(separator: ", "))."
            )
        }
        guard try textRows(database, sql: "PRAGMA foreign_key_check").isEmpty else {
            throw ContentRepositoryError.invalidContent("SQLite foreign-key validation failed.")
        }

        let tables = Set(
            try textRows(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        )
        guard tables.contains("meta") else {
            throw ContentRepositoryError.invalidContent("Missing required table: meta.")
        }
        let decoder = JSONDecoder.hoursContentDecoder
        let manifestData = try singlePayload(
            database,
            sql: "SELECT value FROM meta WHERE key = 'manifest'"
        )
        let embeddedManifest = try decode(
            ContentManifest.self,
            from: manifestData,
            decoder: decoder,
            label: "manifest"
        )
        guard ContentPackInstaller.supportedSchemaVersions.contains(
            embeddedManifest.schemaVersion
        ) else {
            throw ContentRepositoryError.invalidContent(
                "Embedded manifest has unsupported schema \(embeddedManifest.schemaVersion)."
            )
        }
        let requiredTables: Set<String>
        let requiredColumns: [String: [String]]
        switch embeddedManifest.schemaVersion {
        case 3:
            requiredTables = searchOptimizedRequiredTables
            requiredColumns = searchOptimizedRequiredColumns
        case 2:
            requiredTables = normalizedRequiredTables
            requiredColumns = normalizedRequiredColumns
        default:
            requiredTables = legacyRequiredTables
            requiredColumns = legacyRequiredColumns
        }
        let missingTables = requiredTables.subtracting(tables).sorted()
        guard missingTables.isEmpty else {
            throw ContentRepositoryError.invalidContent(
                "Missing required tables: \(missingTables.joined(separator: ", "))."
            )
        }
        for (table, expectedColumns) in requiredColumns {
            let columns = try textRows(
                database,
                sql: "SELECT name FROM pragma_table_info('\(table)') ORDER BY cid"
            )
            guard columns == expectedColumns else {
                throw ContentRepositoryError.invalidContent(
                    "\(table) has an unexpected SQLite schema."
                )
            }
        }

        guard embeddedManifest.rubrics == "Rubrics 1960 - 1960" else {
            throw ContentRepositoryError.invalidContent("Embedded manifest has incorrect rubrics.")
        }
        if let expectedManifest {
            guard expectedManifest.schemaVersion == embeddedManifest.schemaVersion,
                  expectedManifest.corpusVersion == embeddedManifest.corpusVersion,
                  expectedManifest.minimumAppVersion == embeddedManifest.minimumAppVersion,
                  expectedManifest.createdAt == embeddedManifest.createdAt,
                  expectedManifest.rubrics == embeddedManifest.rubrics,
                  expectedManifest.sources == embeddedManifest.sources,
                  expectedManifest.coverage == embeddedManifest.coverage,
                  expectedManifest.compilerRevision == embeddedManifest.compilerRevision,
                  expectedManifest.normalizedCounts == embeddedManifest.normalizedCounts,
                  expectedManifest.notices == embeddedManifest.notices else {
                throw ContentRepositoryError.invalidContent(
                    "Downloaded database does not match its signed manifest metadata."
                )
            }
        }

        let rubrics = try String(
            decoding: singlePayload(
                database,
                sql: "SELECT value FROM meta WHERE key = 'rubrics'"
            ),
            as: UTF8.self
        )
        guard rubrics == embeddedManifest.rubrics else {
            throw ContentRepositoryError.invalidContent("Rubrics metadata is inconsistent.")
        }

        let dayCount = try integer(database, sql: "SELECT COUNT(*) FROM days")
        let officeIndexTable = embeddedManifest.schemaVersion >= 2
            ? "office_schedule"
            : "office_index"
        let officeCount = try integer(
            database,
            sql: "SELECT COUNT(*) FROM \(officeIndexTable)"
        )
        guard officeCount == embeddedManifest.coverage.generatedOfficeCount,
              officeCount == embeddedManifest.coverage.expectedOfficeCount else {
            throw ContentRepositoryError.invalidContent(
                "Office coverage count does not match the manifest."
            )
        }
        guard dayCount > 0, officeCount == dayCount * OfficeHour.allCases.count else {
            throw ContentRepositoryError.invalidContent(
                "Every stored civil date must contain exactly eight canonical hours."
            )
        }
        let incompleteDates = try integer(
            database,
            sql: """
            SELECT COUNT(*) FROM (
                SELECT date
                FROM \(officeIndexTable)
                GROUP BY date
                HAVING COUNT(*) != 8 OR COUNT(DISTINCT hour) != 8
            )
            """
        )
        guard incompleteDates == 0 else {
            throw ContentRepositoryError.invalidContent(
                "\(incompleteDates) dates have incomplete canonical-hour coverage."
            )
        }

        let bounds = try textRows(
            database,
            sql: "SELECT MIN(date) FROM days UNION ALL SELECT MAX(date) FROM days"
        )
        guard bounds == [
            embeddedManifest.coverage.startDate.description,
            embeddedManifest.coverage.endDate.description
        ] else {
            throw ContentRepositoryError.invalidContent("Stored date bounds do not match coverage.")
        }
        if !embeddedManifest.coverage.isSample,
           !embeddedManifest.coverage.hasReviewedWindowCoverage {
            throw ContentRepositoryError.invalidContent(
                "Release coverage is not the declared previous-year-through-next-10-years reviewed window."
            )
        }

        var authoritativeOfficeCount = 0
        var unavailableOfficeCount = 0
        var legacyOfficeCount = 0
        let validateOffice: (String, OfficeDocument, Int) throws -> Void = {
            indexedHour, office, occurrenceCount in
            guard office.hour.rawValue == indexedHour else {
                throw ContentRepositoryError.invalidContent(
                    "An office index points to a document for \(office.hour.rawValue)."
                )
            }
            switch office.format {
            case .authoritativeOrdered:
                authoritativeOfficeCount += occurrenceCount
                guard office.observance != nil,
                      office.visibleContentDigest?.isEmpty == false,
                      !office.sections.isEmpty,
                      office.sections.allSatisfy({
                          !$0.latin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      }) else {
                    throw ContentRepositoryError.invalidContent(
                        "An authoritative office lacks metadata, a digest, or Latin content."
                    )
                }
            case .contentUnavailable:
                unavailableOfficeCount += occurrenceCount
                guard office.observance != nil,
                      office.visibleContentDigest == nil,
                      office.sections.isEmpty else {
                    throw ContentRepositoryError.invalidContent(
                        "An unavailable office must contain metadata only."
                    )
                }
            case .legacyReconstructed, nil:
                guard embeddedManifest.coverage.isSample else {
                    throw ContentRepositoryError.invalidContent(
                        "A correction-pack office uses the legacy reconstruction format."
                    )
                }
                legacyOfficeCount += occurrenceCount
            }
            if (office.hour == .vespers || office.hour == .compline)
                && office.format != .legacyReconstructed {
                guard office.observance?.eveningContext != nil else {
                    throw ContentRepositoryError.invalidContent(
                        "An evening office lacks resolved Vespers context."
                    )
                }
            }
        }
        if embeddedManifest.schemaVersion >= 2 {
            try forEachNormalizedOffice(
                database,
                decoder: decoder,
                validateOffice
            )
        } else {
            try forEachLegacyOffice(
                database,
                decoder: decoder,
                validateOffice
            )
        }
        let expectedAuthoritativeCount =
            embeddedManifest.coverage.authoritativeOfficeCount ?? officeCount
        guard authoritativeOfficeCount == expectedAuthoritativeCount,
              authoritativeOfficeCount + unavailableOfficeCount + legacyOfficeCount
                == officeCount else {
            throw ContentRepositoryError.invalidContent(
                "Authoritative and unavailable office counts do not match the manifest."
            )
        }

        if embeddedManifest.schemaVersion >= 2 {
            guard let counts = embeddedManifest.normalizedCounts else {
                throw ContentRepositoryError.invalidContent(
                    "A normalized manifest lacks normalized table counts."
                )
            }
            let textCount = try integer(database, sql: "SELECT COUNT(*) FROM text_resources")
            let scoreCount = try integer(database, sql: "SELECT COUNT(*) FROM scores")
            let recipeCount = try integer(database, sql: "SELECT COUNT(*) FROM recipes")
            guard counts.textResources == textCount,
                  counts.scoredChantRealizations == scoreCount,
                  counts.recipes == recipeCount,
                  counts.scheduledOffices == officeCount else {
                throw ContentRepositoryError.invalidContent(
                    "Normalized table counts do not match the manifest."
                )
            }
            let widgetCount = try integer(database, sql: "SELECT COUNT(*) FROM widget_calendar")
            guard widgetCount == dayCount else {
                throw ContentRepositoryError.invalidContent(
                    "The widget calendar index does not cover every civil date."
                )
            }
        }

        guard validatesNotation else { return }
        var failures: [GregorianCorpusValidationFailure] = []
        for payload in try payloadRows(database, sql: "SELECT payload FROM scores") {
            let score = try decode(
                ChantScore.self,
                from: payload,
                decoder: decoder,
                label: "score"
            )
            guard score.timeline.events.allSatisfy({
                $0.clef.map { (1...4).contains($0.line) } ?? true
            }) else {
                throw ContentRepositoryError.invalidContent(
                    "A score timeline contains an invalid clef line."
                )
            }
            do {
                _ = try GregorianScoreParser.parse(
                    gabc: score.gabc,
                    timeline: score.timeline
                )
            } catch {
                failures.append(
                    GregorianCorpusValidationFailure(
                        officeID: "content-pack",
                        scoreID: score.id,
                        message: error.localizedDescription
                    )
                )
            }
        }
        if !failures.isEmpty {
            throw GregorianCorpusValidationError(failures: failures)
        }
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from payload: Data,
        decoder: JSONDecoder,
        label: String
    ) throws -> Value {
        do {
            return try decoder.decode(
                type,
                from: ContentPayloadCodec.decode(payload)
            )
        } catch {
            throw ContentRepositoryError.invalidContent(
                "Could not decode \(label): \(error.localizedDescription)"
            )
        }
    }

    private static func integer(_ database: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        try prepare(database, sql: sql, statement: &statement)
        guard let statement else {
            throw ContentRepositoryError.invalidContent("SQLite did not prepare a count query.")
        }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            throw sqliteError(database, step: step)
        }
        let value = Int(sqlite3_column_int64(statement, 0))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ContentRepositoryError.invalidContent("Count query returned multiple rows.")
        }
        return value
    }

    private static func forEachLegacyOffice(
        _ database: OpaquePointer,
        decoder: JSONDecoder,
        _ body: (String, OfficeDocument, Int) throws -> Void
    ) throws {
        let sql = """
        SELECT office_index.hour, documents.payload
        FROM office_index
        JOIN documents ON documents.id = office_index.document_id
        ORDER BY office_index.date, office_index.hour
        """
        var statement: OpaquePointer?
        try prepare(database, sql: sql, statement: &statement)
        guard let statement else {
            throw ContentRepositoryError.invalidContent(
                "SQLite did not prepare the office validation query."
            )
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else {
                throw sqliteError(database, step: step)
            }
            guard let hour = sqlite3_column_text(statement, 0),
                  sqlite3_column_type(statement, 1) != SQLITE_NULL,
                  let payload = sqlite3_column_blob(statement, 1) else {
                throw ContentRepositoryError.invalidContent(
                    "An indexed office row is malformed."
                )
            }
            try autoreleasepool {
                let data = Data(
                    bytes: payload,
                    count: Int(sqlite3_column_bytes(statement, 1))
                )
                try body(
                    String(cString: hour),
                    decode(
                        OfficeDocument.self,
                        from: data,
                        decoder: decoder,
                        label: "indexed office"
                    ),
                    1
                )
            }
        }
    }

    private static func forEachNormalizedOffice(
        _ database: OpaquePointer,
        decoder: JSONDecoder,
        _ body: (String, OfficeDocument, Int) throws -> Void
    ) throws {
        let sql = """
        SELECT MIN(office_schedule.date), MIN(office_schedule.hour),
               office_schedule.recipe_id, recipes.payload,
               COUNT(*), COUNT(DISTINCT office_schedule.hour)
        FROM office_schedule
        JOIN recipes ON recipes.id = office_schedule.recipe_id
        GROUP BY office_schedule.recipe_id, recipes.payload
        ORDER BY office_schedule.recipe_id
        """
        var statement: OpaquePointer?
        try prepare(database, sql: sql, statement: &statement)
        guard let statement else {
            throw ContentRepositoryError.invalidContent(
                "SQLite did not prepare the normalized office validation query."
            )
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else { throw sqliteError(database, step: step) }
            try autoreleasepool {
                guard let dateValue = sqlite3_column_text(statement, 0),
                      let date = LocalDay(iso8601: String(cString: dateValue)),
                      let hourValue = sqlite3_column_text(statement, 1),
                      let hour = OfficeHour(rawValue: String(cString: hourValue)),
                      let recipeValue = sqlite3_column_text(statement, 2),
                      let payloadValue = sqlite3_column_blob(statement, 3),
                      sqlite3_column_int64(statement, 5) == 1 else {
                    throw ContentRepositoryError.invalidContent(
                        "A normalized office row is malformed."
                    )
                }
                let headerData = Data(
                    bytes: payloadValue,
                    count: Int(sqlite3_column_bytes(statement, 3))
                )
                let header = try decode(
                    ValidatorRecipeHeader.self,
                    from: headerData,
                    decoder: decoder,
                    label: "office recipe"
                )
                let sections = try normalizedSections(
                    database,
                    recipeID: String(cString: recipeValue),
                    date: date,
                    hour: hour,
                    decoder: decoder
                )
                let office = OfficeDocument(
                    id: "\(date)-\(hour.rawValue)",
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
                if office.format == .authoritativeOrdered {
                    try VisibleContentDigest.validate(office)
                }
                try body(
                    hour.rawValue,
                    office,
                    Int(sqlite3_column_int64(statement, 4))
                )
            }
        }
    }

    private static func normalizedSections(
        _ database: OpaquePointer,
        recipeID: String,
        date: LocalDay,
        hour: OfficeHour,
        decoder: JSONDecoder
    ) throws -> [OfficeSection] {
        let sql = """
        SELECT recipe_sections.position, text_resources.payload, scores.payload
        FROM recipe_sections
        JOIN text_resources ON text_resources.id = recipe_sections.text_id
        LEFT JOIN scores ON scores.id = recipe_sections.score_id
        WHERE recipe_sections.recipe_id = ?
        ORDER BY recipe_sections.position
        """
        var statement: OpaquePointer?
        try prepare(database, sql: sql, statement: &statement)
        guard let statement else {
            throw ContentRepositoryError.invalidContent("SQLite did not prepare a recipe query.")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, recipeID, -1, transient) == SQLITE_OK else {
            throw sqliteError(database, step: sqlite3_errcode(database))
        }
        var sections: [OfficeSection] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return sections }
            guard step == SQLITE_ROW else { throw sqliteError(database, step: step) }
            guard let textValue = sqlite3_column_blob(statement, 1) else {
                throw ContentRepositoryError.invalidContent("A recipe section is malformed.")
            }
            let textData = Data(
                bytes: textValue,
                count: Int(sqlite3_column_bytes(statement, 1))
            )
            let text = try decode(
                ValidatorTextResource.self,
                from: textData,
                decoder: decoder,
                label: "text resource"
            )
            let score: ChantScore?
            if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                score = nil
            } else if let scoreValue = sqlite3_column_blob(statement, 2) {
                let scoreData = Data(
                    bytes: scoreValue,
                    count: Int(sqlite3_column_bytes(statement, 2))
                )
                score = try decode(
                    ChantScore.self,
                    from: scoreData,
                    decoder: decoder,
                    label: "scored realization"
                )
            } else {
                throw ContentRepositoryError.invalidContent("A score payload is malformed.")
            }
            sections.append(OfficeSection(
                id: "\(date)-\(hour.rawValue)-section-\(sqlite3_column_int64(statement, 0))",
                kind: text.kind,
                title: text.title,
                titleEnglish: text.titleEnglish,
                rubric: text.rubric,
                rubricEnglish: text.rubricEnglish,
                latin: text.latin,
                english: text.english,
                chant: score
            ))
        }
    }

    private static func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private static func singlePayload(
        _ database: OpaquePointer,
        sql: String
    ) throws -> Data {
        let rows = try payloadRows(database, sql: sql)
        guard rows.count == 1 else {
            throw ContentRepositoryError.invalidContent(
                "Expected one metadata row, found \(rows.count)."
            )
        }
        return rows[0]
    }

    private static func textRows(
        _ database: OpaquePointer,
        sql: String
    ) throws -> [String] {
        try payloadRows(database, sql: sql).map {
            String(decoding: $0, as: UTF8.self)
        }
    }

    private static func payloadRows(
        _ database: OpaquePointer,
        sql: String
    ) throws -> [Data] {
        var statement: OpaquePointer?
        try prepare(database, sql: sql, statement: &statement)
        guard let statement else {
            throw ContentRepositoryError.invalidContent("SQLite did not prepare a query.")
        }
        defer { sqlite3_finalize(statement) }
        var rows: [Data] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return rows
            }
            guard step == SQLITE_ROW else {
                throw sqliteError(database, step: step)
            }
            guard sqlite3_column_type(statement, 0) != SQLITE_NULL,
                  let bytes = sqlite3_column_blob(statement, 0) else {
                throw ContentRepositoryError.invalidContent("SQLite returned a null payload.")
            }
            rows.append(
                Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            )
        }
    }

    private static func prepare(
        _ database: OpaquePointer,
        sql: String,
        statement: inout OpaquePointer?
    ) throws {
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw sqliteError(database, step: result)
        }
    }

    private static func sqliteError(
        _ database: OpaquePointer,
        step: Int32
    ) -> ContentRepositoryError {
        .databaseUnavailable(
            "\(String(cString: sqlite3_errmsg(database))) (SQLite \(step))."
        )
    }
}

private struct ValidatorRecipeHeader: Decodable {
    let hour: OfficeHour
    let titleLatin: String
    let titleEnglish: String?
    let contextLabel: String
    let sourceVersion: String
    let format: OfficeDocument.Format?
    let visibleContentDigest: String?
    let observance: OfficeObservance?
}

private struct ValidatorTextResource: Decodable {
    let kind: OfficeSectionKind
    let title: String
    let titleEnglish: String?
    let rubric: String?
    let rubricEnglish: String?
    let latin: String
    let english: String?
}
