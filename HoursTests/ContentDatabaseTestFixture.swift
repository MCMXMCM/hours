import Foundation
import SQLite3
@testable import HoursCore

enum ContentDatabaseTestFixture {
    static let date = LocalDay(year: 2026, month: 12, day: 8)

    static func makeDatabase(
        unavailableHours: Set<OfficeHour> = [],
        tradition: OfficeTradition = .roman1960,
        sourceOrdered: Bool = false
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "hours-database-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "office.sqlite")

        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw failure("Could not create SQLite fixture.")
        }
        defer { sqlite3_close(database) }
        try execute(
            database,
            """
            PRAGMA foreign_keys = ON;
            CREATE TABLE meta (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE days (
              date TEXT PRIMARY KEY NOT NULL,
              payload BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE documents (
              id TEXT PRIMARY KEY NOT NULL,
              payload BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE scores (
              id TEXT PRIMARY KEY NOT NULL,
              payload BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE section_scores (
              document_id TEXT NOT NULL REFERENCES documents(id),
              section_id TEXT NOT NULL,
              score_id TEXT NOT NULL REFERENCES scores(id),
              PRIMARY KEY(document_id, section_id)
            ) WITHOUT ROWID;
            CREATE TABLE office_index (
              date TEXT NOT NULL,
              hour TEXT NOT NULL CHECK(hour IN (
                'matins', 'lauds', 'prime', 'terce', 'sext', 'none', 'vespers', 'compline'
              )),
              document_id TEXT NOT NULL REFERENCES documents(id),
              PRIMARY KEY(date, hour)
            ) WITHOUT ROWID;
            """
        )

        let manifest = ContentManifest(
            schemaVersion: 1,
            corpusVersion: "test",
            minimumAppVersion: "0.1.0",
            createdAt: Date(timeIntervalSince1970: 0),
            rubrics: tradition.rubrics,
            packSHA256: "",
            signature: "",
            sources: [],
            coverage: ContentCoverage(
                startDate: date,
                endDate: date,
                expectedOfficeCount: 8,
                generatedOfficeCount: 8,
                authoritativeOfficeCount: sourceOrdered ? 0 : unavailableHours.isEmpty
                    ? nil
                    : 8 - unavailableHours.count,
                unresolvedScoreCount: 0,
                ambiguousScoreCount: 0,
                isSample: true
            )
        )
        try insert(
            database,
            sql: "INSERT INTO meta(key, value) VALUES (?, ?)",
            text: ["manifest", String(decoding: try encode(manifest), as: UTF8.self)]
        )
        try insert(
            database,
            sql: "INSERT INTO meta(key, value) VALUES (?, ?)",
            text: ["rubrics", manifest.rubrics]
        )

        let day = LiturgicalDay(
            date: date,
            observanceID: "in-conceptione-immaculata",
            titleLatin: "In Conceptione Immaculata B. Mariae Virginis",
            titleEnglish: "The Immaculate Conception of the Blessed Virgin Mary",
            rank: .firstClass,
            color: .white,
            season: "Advent",
            commemorations: []
        )
        try insertPayload(
            database,
            sql: "INSERT INTO days(date, payload) VALUES (?, ?)",
            key: date.description,
            payload: try encode(day)
        )

        for hour in OfficeHour.allCases {
            let isUnavailable = unavailableHours.contains(hour)
            let section = OfficeSection(
                id: "section-\(hour.rawValue)",
                kind: hour == .compline ? .rubric : .prayer,
                title: hour == .compline ? "Rubrica" : "Oratio",
                rubric: hour == .compline ? nil : "Orémus.",
                latin: hour == .compline
                    ? "Examen conscientiæ vel Pater Noster totum secreto."
                    : "Deus, qui per immaculátam Vírginis Conceptiónem."
            )
            let office = OfficeDocument(
                id: "doc-\(hour.rawValue)",
                date: date,
                hour: hour,
                titleLatin: hour.latinTitle,
                titleEnglish: hour.englishTitle,
                contextLabel: "In Conceptione Immaculata B. Mariae Virginis",
                format: isUnavailable ? .contentUnavailable : sourceOrdered ? .sourceOrdered : .authoritativeOrdered,
                visibleContentDigest: isUnavailable
                    ? nil
                    : try VisibleContentDigest.calculate(for: [section]),
                observance: OfficeObservance(
                    observanceID: "in-conceptione-immaculata",
                    titleLatin: "In Conceptione Immaculata B. Mariae Virginis",
                    titleEnglish: "The Immaculate Conception of the Blessed Virgin Mary",
                    rank: .firstClass,
                    color: .white,
                    season: "Advent",
                    eveningContext: hour == .vespers || hour == .compline
                        ? .secondVespers
                        : nil
                ),
                sections: isUnavailable ? [] : [section]
            )
            try insertPayload(
                database,
                sql: "INSERT INTO documents(id, payload) VALUES (?, ?)",
                key: office.id,
                payload: try encode(office)
            )
            try insert(
                database,
                sql: "INSERT INTO office_index(date, hour, document_id) VALUES (?, ?, ?)",
                text: [date.description, hour.rawValue, office.id]
            )
        }

        return url
    }

    static func mutate(_ url: URL, sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw failure("Could not open SQLite fixture for mutation.")
        }
        defer { sqlite3_close(database) }
        try execute(database, sql)
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try JSONEncoder.hoursContentEncoder.encode(value)
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "SQLite \(result)"
            sqlite3_free(message)
            throw failure(detail)
        }
    }

    private static func insert(
        _ database: OpaquePointer,
        sql: String,
        text values: [String]
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw failure(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            guard sqlite3_bind_text(
                statement,
                Int32(offset + 1),
                value,
                -1,
                sqliteTransient
            ) == SQLITE_OK else {
                throw failure(String(cString: sqlite3_errmsg(database)))
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw failure(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func insertPayload(
        _ database: OpaquePointer,
        sql: String,
        key: String,
        payload: Data
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw failure(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, key, -1, sqliteTransient) == SQLITE_OK else {
            throw failure(String(cString: sqlite3_errmsg(database)))
        }
        let bindResult = payload.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                2,
                bytes.baseAddress,
                Int32(bytes.count),
                sqliteTransient
            )
        }
        guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw failure(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private static func failure(_ description: String) -> NSError {
        NSError(
            domain: "ContentDatabaseTestFixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
