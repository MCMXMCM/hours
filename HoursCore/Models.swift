import Foundation

public struct LocalDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .hoursGregorian) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    public init?(iso8601: String) {
        let parts = iso8601.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var date: Date? {
        date(in: .hoursGregorian)
    }

    public func date(in calendar: Calendar) -> Date? {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )
    }

    /// The date Hours selects while following the current canonical hour.
    ///
    /// The preceding civil date remains active through Matins so the automatic
    /// Office date advances with Lauds at 4 a.m., rather than at midnight.
    public static func currentOfficeDay(
        at date: Date = Date(),
        calendar: Calendar = .hoursGregorian
    ) -> Self {
        let hour = calendar.component(.hour, from: date)
        guard hour < 4,
              let previousDay = calendar.date(
                  byAdding: .day,
                  value: -1,
                  to: date
              ) else {
            return Self(date, calendar: calendar)
        }
        return Self(previousDay, calendar: calendar)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public extension Calendar {
    static var hoursGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // A LocalDay is a civil date, so bridging to Date must use the user's
        // current zone. UTC midnight would display as the previous day west of
        // Greenwich and would corrupt "Pray this evening" selection.
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}

public enum OfficeHour: String, Codable, CaseIterable, Hashable, Sendable {
    case matins
    case lauds
    case prime
    case terce
    case sext
    case none
    case vespers
    case compline

    public var latinTitle: String {
        switch self {
        case .matins: "Ad Matutinum"
        case .lauds: "Ad Laudes"
        case .prime: "Ad Primam"
        case .terce: "Ad Tertiam"
        case .sext: "Ad Sextam"
        case .none: "Ad Nonam"
        case .vespers: "Ad Vesperas"
        case .compline: "Ad Completorium"
        }
    }

    public var latinName: String {
        switch self {
        case .matins: "Matutinum"
        case .lauds: "Laudes"
        case .prime: "Prima"
        case .terce: "Tertia"
        case .sext: "Sexta"
        case .none: "Nona"
        case .vespers: "Vesperae"
        case .compline: "Completorium"
        }
    }

    public var englishTitle: String {
        switch self {
        case .matins: "Matins"
        case .lauds: "Lauds"
        case .prime: "Prime"
        case .terce: "Terce"
        case .sext: "Sext"
        case .none: "None"
        case .vespers: "Vespers"
        case .compline: "Compline"
        }
    }

    public var customaryTimeRange: String {
        let range = customaryMinuteRange
        return "\(Self.timeLabel(for: range.start)) – "
            + Self.timeLabel(for: range.end)
    }

    public static func current(
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Self {
        let components = calendar.dateComponents(
            [.hour, .minute],
            from: date
        )
        let minuteOfDay = (components.hour ?? 0) * 60
            + (components.minute ?? 0)

        return allCases.first {
            $0.contains(minuteOfDay: minuteOfDay)
        } ?? .matins
    }

    private var customaryMinuteRange: (start: Int, end: Int) {
        switch self {
        case .matins:
            (0, 4 * 60)
        case .lauds:
            (4 * 60, 6 * 60)
        case .prime:
            (6 * 60, 8 * 60)
        case .terce:
            (8 * 60, 10 * 60)
        case .sext:
            (10 * 60, 13 * 60)
        case .none:
            (13 * 60, 16 * 60)
        case .vespers:
            (16 * 60, 20 * 60)
        case .compline:
            (20 * 60, 24 * 60)
        }
    }

    private func contains(minuteOfDay: Int) -> Bool {
        let range = customaryMinuteRange
        if range.start < range.end {
            return range.start <= minuteOfDay
                && minuteOfDay < range.end
        }
        return minuteOfDay >= range.start
            || minuteOfDay < range.end
    }

    private static func timeLabel(for minuteOfDay: Int) -> String {
        let normalizedMinute = minuteOfDay % (24 * 60)
        let hour24 = normalizedMinute / 60
        let minute = normalizedMinute % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "am" : "pm"

        guard minute != 0 else {
            return "\(hour12)\(suffix)"
        }
        return String(
            format: "%d:%02d%@",
            hour12,
            minute,
            suffix
        )
    }
}

public enum LiturgicalRank: String, Codable, Hashable, Sendable {
    case firstClass
    case secondClass
    case thirdClass
    case fourthClass

    public var displayName: String {
        switch self {
        case .firstClass: "I. classis"
        case .secondClass: "II. classis"
        case .thirdClass: "III. classis"
        case .fourthClass: "IV. classis"
        }
    }
}

public enum LiturgicalColor: String, Codable, Hashable, Sendable {
    case white
    case red
    case green
    case violet
    case rose
    case black
}

public enum EveningContext: String, Codable, Hashable, Sendable {
    case firstVespers
    case secondVespers
    case ferialVespers

    public var displayName: String {
        switch self {
        case .firstVespers: "First Vespers"
        case .secondVespers: "Second Vespers"
        case .ferialVespers: "Vespers"
        }
    }
}

public struct Commemoration: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let titleLatin: String
    public let titleEnglish: String?

    public init(id: String, titleLatin: String, titleEnglish: String? = nil) {
        self.id = id
        self.titleLatin = titleLatin
        self.titleEnglish = titleEnglish
    }
}

public struct LiturgicalDay: Codable, Hashable, Sendable, Identifiable {
    public var id: LocalDay { date }
    public let date: LocalDay
    public let observanceID: String
    public let titleLatin: String
    public let titleEnglish: String?
    public let rank: LiturgicalRank?
    public let color: LiturgicalColor?
    public let season: String
    public let eveningContext: EveningContext?
    public let commemorations: [Commemoration]
    public let sourceVersion: String

    public init(
        date: LocalDay,
        observanceID: String,
        titleLatin: String,
        titleEnglish: String? = nil,
        rank: LiturgicalRank? = nil,
        color: LiturgicalColor? = nil,
        season: String,
        eveningContext: EveningContext? = nil,
        commemorations: [Commemoration] = [],
        sourceVersion: String = "Rubrics 1960 - 1960"
    ) {
        self.date = date
        self.observanceID = observanceID
        self.titleLatin = titleLatin
        self.titleEnglish = titleEnglish
        self.rank = rank
        self.color = color
        self.season = season
        self.eveningContext = eveningContext
        self.commemorations = commemorations
        self.sourceVersion = sourceVersion
    }
}

public enum OfficeSectionKind: String, Codable, Hashable, Sendable {
    case opening
    case invitatory
    case prayer
    case rubric
    case reading
    case absolution
    case blessing
    case psalm
    case antiphon
    case chapter
    case responsory
    case hymn
    case versicle
    case canticle
    case collect
    case preces
    case conclusion
    case marianAntiphon
}

public enum ChantReviewStatus: String, Codable, Hashable, Sendable {
    case exactMatch
    case humanReviewed
    case generatedFormula
    case ambiguous
    case missing

    public var isReleaseReady: Bool {
        switch self {
        case .exactMatch, .humanReviewed, .generatedFormula: true
        case .ambiguous, .missing: false
        }
    }
}

public enum ChantNotationModifier: String, Codable, Hashable, Sendable {
    case mora
    case episema
    case quilisma
    case liquescent
    case flat
    case natural
    case sharp
    case phraseBoundary
}

public struct ChantClef: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case c
        case f
    }

    public let kind: Kind
    public let line: Int
    public let flattensB: Bool

    public init(kind: Kind, line: Int, flattensB: Bool = false) {
        self.kind = kind
        self.line = line
        self.flattensB = flattensB
    }
}

