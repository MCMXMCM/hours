import Foundation

/// The parts of the Mass as search finds them: every text of an edition's
/// Missal, ordinary and proper, with the chant it is sung to and the
/// Masses that say it. The Missal is searched in memory: an index of its
/// texts in the database would take more room in the bundle than the
/// Missal has left, and the texts are few beside the Office's.
///
/// A text the Missal keeps under several titles or rubrics is one result.
/// Each part of the Ordinary the Kyriale sets is one result whatever its
/// lines' marks (`OrdinaryPart`), offering every setting of the Kyriale.
public enum MassPartSearch {
    /// The beginning of the identifier of every part of the Mass a search
    /// finds, by which it is told from the Office's.
    public static let idPrefix = "missa:"
    /// The beginning of the identifier of a part of the Ordinary the Kyriale
    /// sets, which offers each of its settings.
    public static let ordinaryIDPrefix = "missa:ordinary:"
}

/// A part of the Ordinary as the Kyriale sets it, by the words it sings:
/// the Agnus Dei of the Mass for the dead, which asks rest for them, is a
/// part of its own, as are the three ways of dismissing the people.
public enum OrdinaryPart: String, Codable, CaseIterable, Hashable, Sendable {
    case kyrie
    case gloria
    case credo
    case sanctus
    case agnusDei
    case agnusDeiDefunctorum
    case ite
    case benedicamus
    case requiescant
}

/// The parts of the Mass a search looks among.
public struct MassPartFilter: Hashable, Sendable {
    /// The kinds of section; nil for every kind.
    public let kinds: Set<OfficeSectionKind>?
    /// Of the Ordinary, or proper to the day; nil for either.
    public let ordinary: Bool?
    /// Only the parts that are sung.
    public let requiresScore: Bool

    public init(
        kinds: Set<OfficeSectionKind>? = nil,
        ordinary: Bool? = nil,
        requiresScore: Bool = false
    ) {
        self.kinds = kinds
        self.ordinary = ordinary
        self.requiresScore = requiresScore
    }

    public static let everyPart = MassPartFilter()
}

/// A text of the Missal, as the search reads it.
struct MissalSearchText {
    let id: Int
    let kind: OfficeSectionKind
    let title: String
    let titleEnglish: String?
    let rubric: String?
    let rubricEnglish: String?
    let latin: String
    let english: String?
    let ordinary: Bool
    /// The words of its Latin as search compares them (`MassPartIndex.words`).
    let latinWords: [UInt8]

    init(
        id: Int,
        kind: OfficeSectionKind,
        title: String,
        titleEnglish: String?,
        rubric: String?,
        rubricEnglish: String?,
        latin: String,
        english: String?,
        ordinary: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.titleEnglish = titleEnglish
        self.rubric = rubric
        self.rubricEnglish = rubricEnglish
        self.latin = latin
        self.english = english
        self.ordinary = ordinary
        latinWords = MassPartIndex.words([latin], latin: true)
    }
}

/// A part of the Mass that search finds: one text, or several that print
/// the same words, or a part of the Ordinary.
struct MassPartEntry {
    let id: String
    let kind: OfficeSectionKind
    let ordinary: Bool
    let part: OrdinaryPart?
    let title: String
    let titleEnglish: String?
    let rubric: String?
    let rubricEnglish: String?
    let latin: String
    let english: String?
    /// The words a sung part opens with, as the Office's chants have their
    /// incipits; empty for a part that is not sung.
    let incipit: String
    let textIDs: [Int]
    /// The Missal's scores of its texts, by their identifiers in order.
    let scoreIDs: [Int]
    let isSung: Bool
    /// The words of each language's fields, each between spaces, as the
    /// search compares them (`MassPartIndex.words`).
    let latinWords: [UInt8]
    let englishWords: [UInt8]
    let length: Int
}

/// Every part of the Mass of an edition's Missal, as search finds them.
struct MassPartIndex {
    let entries: [MassPartEntry]
    private let entryIndices: [String: Int]
    /// Each text's sections in the Missal: the Mass that says it and the
    /// chant it is sung to there.
    let uses: [Int: [(mass: Int, score: Int?)]]

    /// English names a part of the Ordinary is known by that its own
    /// fields do not give.
    private static let englishAliases: [OrdinaryPart: [String]] = [
        .credo: ["Nicene Creed"]
    ]

