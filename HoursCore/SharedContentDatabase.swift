import CoreFoundation
import Foundation
import SQLite3

/// Bundle-only schema 5 keeps exact strings and score timelines in one
/// sibling catalog, and stores each edition's relations compactly: ordered
/// sections in pages of like recipes, the recipes of each text as one list,
/// recipe headers without their repeated keys, and one copy of the day
/// records that are alike. Temporary views expose the tables of the
/// standalone schema to every existing repository query; the compiler's
/// packer (sharedCorpus.ts) proves that they return exactly what the
/// standalone edition holds. One view has no standalone counterpart:
/// `recipe_titles` gives each recipe's observance as plain columns, which
/// the search of office titles reads in place of every recipe's header.
/// Signed downloadable packs remain self-contained schemas 1–3.
enum SharedContentDatabase {
    static let catalogName = "office-resources.sqlite"
    static let storageSchema = 5

    /// A section as one integer, the text above the score.
    static let scoreRadix: Int64 = 16_777_216

    /// The views of sharedCorpus.ts (`sharedViewSQL`), statement for statement.
    private static let views = [
        // Day records are plain JSON, read without a function: the app lists
        // every day of an edition as it starts.
        """
        CREATE TEMP VIEW days AS
          SELECT d.date AS date, r.payload AS payload
          FROM main.days d JOIN main.day_records r ON r.id = d.record
        """,
        """
        CREATE TEMP VIEW text_resources AS
          SELECT id, stable_key, kind, incipits_latin, hours_expand_payload(payload) AS payload
          FROM main.text_resources
        """,
        """
        CREATE TEMP VIEW scores AS
          SELECT id, hours_expand_payload(payload) AS payload FROM main.scores
        """,
        """
        CREATE TEMP VIEW recipes AS
          SELECT id, hours_recipe_header(shape, digest, payload) AS payload FROM main.recipes
        """,
        """
        CREATE TEMP VIEW recipe_sections AS
          SELECT r.id AS recipe_id, j.key AS position, j.value / \(scoreRadix) AS text_id,
                 NULLIF(j.value % \(scoreRadix), 0) AS score_id
          FROM main.recipes r
          JOIN main.recipe_section_pages p ON p.page = r.page
          JOIN json_each(hours_recipe_sections(p.page, p.payload, r.slot)) j
        """,
        """
        CREATE TEMP VIEW text_recipes AS
          SELECT l.text_id AS text_id, j.value AS recipe_id
          FROM main.text_recipe_lists l JOIN json_each(hours_id_list(l.payload)) j
        """,
        """
        CREATE TEMP VIEW \(recipeTitlesView) AS
          SELECT r.id AS recipe_id, o.observance_id AS observance_id,
                 o.title_latin AS title_latin, o.title_english AS title_english
          FROM main.recipes r JOIN main.recipe_observances o ON o.id = r.observance
        """
    ]

    /// The view that gives each recipe's observance as plain columns.
    static let recipeTitlesView = "recipe_titles"