public struct ChantEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let phraseID: String
    public let syllableID: String
    public let syllable: String
    public let relativePitch: Int
    public let durationWeight: Double
    public let modifiers: [ChantNotationModifier]
    public let clef: ChantClef?

    private enum CodingKeys: String, CodingKey {
        case id
        case phraseID
        case syllableID
        case syllable
        case relativePitch
        case durationWeight
        case modifiers
        case clef
    }

    private enum CompactKeys: String, CodingKey {
        case id = "i"
        case phraseID = "p"
        case syllableID = "y"
        case syllable = "s"
        case relativePitch = "n"
        case durationWeight = "d"
        case modifiers = "m"
        case clef = "c"
    }

    private struct CompactClef: Codable {
        let kind: ChantClef.Kind
        let line: Int
        let flattensB: Bool

        private enum CodingKeys: String, CodingKey {
            case kind = "k"
            case line = "l"
            case flattensB = "b"
        }
    }

    public init(
        id: String,
        phraseID: String,
        syllableID: String,
        syllable: String,
        relativePitch: Int,
        durationWeight: Double = 1,
        modifiers: [ChantNotationModifier] = [],
        clef: ChantClef? = nil
    ) {
        self.id = id
        self.phraseID = phraseID
        self.syllableID = syllableID
        self.syllable = syllable
        self.relativePitch = relativePitch
        self.durationWeight = durationWeight
        self.modifiers = modifiers
        self.clef = clef
    }

    public init(from decoder: any Decoder) throws {
        let verbose = try decoder.container(keyedBy: CodingKeys.self)
        if verbose.contains(.id) {
            id = try verbose.decode(String.self, forKey: .id)
            phraseID = try verbose.decode(String.self, forKey: .phraseID)
            syllableID = try verbose.decode(String.self, forKey: .syllableID)
            syllable = try verbose.decode(String.self, forKey: .syllable)
            relativePitch = try verbose.decode(Int.self, forKey: .relativePitch)
            durationWeight = try verbose.decode(Double.self, forKey: .durationWeight)
            modifiers = try verbose.decode([ChantNotationModifier].self, forKey: .modifiers)
            clef = try verbose.decodeIfPresent(ChantClef.self, forKey: .clef)
            return
        }

        let compact = try decoder.container(keyedBy: CompactKeys.self)
        id = try compact.decode(String.self, forKey: .id)
        phraseID = try compact.decode(String.self, forKey: .phraseID)
        syllableID = try compact.decode(String.self, forKey: .syllableID)
        syllable = try compact.decode(String.self, forKey: .syllable)
        relativePitch = try compact.decode(Int.self, forKey: .relativePitch)
        durationWeight = try compact.decode(Double.self, forKey: .durationWeight)
        modifiers = try compact.decode([ChantNotationModifier].self, forKey: .modifiers)
        if let storedClef = try compact.decodeIfPresent(CompactClef.self, forKey: .clef) {
            clef = ChantClef(
                kind: storedClef.kind,
                line: storedClef.line,
                flattensB: storedClef.flattensB
            )
        } else {
            clef = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(phraseID, forKey: .phraseID)
        try container.encode(syllableID, forKey: .syllableID)
        try container.encode(syllable, forKey: .syllable)
        try container.encode(relativePitch, forKey: .relativePitch)
        try container.encode(durationWeight, forKey: .durationWeight)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(clef, forKey: .clef)
    }
}