    /// - Parameters:
    ///   - texts: every text of the Missal.
    ///   - sections: each Mass's sections, by the Mass's identifier.
    ///   - kyrialeParts: the parts of the Ordinary the Kyriale has
    ///     settings for.
    init(
        texts: [MissalSearchText],
        sections: [Int: [(text: Int, score: Int?)]],
        kyrialeParts: Set<OrdinaryPart>
    ) {
        var uses: [Int: [(mass: Int, score: Int?)]] = [:]
        for mass in sections.keys.sorted() {
            for section in sections[mass] ?? [] {
                uses[section.text, default: []].append((mass, section.score))
            }
        }
        var groups: [String: [MissalSearchText]] = [:]
        var order: [String] = []
        for text in texts.sorted(by: { $0.id < $1.id }) {
            guard !text.latin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(text.english ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let key = Self.ordinaryPart(of: text).map { "ordinary:\($0.rawValue)" }
                ?? "\(text.kind.rawValue):\(Self.stableHash(Self.withoutMarks(text.latinWords)))"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(text)
        }
        var entries: [MassPartEntry] = []
        entries.reserveCapacity(order.count)
        for key in order {
            guard let group = groups[key] else { continue }
            // The text said most often stands for the rest.
            let shown = group.max { left, right in
                let leftUses = uses[left.id]?.count ?? 0
                let rightUses = uses[right.id]?.count ?? 0
                if leftUses != rightUses { return leftUses < rightUses }
                return left.id > right.id
            } ?? group[0]
            let part = Self.ordinaryPart(of: shown)
            let scoreIDs = Set(group.flatMap { text in
                (uses[text.id] ?? []).compactMap(\.score)
            }).sorted()
            let title: String
            let titleEnglish: String?
            switch part {
            case .ite:
                (title, titleEnglish) = ("Ite, missa est", "Dismissal")
            case .benedicamus:
                (title, titleEnglish) = ("Benedicamus Domino", "Dismissal")
            case .requiescant:
                (title, titleEnglish) = ("Requiescant in pace", "Dismissal")
            default:
                (title, titleEnglish) = (shown.title, shown.titleEnglish)
            }
            let isSung = !scoreIDs.isEmpty || part.map(kyrialeParts.contains) == true
            let incipit = part != nil ? title : isSung ? Self.opening(of: shown.latin) : ""
            let english = [titleEnglish, shown.rubricEnglish, shown.english]
                + (part.flatMap { Self.englishAliases[$0] } ?? []).map(Optional.some)
            entries.append(MassPartEntry(
                id: "\(MassPartSearch.idPrefix)\(key)",
                kind: shown.kind,
                ordinary: part != nil || shown.ordinary,
                part: part,
                title: title,
                titleEnglish: titleEnglish,
                rubric: shown.rubric,
                rubricEnglish: shown.rubricEnglish,
                latin: shown.latin,
                english: shown.english,
                incipit: incipit,
                textIDs: group.map(\.id),
                scoreIDs: scoreIDs,
                isSung: isSung,
                latinWords: Self.words([title, shown.rubric, incipit], latin: true) + shown.latinWords,
                englishWords: Self.words(english, latin: false),
                length: shown.latin.count + (shown.english?.count ?? 0)
            ))
        }
        self.entries = entries
        entryIndices = Dictionary(
            entries.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        self.uses = uses
    }

    func entry(_ id: String) -> MassPartEntry? {
        entryIndices[id].map { entries[$0] }
    }

    /// The parts whose fields hold every word of the query, each at the
    /// beginning of a word of theirs as the Office's index finds it: by how
    /// nearly each answers the query as a phrase, then the shorter first.
    func search(
        query: String,
        language: LiturgicalSearchLanguage,
        filter: MassPartFilter,
        limit: Int
    ) -> [LiturgicalSearchHit] {
        let tokens = query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !tokens.isEmpty else { return [] }
        let latinTokens = tokens.map { Array(" \(SQLiteContentRepository.searchNormalized($0, latin: true))".utf8) }
        let englishTokens = tokens.map { Array(" \(SQLiteContentRepository.searchNormalized($0, latin: false))".utf8) }
        var found: [(rank: Int, entry: MassPartEntry, hit: LiturgicalSearchHit)] = []
        for entry in entries {
            if let kinds = filter.kinds, !kinds.contains(entry.kind) { continue }
            if let ordinary = filter.ordinary, ordinary != entry.ordinary { continue }
            if filter.requiresScore, !entry.isSung { continue }
            let inLatin = language != .english
                && latinTokens.allSatisfy { Self.contains(entry.latinWords, $0) }
            let inEnglish = language != .latin && !inLatin
                && englishTokens.allSatisfy { Self.contains(entry.englishWords, $0) }
            guard inLatin || inEnglish else { continue }
            let shownIn: LiturgicalSearchLanguage = language == .all
                ? (inLatin ? .latin : .english)
                : language
            let rank = SQLiteContentRepository.searchPhraseRank(
                title: entry.title,
                titleEnglish: entry.titleEnglish,
                latin: entry.latin,
                english: entry.english,
                incipits: entry.incipit,
                query: query,
                language: shownIn
            )
            found.append((rank, entry, LiturgicalSearchHit(
                id: entry.id,
                kind: entry.kind,
                titleLatin: entry.title,
                titleEnglish: entry.titleEnglish,
                snippet: SQLiteContentRepository.searchSnippet(
                    latin: entry.latin,
                    english: entry.english,
                    incipits: entry.incipit,
                    query: query,
                    language: shownIn
                ),
                snippetLanguage: shownIn,
                hasScoredRealizations: entry.isSung,
                rank: rank
            )))
        }
        return found.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            if left.entry.length != right.entry.length { return left.entry.length < right.entry.length }
            return left.entry.id < right.entry.id
        }
        .prefix(max(1, min(limit, 50)))
        .map(\.hit)
    }

    /// The part of the Ordinary a text is, by its kind and the words it
    /// begins with; nil for a text proper to the day, or one of the
    /// Ordinary the Kyriale does not set.
    static func ordinaryPart(of text: MissalSearchText) -> OrdinaryPart? {
        switch text.kind {
        case .kyrie: return .kyrie
        case .gloria: return .gloria
        case .credo: return .credo
        case .sanctus: return .sanctus
        case .agnusDei:
            return contains(text.latinWords, Array(" requiem ".utf8)) ? .agnusDeiDefunctorum : .agnusDei
        case .dismissal:
            let words = String(decoding: withoutMarks(text.latinWords), as: UTF8.self)
            if words.hasPrefix(" ite ") { return .ite }
            if words.hasPrefix(" benedicamus ") { return .benedicamus }
            if words.hasPrefix(" requiescant ") { return .requiescant }
            return nil
        default:
            return nil
        }
    }

    /// The words of a Latin text as search compares them (`words`),
    /// without its lines' marks (℣., ℟., and the server's S., M. and P.),
    /// which tell a Mass's lines apart and not its texts.
    static func withoutMarks(_ words: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(words.count)
        var index = 0
        while index < words.count {
            // A mark is a word of one letter, between spaces.
            if words[index] == 0x20, index + 2 < words.count, words[index + 2] == 0x20,
               [0x73, 0x6d, 0x70, 0x76, 0x72].contains(words[index + 1]) {
                index += 2
                continue
            }
            result.append(words[index])
            index += 1
        }
        return result
    }

    /// The words a sung part opens with: to the first mark of punctuation,
    /// its lines' marks left out.
    static func opening(of latin: String) -> String {
        let text = latin
            .replacingOccurrences(of: #"^\s*(?:[℣℟]\.?|[SMPVR]\.)\s*"#, with: "", options: .regularExpression)
        let end = text.firstIndex { ",.:;!?\n".contains($0) } ?? text.endIndex
        return text[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words of the fields, normalized as the Office's search
    /// normalizes them (`searchNormalized`), each between spaces: a query's
    /// word, with a space before it, is found at the beginning of a word.
    static func words(_ fields: [String?], latin: Bool) -> [UInt8] {
        let normalized = SQLiteContentRepository.searchNormalized(
            fields.compactMap { $0 }.joined(separator: " "),
            latin: latin
        )
        var bytes: [UInt8] = [0x20]
        bytes.reserveCapacity(normalized.utf8.count + 2)
        var pendingSpace = false
        for scalar in normalized.unicodeScalars {
            let isOfAWord: Bool
            if scalar.isASCII {
                // Normalized, a letter is lower case.
                let value = scalar.value
                isOfAWord = (0x61...0x7a).contains(value) || (0x30...0x39).contains(value)
                    || (0x41...0x5a).contains(value)
            } else {
                isOfAWord = scalar.properties.isAlphabetic || scalar.properties.numericType != nil
            }
            if isOfAWord {
                if pendingSpace {
                    bytes.append(0x20)
                    pendingSpace = false
                }
                if scalar.isASCII {
                    bytes.append(UInt8(scalar.value))
                } else {
                    UTF8.encode(scalar) { bytes.append($0) }
                }
            } else if bytes.count > 1 {
                pendingSpace = true
            }
        }
        bytes.append(0x20)
        return bytes
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return needle.isEmpty }
        return haystack.withUnsafeBytes { hay in
            needle.withUnsafeBytes { word in
                memmem(hay.baseAddress, hay.count, word.baseAddress, word.count) != nil
            }
        }
    }

    /// FNV-1a over the bytes, in hexadecimal: the same in every launch, as
    /// a recent result's identifier must be.
    static func stableHash(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
