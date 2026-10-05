import CoreFoundation
import Foundation
import SQLite3

/// Bundle-only schema 4 keeps edition-local relationships and FTS indexes,
/// while exact strings and score timelines live in one sibling catalog.
/// Temporary views expose ordinary JSON to every existing repository query.
/// Signed downloadable packs remain self-contained schemas 1–3.
enum SharedContentDatabase {
    static let catalogName = "office-resources.sqlite"

    static func prepare(_ database: OpaquePointer, at url: URL) throws {
        guard let manifest = try metadata(database, key: "manifest"),
              let object = try JSONSerialization.jsonObject(with: Data(manifest.utf8)) as? [String: Any],
              let schema = object["schemaVersion"] as? Int else {
            throw invalid("Missing content manifest.")
        }
        let identity = try metadata(database, key: "shared_catalog")
        guard schema == 4 else {
            guard identity == nil else { throw invalid("Unexpected shared catalog in standalone content.") }
            return
        }
        guard let identity, identity.count == 64 else { throw invalid("Missing shared catalog identity.") }
        let resolver = try SharedContentResolver(
            url: url.deletingLastPathComponent().appendingPathComponent(catalogName),
            identity: identity
        )
        let context = Unmanaged.passRetained(resolver).toOpaque()
        // SQLite owns context, including destruction if registration fails.
        let result = sqlite3_create_function_v2(database, "hours_expand_payload", 1, SQLITE_UTF8,
            context, { context, count, arguments in
                guard let context, count == 1, let argument = arguments?[0],
                      let state = sqlite3_user_data(context),
                      let bytes = sqlite3_value_blob(argument) else {
                    sqlite3_result_error(context, "Missing shared content payload", -1)
                    return
                }
                do {
                    let resolver = Unmanaged<SharedContentResolver>.fromOpaque(state).takeUnretainedValue()
                    let payload = Data(bytes: bytes, count: Int(sqlite3_value_bytes(argument)))
                    let expanded = try resolver.decode(payload)
                    expanded.withUnsafeBytes { buffer in
                        sqlite3_result_blob(context, buffer.baseAddress, Int32(buffer.count),
                            unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                    }
                } catch {
                    sqlite3_result_error(context, error.localizedDescription, -1)
                }
            }, nil, nil, { pointer in
                if let pointer { Unmanaged<SharedContentResolver>.fromOpaque(pointer).release() }
            })
        guard result == SQLITE_OK else { throw invalid(String(cString: sqlite3_errmsg(database))) }
        for (table, columns) in [
            ("days", "date"),
            ("text_resources", "id, stable_key, kind, incipits_latin"),
            ("scores", "id, stable_key"),
            ("recipes", "id, stable_key")
        ] {
            let sql = "CREATE TEMP VIEW \(table) AS SELECT \(columns), hours_expand_payload(payload) AS payload FROM main.\(table)"
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw invalid(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    fileprivate static func metadata(_ database: OpaquePointer, key: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM meta WHERE key=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw invalid("Cannot read content metadata.") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else {
            throw invalid("Cannot bind content metadata key.")
        }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw invalid("Cannot read content metadata value.")
        }
        return String(cString: value)
    }

    fileprivate static func invalid(_ message: String) -> ContentRepositoryError {
        .invalidContent(message)
    }
}

private final class SharedJSONValue: NSObject {
    let value: Any
    init(_ value: Any) { self.value = value }
}

/// Called synchronously by one SQLite connection; no global or cross-actor state.
private final class SharedContentResolver {
    private let database: OpaquePointer
    private let lookup: OpaquePointer
    private let values = NSCache<NSNumber, SharedJSONValue>()
    private let payloads = NSCache<NSData, NSData>()

    init(url: URL, identity: String) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SharedContentDatabase.invalid("The shared office catalog is missing or cannot be opened.")
        }
        do {
            guard try SharedContentDatabase.metadata(database, key: "identity") == identity else {
                throw SharedContentDatabase.invalid("The office corpus and shared catalog belong to different generations.")
            }
            var lookup: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT payload FROM resources WHERE id=?", -1, &lookup, nil) == SQLITE_OK,
                  let lookup else { throw SharedContentDatabase.invalid("The shared catalog schema is invalid.") }
            self.database = database
            self.lookup = lookup
        } catch { sqlite3_close(database); throw error }
        values.totalCostLimit = 8 * 1024 * 1024
        values.countLimit = 2_048
        payloads.totalCostLimit = 16 * 1024 * 1024
        payloads.countLimit = 256
    }

    deinit {
        sqlite3_finalize(lookup)
        sqlite3_close(database)
    }

    func decode(_ payload: Data) throws -> Data {
        if let cached = payloads.object(forKey: payload as NSData) { return cached as Data }
        let object = try JSONSerialization.jsonObject(with: ContentPayloadCodec.decode(payload), options: [.fragmentsAllowed])
        let expanded = try expand(object)
        let result = try JSONSerialization.data(withJSONObject: expanded, options: [.fragmentsAllowed])
        payloads.setObject(result as NSData, forKey: payload as NSData, cost: payload.count + result.count)
        return result
    }

    private func resource(_ number: Any) throws -> Any {
        guard let number = number as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 1, number.doubleValue <= Double(Int64.max),
              number.doubleValue.rounded() == number.doubleValue else {
            throw SharedContentDatabase.invalid("Invalid shared resource identifier.")
        }
        if let cached = values.object(forKey: number) { return cached.value }
        sqlite3_reset(lookup)
        sqlite3_clear_bindings(lookup)
        // SQLITE_ROW leaves the read transaction (and its file lock) active.
        // Reset on every exit, including decoding errors, rather than waiting
        // for another cache miss. Otherwise iOS terminates the suspended app
        // with RUNNINGBOARD 0xdead10cc while this cached statement is idle.
        defer {
            sqlite3_reset(lookup)
            sqlite3_clear_bindings(lookup)
        }
        guard sqlite3_bind_int64(lookup, 1, number.int64Value) == SQLITE_OK,
              sqlite3_step(lookup) == SQLITE_ROW, let bytes = sqlite3_column_blob(lookup, 0) else {
            throw SharedContentDatabase.invalid("Missing shared resource \(number).")
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(lookup, 0)))
        let decoded = try ContentPayloadCodec.decode(data)
        let value = try JSONSerialization.jsonObject(with: decoded, options: [.fragmentsAllowed])
        try validateTerminal(value)
        // JSON object overhead can substantially exceed its encoded length.
        values.setObject(SharedJSONValue(value), forKey: number, cost: decoded.count * 4)
        return value
    }

