import Foundation
import SQLite3
import XCTest
@testable import HoursCore

final class SharedContentDatabaseTests: XCTestCase {
    func testSharedLookupReleasesFileLockAfterSuccessCacheHitAndDecodeFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = String(repeating: "c", count: 64)
        let catalog = directory.appendingPathComponent(SharedContentDatabase.catalogName)
        let edition = directory.appendingPathComponent("edition.sqlite")
        try withDatabase(catalog) { database in
            try execute(database, "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE resources(id INTEGER PRIMARY KEY,payload BLOB)")
            try put(database, sql: "INSERT INTO meta VALUES('identity',?)", data: Data(identity.utf8), text: true)
            try put(database, sql: "INSERT INTO resources VALUES(1,?)", data: Data(#""A verse""#.utf8))
            try put(database, sql: "INSERT INTO resources VALUES(2,?)", data: Data("invalid JSON".utf8))
        }
        try makeEdition(edition, identity: identity, payload: ["latin": ["$r": 1]])
        try withDatabase(edition) { database in
            try SharedContentDatabase.prepare(database, at: edition)
            for _ in 0..<2 {
                _ = try payload(database)
                try withDatabase(catalog) { writer in
                    // BEGIN EXCLUSIVE fails with SQLITE_BUSY if the resolver
                    // kept a read lock, even though the outer query finished.
                    try execute(writer, "BEGIN EXCLUSIVE; ROLLBACK")
                }
            }
            try execute(database, "UPDATE main.days SET payload = '{\"latin\":{\"$r\":2}}'")
            XCTAssertThrowsError(try payload(database))
            try withDatabase(catalog) { writer in
                try execute(writer, "BEGIN EXCLUSIVE; ROLLBACK")
            }
        }
    }

    func testCatalogExpandsBothRomanEditionsWithExactTextAndDistinctScoreIdentities() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = String(repeating: "a", count: 64)
        let timeline: [String: Any] = ["events": [["i": ":0", "p": ":p:0", "y": ":s:0", "s": "Ký", "n": 1, "d": 1.5, "m": ["mora"], "c": ["k": "c", "l": 4, "b": false]]]]
        let resources: [Any] = ["Oratio", "Orémus.\n\n", "Let us pray.\n", timeline]
        try withDatabase(directory.appendingPathComponent(SharedContentDatabase.catalogName)) { database in
            try execute(database, "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE resources(id INTEGER PRIMARY KEY,payload BLOB)")
            try put(database, sql: "INSERT INTO meta VALUES('identity',?)", data: Data(identity.utf8), text: true)
            for value in resources {
                let json = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
                try put(database, sql: "INSERT INTO resources(payload) VALUES(?)", data: ContentPayloadCodec.encodeForTesting(json))
            }
        }
        for tradition in OfficeTradition.allCases {
            let url = directory.appendingPathComponent("\(tradition.rawValue).sqlite")
            let encoded: [String: Any] = ["title": ["$r": 1], "latin": ["$join": [["$r": 2], "Deus."]], "english": ["$r": 3],
                "reviewStatus": tradition == .roman1960 ? "approved" : "sourceTranscription",
                "provenance": tradition.title, "timeline": ["$timeline": [tradition.rawValue, ["$r": 4]]]]
            try makeEdition(url, identity: identity, payload: encoded)
            try withDatabase(url) { database in
                try SharedContentDatabase.prepare(database, at: url)
                let decoded = try JSONSerialization.jsonObject(with: payload(database)) as? [String: Any]
                XCTAssertEqual(decoded?["title"] as? String, "Oratio")
                XCTAssertEqual(decoded?["latin"] as? String, "Orémus.\n\nDeus.")
                XCTAssertEqual(decoded?["english"] as? String, "Let us pray.\n")
                XCTAssertEqual(decoded?["provenance"] as? String, tradition.title)
                XCTAssertEqual(decoded?["reviewStatus"] as? String, tradition == .roman1960 ? "approved" : "sourceTranscription")
                let events = (decoded?["timeline"] as? [String: Any])?["events"] as? [[String: Any]]
                XCTAssertEqual(events?.first?["i"] as? String, tradition.rawValue + ":0")
                XCTAssertEqual(events?.first?["p"] as? String, tradition.rawValue + ":p:0")
                XCTAssertEqual(events?.first?["y"] as? String, tradition.rawValue + ":s:0")
                XCTAssertEqual(events?.first?["d"] as? Double, 1.5)
                XCTAssertEqual(events?.first?["m"] as? [String], ["mora"])
                // Exercise both caches without changing the decoded result.
                XCTAssertEqual(try payload(database), try payload(database))
            }
        }
    }

