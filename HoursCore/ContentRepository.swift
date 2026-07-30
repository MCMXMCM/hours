import Foundation
import SQLite3

public enum ContentRepositoryError: LocalizedError, Equatable {
    case databaseUnavailable(String)
    case contentUnavailable(LocalDay, OfficeHour?)
    case invalidContent(String)

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
        }
    }
}

public protocol ContentRepository: Sendable {
    func availableDays() async throws -> [LiturgicalDay]
    func day(on date: LocalDay) async throws -> LiturgicalDay
    func office(on date: LocalDay, hour: OfficeHour) async throws -> OfficeDocument
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
}

public actor SQLiteContentRepository: ContentRepository {
    private let connection: SQLiteConnection
    private let decoder: JSONDecoder

    public init(databaseURL: URL) throws {
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

    public func day(on date: LocalDay) throws -> LiturgicalDay {
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
                rubric: section.rubric,
                latin: section.latin,
                english: section.english,
                chant: scores[section.id] ?? section.chant
            )
        }
        let office = OfficeDocument(
            id: "\(date)-\(hour.rawValue)",
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
        return office
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

    private func bind(_ bindings: [String], to statement: OpaquePointer) throws {
        let database = connection.pointer
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, binding) in bindings.enumerated() {
            guard sqlite3_bind_text(
                statement,
                Int32(index + 1),
                binding,
                -1,
                transient
            ) == SQLITE_OK else {
                throw ContentRepositoryError.databaseUnavailable(String(cString: sqlite3_errmsg(database)))
            }
        }
    }
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
