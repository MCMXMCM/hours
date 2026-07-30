import Foundation
import SQLite3

public enum ContentDatabaseValidator {
    private static let requiredTables: Set<String> = [
        "meta",
        "days",
        "documents",
        "scores",
        "section_scores",
        "office_index"
    ]
    private static let requiredColumns: [String: [String]] = [
        "meta": ["key", "value"],
        "days": ["date", "payload"],
        "documents": ["id", "payload"],
        "scores": ["id", "payload"],
        "section_scores": ["document_id", "section_id", "score_id"],
        "office_index": ["date", "hour", "document_id"]
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
        guard embeddedManifest.schemaVersion == ContentPackInstaller.supportedSchemaVersion else {
            throw ContentRepositoryError.invalidContent(
                "Embedded manifest has unsupported schema \(embeddedManifest.schemaVersion)."
            )
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
                  expectedManifest.coverage == embeddedManifest.coverage else {
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
        let officeCount = try integer(database, sql: "SELECT COUNT(*) FROM office_index")
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
                FROM office_index
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

        var authoritativeOfficeCount = 0
        var unavailableOfficeCount = 0
        for (indexedHour, payload) in try indexedOfficeRows(database) {
            let office = try decode(
                OfficeDocument.self,
                from: payload,
                decoder: decoder,
                label: "indexed office"
            )
            guard office.hour.rawValue == indexedHour else {
                throw ContentRepositoryError.invalidContent(
                    "An office index points to a document for \(office.hour.rawValue)."
                )
            }
            switch office.format {
            case .authoritativeOrdered:
                authoritativeOfficeCount += 1
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
                unavailableOfficeCount += 1
                guard office.observance != nil,
                      office.visibleContentDigest == nil,
                      office.sections.isEmpty else {
                    throw ContentRepositoryError.invalidContent(
                        "An unavailable office must contain metadata only."
                    )
                }
            case .legacyReconstructed, nil:
                throw ContentRepositoryError.invalidContent(
                    "A correction-pack office uses the legacy reconstruction format."
                )
            }
        }
        let expectedAuthoritativeCount =
            embeddedManifest.coverage.authoritativeOfficeCount ?? officeCount
        guard authoritativeOfficeCount == expectedAuthoritativeCount,
              authoritativeOfficeCount + unavailableOfficeCount == officeCount else {
            throw ContentRepositoryError.invalidContent(
                "Authoritative and unavailable office counts do not match the manifest."
            )
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

    private static func indexedOfficeRows(
        _ database: OpaquePointer
    ) throws -> [(hour: String, payload: Data)] {
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
        var rows: [(String, Data)] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return rows
            }
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
            rows.append(
                (
                    String(cString: hour),
                    Data(
                        bytes: payload,
                        count: Int(sqlite3_column_bytes(statement, 1))
                    )
                )
            )
        }
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
