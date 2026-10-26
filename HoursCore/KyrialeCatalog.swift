import Foundation
import SQLite3

/// The Kyriale's settings of the Ordinary, which search offers for each part
/// of it (`kyrialeCatalog.ts`): every Kyrie, Gloria, Credo, Sanctus, Agnus
/// Dei and dismissal the book gives, the eighteen Masses, the Credos, the
/// chants ad libitum and the Mass for the dead, each named as the book
/// numbers it ("Kyrie IV"). Both editions read one catalog.
public final class KyrialeCatalog: Sendable {
    /// The schema this reader knows.
    public static let schema = 1

    /// A setting of a part of the Ordinary.
    public struct Setting: Sendable {
        public let part: OrdinaryPart
        /// The name of its Mass or of its trope, and the other Masses that
        /// sing it ("Cum jubilo · also of Mass X").
        public let note: String?
        /// Its chant, its incipit the setting's name.
        public let score: ChantScore
    }

    private struct Row: Sendable {
        let part: OrdinaryPart
        let note: String?
        let payload: Data
    }

    /// The rows in the catalog's order, their scores still compressed: a
    /// part's are read when it is asked for.
    private let rows: [Row]

    /// The parts it has settings for.
    public var parts: Set<OrdinaryPart> {
        Set(rows.map(\.part))
    }

    public init(databaseURL: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:))
                ?? "SQLite returned \(result)."
            if let database { sqlite3_close(database) }
            throw ContentRepositoryError.databaseUnavailable(message)
        }
        defer { sqlite3_close(database) }
        func failure() -> ContentRepositoryError {
            .databaseUnavailable(String(cString: sqlite3_errmsg(database)))
        }
        var manifestStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM meta WHERE key = 'manifest'", -1, &manifestStatement, nil) == SQLITE_OK,
              let manifestStatement else {
            throw failure()
        }
        defer { sqlite3_finalize(manifestStatement) }
        guard sqlite3_step(manifestStatement) == SQLITE_ROW,
              let manifestText = sqlite3_column_text(manifestStatement, 0) else {
            throw ContentRepositoryError.invalidContent("The Kyriale has no manifest.")
        }
        let manifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(String(cString: manifestText).utf8)
        )
        guard manifest.schema == Self.schema else {
            throw ContentRepositoryError.invalidContent("The Kyriale has schema \(manifest.schema); this app reads \(Self.schema).")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT part, note, score FROM settings ORDER BY position", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw failure()
        }
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW,
                  let partText = sqlite3_column_text(statement, 0),
                  let part = OrdinaryPart(rawValue: String(cString: partText)),
                  let bytes = sqlite3_column_blob(statement, 2) else {
                throw ContentRepositoryError.invalidContent("A setting of the Kyriale is malformed.")
            }
            let note = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            rows.append(Row(
                part: part,
                note: note,
                payload: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            ))
        }
        self.rows = rows
    }

    /// The settings of a part, in the book's order.
    public func settings(of part: OrdinaryPart) throws -> [Setting] {
        let decoder = JSONDecoder.hoursContentDecoder
        return try rows.filter { $0.part == part }.map { row in
            Setting(
                part: row.part,
                note: row.note,
                score: try decoder.decode(ChantScore.self, from: ContentPayloadCodec.decode(row.payload))
            )
        }
    }

    /// Every setting, in the catalog's order: for the notation validator.
    public func allSettings() throws -> [Setting] {
        try OrdinaryPart.allCases.flatMap { try settings(of: $0) }
    }

    /// The bundled catalog.
    public static func bundledURL(in bundle: Bundle = .main) throws -> URL {
        for subdirectory in ["Resources/Missal", "Missal", "Resources", nil] as [String?] {
            if let url = bundle.url(forResource: "kyriale", withExtension: "sqlite", subdirectory: subdirectory) {
                return url
            }
        }
        throw ContentRepositoryError.databaseUnavailable("The bundled Kyriale is missing.")
    }

    private struct Manifest: Decodable {
        let schema: Int
    }
}