    static func prepare(_ database: OpaquePointer, at url: URL) throws {
        guard let manifest = try metadata(database, key: "manifest"),
              let object = try JSONSerialization.jsonObject(with: Data(manifest.utf8)) as? [String: Any],
              let schema = object["schemaVersion"] as? Int else {
            throw invalid("Missing content manifest.")
        }
        let identity = try metadata(database, key: "shared_catalog")
        guard schema == storageSchema else {
            guard identity == nil else { throw invalid("Unexpected shared catalog in standalone content.") }
            return
        }
        guard let identity, identity.count == 64 else { throw invalid("Missing shared catalog identity.") }
        let resolver = try SharedContentResolver(
            url: url.deletingLastPathComponent().appendingPathComponent(catalogName),
            identity: identity,
            shapes: try recipeShapes(database)
        )
        try register("hours_expand_payload", arguments: 1, on: database, resolver: resolver) { context, arguments, resolver in
            guard let payload = blob(arguments[0]) else { throw invalid("Missing shared content payload.") }
            result(try resolver.decode(payload), in: context)
        }
        try register("hours_recipe_header", arguments: 3, on: database, resolver: resolver) { context, arguments, resolver in
            guard let payload = blob(arguments[2]) else { throw invalid("Missing recipe header.") }
            result(
                try resolver.recipeHeader(
                    shape: sqlite3_value_int64(arguments[0]),
                    digest: blob(arguments[1]),
                    payload: payload
                ),
                in: context
            )
        }
        try register("hours_recipe_sections", arguments: 3, on: database, resolver: resolver) { context, arguments, resolver in
            guard let payload = blob(arguments[1]) else { throw invalid("Missing recipe section page.") }
            result(
                try resolver.recipeSections(
                    page: sqlite3_value_int64(arguments[0]),
                    payload: payload,
                    slot: Int(sqlite3_value_int64(arguments[2]))
                ),
                in: context
            )
        }
        try register("hours_id_list", arguments: 1, on: database, resolver: resolver) { context, arguments, _ in
            guard let payload = blob(arguments[0]) else { throw invalid("Missing identifier list.") }
            result(try SharedContentResolver.identifierList(payload), in: context)
        }
        for sql in views {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw invalid(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private typealias Function = (OpaquePointer?, [OpaquePointer?], SharedContentResolver) throws -> Void

    /// Carries a function's body and the resolver it reads; SQLite owns it.
    private final class FunctionBox {
        let resolver: SharedContentResolver
        let body: Function
        init(resolver: SharedContentResolver, body: @escaping Function) {
            self.resolver = resolver
            self.body = body
        }
    }

    private static func register(
        _ name: String,
        arguments: Int32,
        on database: OpaquePointer,
        resolver: SharedContentResolver,
        body: @escaping Function
    ) throws {
        let box = Unmanaged.passRetained(FunctionBox(resolver: resolver, body: body)).toOpaque()
        // SQLite owns the box, including its destruction if registration fails.
        let status = sqlite3_create_function_v2(database, name, arguments, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            box, { context, count, arguments in
                guard let context, let state = sqlite3_user_data(context), let arguments else {
                    sqlite3_result_error(context, "Missing shared content function state", -1)
                    return
                }
                let box = Unmanaged<FunctionBox>.fromOpaque(state).takeUnretainedValue()
                do {
                    try box.body(context, (0..<Int(count)).map { arguments[$0] }, box.resolver)
                } catch {
                    sqlite3_result_error(context, error.localizedDescription, -1)
                }
            }, nil, nil, { pointer in
                if let pointer { Unmanaged<FunctionBox>.fromOpaque(pointer).release() }
            })
        guard status == SQLITE_OK else { throw invalid(String(cString: sqlite3_errmsg(database))) }
    }

    private static func blob(_ value: OpaquePointer?) -> Data? {
        guard sqlite3_value_type(value) != SQLITE_NULL, let bytes = sqlite3_value_blob(value) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_value_bytes(value)))
    }

    private static func result(_ data: Data, in context: OpaquePointer?) {
        data.withUnsafeBytes { buffer in
            sqlite3_result_blob(context, buffer.baseAddress, Int32(buffer.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    private static func result(_ text: String, in context: OpaquePointer?) {
        sqlite3_result_text(context, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    /// The key paths of each recipe header shape, in the order of its values.
    private static func recipeShapes(_ database: OpaquePointer) throws -> [Int64: [String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id, paths FROM main.recipe_shapes", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw invalid("Cannot read recipe header shapes.") }
        defer { sqlite3_finalize(statement) }
        var shapes: [Int64: [String]] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return shapes }
            guard step == SQLITE_ROW, let text = sqlite3_column_text(statement, 1),
                  let paths = try JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String] else {
                throw invalid("Invalid recipe header shape.")
            }
            shapes[sqlite3_column_int64(statement, 0)] = paths
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

private final class SharedSectionPage: NSObject {
    /// The sections of every recipe of the page in turn, each one integer
    /// (the text above the score; a section without chant has the score
    /// zero), and where each recipe's begin, with the end of the last.
    let sections: [Int64]
    let starts: [Int]

    /// From each recipe's text and score identifiers in turn.
    init(recipes: [[Int64]], page: Int64) throws {
        var sections: [Int64] = []
        sections.reserveCapacity(recipes.reduce(0) { $0 + $1.count } / 2)
        var starts = [0]
        starts.reserveCapacity(recipes.count + 1)
        for flat in recipes {
            guard flat.count.isMultiple(of: 2) else {
                throw SharedContentDatabase.invalid("Invalid recipe in section page \(page).")
            }
            for index in stride(from: 0, to: flat.count, by: 2) {
                let textID = flat[index], scoreID = flat[index + 1]
                guard textID >= 1, scoreID >= 0, scoreID < SharedContentDatabase.scoreRadix else {
                    throw SharedContentDatabase.invalid("Invalid section in page \(page).")
                }
                sections.append(textID * SharedContentDatabase.scoreRadix + scoreID)
            }
            starts.append(sections.count)
        }
        self.sections = sections
        self.starts = starts
    }

    var cost: Int { (sections.count + starts.count) * MemoryLayout<Int64>.stride }
}

/// Called synchronously by one SQLite connection; no global or cross-actor state.
private final class SharedContentResolver {
    private let database: OpaquePointer
    private let lookup: OpaquePointer
    private let shapes: [Int64: [String]]
    private let values = NSCache<NSNumber, SharedJSONValue>()
    private let payloads = NSCache<NSData, NSData>()
    private let pages = NSCache<NSNumber, SharedSectionPage>()

    init(url: URL, identity: String, shapes: [Int64: [String]]) throws {
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
        self.shapes = shapes
        // Bounded by its cost. A year's recipe headers and day records name
        // several thousand short strings between them (titles, seasons,
        // labels), and a count below that reads each from the catalog again.
        values.totalCostLimit = 8 * 1024 * 1024
        values.countLimit = 32_768
        // Bounded by its cost. The count admits the few thousand small day
        // records a perennial edition reads again for every date they serve.
        payloads.totalCostLimit = 16 * 1024 * 1024
        payloads.countLimit = 8_192
        // A page holds sixty-four recipes, about twenty-four kilobytes held
        // so. Reading an Hour reads one page; asking where a common text is
        // used reads every page of the edition (some six hundred), and a
        // cache that cannot hold them decodes each again and again.
        pages.totalCostLimit = 32 * 1024 * 1024
        pages.countLimit = 4_096
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

    /// A recipe header from the values of its shape's keys and its
    /// visible-content digest, as the standalone schema stores it.
    func recipeHeader(shape: Int64, digest: Data?, payload: Data) throws -> Data {
        guard let paths = shapes[shape] else {
            throw SharedContentDatabase.invalid("Missing recipe header shape \(shape).")
        }
        let object = try JSONSerialization.jsonObject(with: ContentPayloadCodec.decode(payload))
        guard let values = try expand(object) as? [Any] else {
            throw SharedContentDatabase.invalid("Invalid recipe header.")
        }
        var header: [String: Any] = [:]
        var observance: [String: Any]?
        var next = 0
        for path in paths {
            if path == "visibleContentDigest" {
                header[path] = digest.map { $0.map { String(format: "%02x", $0) }.joined() } ?? NSNull()
            } else if path.hasPrefix("observance{") {
                observance = [:]
            } else {
                guard next < values.count else {
                    throw SharedContentDatabase.invalid("A recipe header does not fit its shape.")
                }
                if path.hasPrefix("observance.") {
                    guard observance != nil else {
                        throw SharedContentDatabase.invalid("Invalid recipe header shape.")
                    }
                    observance?[String(path.dropFirst("observance.".count))] = values[next]
                } else {
                    header[path] = values[next]
                }
                next += 1
            }
        }
        guard next == values.count else {
            throw SharedContentDatabase.invalid("A recipe header does not fit its shape.")
        }
        if let observance { header["observance"] = observance }
        return try JSONSerialization.data(withJSONObject: header)
    }

    /// One recipe of a page as a JSON array of packed sections.
    func recipeSections(page: Int64, payload: Data, slot: Int) throws -> String {
        let key = NSNumber(value: page)
        let decoded: SharedSectionPage
        if let cached = pages.object(forKey: key) {
            decoded = cached
        } else {
            decoded = try SharedSectionPage(
                recipes: Self.integerArrays(ContentPayloadCodec.decode(payload)),
                page: page
            )
            pages.setObject(decoded, forKey: key, cost: decoded.cost)
        }
        guard slot >= 0, slot + 1 < decoded.starts.count else {
            throw SharedContentDatabase.invalid("Missing recipe \(slot) of section page \(page).")
        }
        let sections = decoded.sections[decoded.starts[slot]..<decoded.starts[slot + 1]]
        var text = "["
        text.reserveCapacity(sections.count * 13 + 2)
        for (index, section) in sections.enumerated() {
            if index > 0 { text.append(",") }
            text.append(String(section))
        }
        text.append("]")
        return text
    }

    /// Ascending identifiers, stored as the gaps between them, as a JSON array.
    static func identifierList(_ payload: Data) throws -> String {
        let arrays = try integerArrays(ContentPayloadCodec.decode(payload), nested: false)
        var previous: Int64 = 0
        var text = "["
        for (index, gap) in (arrays.first ?? []).enumerated() {
            guard gap >= 1 else { throw SharedContentDatabase.invalid("Invalid identifier list.") }
            previous += gap
            if index > 0 { text.append(",") }
            text.append(String(previous))
        }
        text.append("]")
        return text
    }

    /// Reads a JSON array of arrays of non-negative integers (or, unnested,
    /// one such array) without building Foundation objects for each number.
    private static func integerArrays(_ data: Data, nested: Bool = true) throws -> [[Int64]] {
        var result: [[Int64]] = []
        var current: [Int64] = []
        var number: Int64 = 0
        var hasDigits = false
        var depth = 0
        let innerDepth = nested ? 2 : 1
        func finishNumber() throws {
            guard hasDigits else { return }
            guard depth == innerDepth else { throw SharedContentDatabase.invalid("Invalid integer array.") }
            current.append(number)
            number = 0
            hasDigits = false
        }
        for byte in data {
            switch byte {
            case UInt8(ascii: "["):
                depth += 1
                guard depth <= innerDepth else { throw SharedContentDatabase.invalid("Invalid integer array.") }
                if depth == innerDepth { current = [] }
            case UInt8(ascii: "]"):
                try finishNumber()
                if depth == innerDepth { result.append(current) }
                depth -= 1
                guard depth >= 0 else { throw SharedContentDatabase.invalid("Invalid integer array.") }
            case UInt8(ascii: ","):
                try finishNumber()
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                let (product, overflowed) = number.multipliedReportingOverflow(by: 10)
                guard !overflowed else { throw SharedContentDatabase.invalid("Invalid integer array.") }
                number = product + Int64(byte - UInt8(ascii: "0"))
                hasDigits = true
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\t"), UInt8(ascii: "\r"):
                try finishNumber()
            default:
                throw SharedContentDatabase.invalid("Invalid integer array.")
            }
        }
        guard depth == 0, !hasDigits else { throw SharedContentDatabase.invalid("Invalid integer array.") }
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