public struct ChantTimeline: Codable, Hashable, Sendable {
    public let events: [ChantEvent]

    public init(events: [ChantEvent]) {
        self.events = events
    }

    public var phraseIDs: [String] {
        events.reduce(into: []) { result, event in
            if result.last != event.phraseID {
                result.append(event.phraseID)
            }
        }
    }

    public var totalDurationWeight: Double {
        events.reduce(0) { $0 + $1.durationWeight }
    }
}

public struct ChantProvenance: Codable, Hashable, Sendable {
    public let collection: String
    public let sourceBook: String
    public let sourceURL: URL?
    public let license: String
    public let snapshot: String

    public init(
        collection: String,
        sourceBook: String,
        sourceURL: URL? = nil,
        license: String,
        snapshot: String
    ) {
        self.collection = collection
        self.sourceBook = sourceBook
        self.sourceURL = sourceURL
        self.license = license
        self.snapshot = snapshot
    }
}

public struct ChantScore: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let incipit: String
    public let gabc: String
    public let mode: String?
    public let reviewStatus: ChantReviewStatus
    public let provenance: ChantProvenance
    public let timeline: ChantTimeline

    public init(
        id: String,
        incipit: String,
        gabc: String,
        mode: String? = nil,
        reviewStatus: ChantReviewStatus,
        provenance: ChantProvenance,
        timeline: ChantTimeline
    ) {
        self.id = id
        self.incipit = incipit
        self.gabc = gabc
        self.mode = mode
        self.reviewStatus = reviewStatus
        self.provenance = provenance
        self.timeline = timeline
    }
}

public struct OfficeSection: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: OfficeSectionKind
    public let title: String
    public let rubric: String?
    public let latin: String
    public let english: String?
    public let chant: ChantScore?

    public init(
        id: String,
        kind: OfficeSectionKind,
        title: String,
        rubric: String? = nil,
        latin: String,
        english: String? = nil,
        chant: ChantScore? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rubric = rubric
        self.latin = latin
        self.english = english
        self.chant = chant
    }

    public var userFacingRubric: String? {
        guard let rubric,
              let collection = chant?.provenance.collection else {
            return rubric
        }
        if rubric == collection || rubric.hasPrefix("\(collection) · ") {
            return nil
        }
        return rubric
    }
}

public struct OfficeDocument: Codable, Hashable, Sendable, Identifiable {
    public enum Format: String, Codable, Hashable, Sendable {
        case authoritativeOrdered
        case legacyReconstructed
        case contentUnavailable
    }

    public let id: String
    public let date: LocalDay
    public let hour: OfficeHour
    public let titleLatin: String
    public let titleEnglish: String?
    public let contextLabel: String
    public let sourceVersion: String
    public let format: Format?
    public let visibleContentDigest: String?
    public let observance: OfficeObservance?
    public let sections: [OfficeSection]