    private func validateTerminal(_ value: Any, depth: Int = 0) throws {
        guard depth <= 64 else { throw SharedContentDatabase.invalid("Shared content nesting is too deep.") }
        if let object = value as? [String: Any] {
            guard Set(object.keys).isDisjoint(with: ["$r", "$join", "$timeline"]) else {
                throw SharedContentDatabase.invalid("Shared catalog values must not contain references.")
            }
            for child in object.values { try validateTerminal(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            for child in array { try validateTerminal(child, depth: depth + 1) }
        }
    }

    private func expand(_ value: Any, depth: Int = 0) throws -> Any {
        guard depth <= 64 else { throw SharedContentDatabase.invalid("Shared content nesting is too deep.") }
        if let array = value as? [Any] { return try array.map { try expand($0, depth: depth + 1) } }
        guard let object = value as? [String: Any] else { return value }
        if let reference = object["$r"] {
            guard object.count == 1 else { throw SharedContentDatabase.invalid("Invalid shared reference.") }
            return try resource(reference)
        }
        if let joined = object["$join"] {
            guard object.count == 1, let parts = joined as? [Any] else { throw SharedContentDatabase.invalid("Invalid shared string.") }
            return try parts.map { part -> String in
                guard let text = try expand(part, depth: depth + 1) as? String else {
                    throw SharedContentDatabase.invalid("Non-string shared fragment.")
                }
                return text
            }.joined()
        }
        if let timeline = object["$timeline"] {
            guard object.count == 1, let parts = timeline as? [Any], parts.count == 2,
                  let prefix = parts[0] as? String,
                  var body = try expand(parts[1], depth: depth + 1) as? [String: Any],
                  let events = body["events"] as? [[String: Any]] else {
                throw SharedContentDatabase.invalid("Invalid shared timeline.")
            }
            body["events"] = try events.map { event -> [String: Any] in
                var event = event
                for key in ["i", "p", "y"] {
                    guard let suffix = event[key] as? String else { throw SharedContentDatabase.invalid("Invalid shared event identity.") }
                    event[key] = prefix + suffix
                }
                return event
            }
            return body
        }
        return try object.mapValues { try expand($0, depth: depth + 1) }
    }
}