    func testMissingMismatchedOrCorruptCatalogFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = String(repeating: "b", count: 64)
        let edition = directory.appendingPathComponent("edition.sqlite")
        try makeEdition(edition, identity: identity, payload: ["latin": ["$r": 1]])
        try withDatabase(edition) { database in
            XCTAssertThrowsError(try SharedContentDatabase.prepare(database, at: edition))
        }
        let catalog = directory.appendingPathComponent(SharedContentDatabase.catalogName)
        try withDatabase(catalog) { database in
            try execute(database, "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE resources(id INTEGER PRIMARY KEY,payload BLOB); INSERT INTO meta VALUES('identity','wrong')")
        }
        try withDatabase(edition) { database in
            XCTAssertThrowsError(try SharedContentDatabase.prepare(database, at: edition))
        }
        try withDatabase(catalog) { database in
            try put(database, sql: "UPDATE meta SET value=?", data: Data(identity.utf8), text: true)
        }
        try withDatabase(edition) { database in
            try SharedContentDatabase.prepare(database, at: edition)
            XCTAssertThrowsError(try payload(database)) // Missing resource.
        }
        try withDatabase(catalog) { database in
            try put(database, sql: "INSERT INTO resources VALUES(1,?)", data: Data(#"{"$r":1}"#.utf8))
        }
        try withDatabase(edition) { database in
            try SharedContentDatabase.prepare(database, at: edition)
            XCTAssertThrowsError(try payload(database)) // Catalog cycles are forbidden.
        }
    }

    func testNodePackedFixtureValidatesAndLoadsThroughNativeRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = Bundle(for: Self.self)
        let edition = try XCTUnwrap(bundle.url(forResource: "shared-edition-fixture", withExtension: "bin"))
        let catalog = try XCTUnwrap(bundle.url(forResource: "shared-catalog-fixture", withExtension: "bin"))
        let url = directory.appendingPathComponent("fixture.sqlite")
        try FileManager.default.copyItem(at: edition, to: url)
        try FileManager.default.copyItem(at: catalog, to: directory.appendingPathComponent(SharedContentDatabase.catalogName))
        XCTAssertNoThrow(try ContentDatabaseValidator.validate(databaseURL: url))
        let repository = try SQLiteContentRepository(databaseURL: url)
        for hour in OfficeHour.allCases {
            let office = try await repository.office(on: LocalDay(year: 2026, month: 7, day: 23), hour: hour)
            XCTAssertFalse(office.sections.isEmpty)
        }
        let hits = try await repository.searchHits(query: "Deus", language: .latin, kind: nil, limit: 5)
        XCTAssertFalse(hits.isEmpty)
    }

    func testBuiltAppUsesOneSharedCatalogWithinAggregateBudget() async throws {
        var total = 0
        var catalogs = Set<URL>()
        for tradition in OfficeTradition.allCases {
            let url = try tradition.databaseURL()
            let repository = try SQLiteContentRepository(databaseURL: url, expectedTradition: tradition)
            let schema = await repository.contentSchemaVersion()
            XCTAssertEqual(schema, 4)
            total += try Data(contentsOf: url, options: .mappedIfSafe).count
            catalogs.insert(url.deletingLastPathComponent().appendingPathComponent(SharedContentDatabase.catalogName))
        }
        XCTAssertEqual(catalogs.count, 1)
        total += try Data(contentsOf: XCTUnwrap(catalogs.first), options: .mappedIfSafe).count
        XCTAssertLessThanOrEqual(total, ContentPerformanceBudgets.sharedOfficeBundleBytes)
        XCTAssertFalse(ContentPackInstaller.supportedSchemaVersions.contains(4), "Bundle-only packs require their catalog and must not be accepted as standalone downloads.")
    }

    private func makeEdition(_ url: URL, identity: String, payload: [String: Any]) throws {
        try withDatabase(url) { database in
            try execute(database, """
                CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);
                INSERT INTO meta VALUES('manifest','{"schemaVersion":4}');
                CREATE TABLE days(date TEXT PRIMARY KEY,payload BLOB);
                CREATE TABLE text_resources(id INTEGER PRIMARY KEY,stable_key TEXT,kind TEXT,incipits_latin TEXT,payload BLOB);
                CREATE TABLE scores(id INTEGER PRIMARY KEY,stable_key TEXT,payload BLOB);
                CREATE TABLE recipes(id INTEGER PRIMARY KEY,stable_key TEXT,payload BLOB);
                """)
            try put(database, sql: "INSERT INTO meta VALUES('shared_catalog',?)", data: Data(identity.utf8), text: true)
            let data = try JSONSerialization.data(withJSONObject: payload)
            try put(database, sql: "INSERT INTO days VALUES('2026-09-07',?)", data: ContentPayloadCodec.encodeForTesting(data))
        }
    }

    private func withDatabase(_ url: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let pointer = try XCTUnwrap(database)
        defer { sqlite3_close(pointer) }
        try body(pointer)
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ContentRepositoryError.invalidContent(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func put(_ database: OpaquePointer, sql: String, data: Data, text: Bool = false) throws {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        let query = try XCTUnwrap(statement)
        defer { sqlite3_finalize(query) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if text {
            XCTAssertEqual(sqlite3_bind_text(query, 1, String(decoding: data, as: UTF8.self), -1, transient), SQLITE_OK)
        } else {
            XCTAssertEqual(data.withUnsafeBytes { sqlite3_bind_blob(query, 1, $0.baseAddress, Int32($0.count), transient) }, SQLITE_OK)
        }
        XCTAssertEqual(sqlite3_step(query), SQLITE_DONE)
    }

    private func payload(_ database: OpaquePointer) throws -> Data {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT payload FROM days", -1, &statement, nil), SQLITE_OK)
        let query = try XCTUnwrap(statement)
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW, let bytes = sqlite3_column_blob(query, 0) else {
            throw ContentRepositoryError.invalidContent(String(cString: sqlite3_errmsg(database)))
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
    }
}