    public init(
        id: String,
        date: LocalDay,
        hour: OfficeHour,
        titleLatin: String,
        titleEnglish: String? = nil,
        contextLabel: String,
        sourceVersion: String = "Rubrics 1960 - 1960",
        format: Format? = nil,
        visibleContentDigest: String? = nil,
        observance: OfficeObservance? = nil,
        sections: [OfficeSection]
    ) {
        self.id = id
        self.date = date
        self.hour = hour
        self.titleLatin = titleLatin
        self.titleEnglish = titleEnglish
        self.contextLabel = contextLabel
        self.sourceVersion = sourceVersion
        self.format = format
        self.visibleContentDigest = visibleContentDigest
        self.observance = observance
        self.sections = sections
    }

    public var playableScores: [ChantScore] {
        sections.compactMap(\.chant).filter { !$0.timeline.events.isEmpty }
    }
}

public struct OfficeObservance: Codable, Hashable, Sendable, Identifiable {
    public let observanceID: String
    public var id: String { observanceID }
    public let titleLatin: String
    public let titleEnglish: String?
    public let rank: LiturgicalRank?
    public let color: LiturgicalColor?
    public let season: String?
    public let eveningContext: EveningContext?
    public let commemorations: [Commemoration]

    public init(
        observanceID: String,
        titleLatin: String,
        titleEnglish: String? = nil,
        rank: LiturgicalRank? = nil,
        color: LiturgicalColor? = nil,
        season: String? = nil,
        eveningContext: EveningContext? = nil,
        commemorations: [Commemoration] = []
    ) {
        self.observanceID = observanceID
        self.titleLatin = titleLatin
        self.titleEnglish = titleEnglish
        self.rank = rank
        self.color = color
        self.season = season
        self.eveningContext = eveningContext
        self.commemorations = commemorations
    }
}

public struct ContentSourcePin: Codable, Hashable, Sendable {
    public let name: String
    public let url: URL
    public let revision: String
    public let license: String
    public let checksum: String

    public init(
        name: String,
        url: URL,
        revision: String,
        license: String,
        checksum: String
    ) {
        self.name = name
        self.url = url
        self.revision = revision
        self.license = license
        self.checksum = checksum
    }
}

public struct ContentCoverage: Codable, Hashable, Sendable {
    public let startDate: LocalDay
    public let endDate: LocalDay
    public let expectedOfficeCount: Int
    public let generatedOfficeCount: Int
    public let authoritativeOfficeCount: Int?
    public let unresolvedScoreCount: Int
    public let ambiguousScoreCount: Int
    public let isSample: Bool

    public init(
        startDate: LocalDay,
        endDate: LocalDay,
        expectedOfficeCount: Int,
        generatedOfficeCount: Int,
        authoritativeOfficeCount: Int? = nil,
        unresolvedScoreCount: Int,
        ambiguousScoreCount: Int,
        isSample: Bool
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.expectedOfficeCount = expectedOfficeCount
        self.generatedOfficeCount = generatedOfficeCount
        self.authoritativeOfficeCount = authoritativeOfficeCount
        self.unresolvedScoreCount = unresolvedScoreCount
        self.ambiguousScoreCount = ambiguousScoreCount
        self.isSample = isSample
    }

    public var isReleaseReady: Bool {
        !isSample
            && expectedOfficeCount == generatedOfficeCount
            && authoritativeOfficeCount == expectedOfficeCount
            && unresolvedScoreCount == 0
            && ambiguousScoreCount == 0
    }
}

public struct ContentManifest: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let corpusVersion: String
    public let minimumAppVersion: String
    public let createdAt: Date
    public let rubrics: String
    public let packSHA256: String
    public let packURL: URL?
    public let signature: String
    public let sources: [ContentSourcePin]
    public let coverage: ContentCoverage

    public init(
        schemaVersion: Int,
        corpusVersion: String,
        minimumAppVersion: String,
        createdAt: Date,
        rubrics: String,
        packSHA256: String,
        packURL: URL? = nil,
        signature: String,
        sources: [ContentSourcePin],
        coverage: ContentCoverage
    ) {
        self.schemaVersion = schemaVersion
        self.corpusVersion = corpusVersion
        self.minimumAppVersion = minimumAppVersion
        self.createdAt = createdAt
        self.rubrics = rubrics
        self.packSHA256 = packSHA256
        self.packURL = packURL
        self.signature = signature
        self.sources = sources
        self.coverage = coverage
    }

    public var signingPayload: Data {
        Data(
            "\(schemaVersion)|\(corpusVersion)|\(minimumAppVersion)|\(packSHA256)"
                .utf8
        )
    }
}
