import Foundation

public struct GregorianSourceRange: Codable, Hashable, Sendable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

public enum GregorianClefKind: String, Codable, Hashable, Sendable {
    case c
    case f
}

public struct GregorianClef: Codable, Hashable, Sendable {
    public let kind: GregorianClefKind
    public let line: Int
    public let flattensB: Bool

    public init(kind: GregorianClefKind, line: Int, flattensB: Bool = false) {
        self.kind = kind
        self.line = line
        self.flattensB = flattensB
    }
}

public enum GregorianAccidental: String, Codable, Hashable, Sendable {
    case flat
    case natural
    case sharp
}

public enum GregorianDivision: String, Codable, Hashable, Sendable {
    case minima
    case minor
    case major
    case final
}

public enum GregorianNoteShape: String, Codable, Hashable, Sendable {
    case punctum
    case virga
    case quilisma
    case liquescent
    case inclinatum
    case oriscus
    case stropha
}

public enum GregorianLiquescence: String, Codable, Hashable, Sendable {
    case none
    case small
    case ascending
    case descending
}

public enum GregorianEpisemaPosition: String, Codable, Hashable, Sendable {
    case above
    case below
}

public struct GregorianAccidentalMark: Codable, Hashable, Sendable {
    public let kind: GregorianAccidental
    public let pitch: Int
    public let sourceRange: GregorianSourceRange

    public init(
        kind: GregorianAccidental,
        pitch: Int,
        sourceRange: GregorianSourceRange
    ) {
        self.kind = kind
        self.pitch = pitch
        self.sourceRange = sourceRange
    }
}

/// Semantic neume families used by the native compositor. These deliberately
/// mirror Exsurge's named-neume layer rather than treating a neume as an
/// arbitrary row of noteheads.
public enum GregorianNeumeForm: String, Codable, Hashable, Sendable {
    case apostropha
    case bivirga
    case trivirga
    case climacus
    case clivis
    case ancus
    case distropha
    case oriscus
    case pesQuassus
    case pesSubpunctis
    case podatus
    case porrectus
    case porrectusFlexus
    case punctaInclinata
    case punctum
    case salicus
    case salicusFlexus
    case scandicus
    case scandicusFlexus
    case torculus
    case torculusResupinus
    case torculusResupinusFlexus
    case tristropha
    case virga
}

public enum GregorianLyricStyle: String, Codable, Hashable, Sendable {
    case regular
    case preparatory
    case accented
    case rubric
}

public struct GregorianNote: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let pitch: Int
    public let relativePitch: Int
    public let shape: GregorianNoteShape
    public let accidental: GregorianAccidental?
    public let hasMora: Bool
    public let hasEpisema: Bool
    public let moraCount: Int
    public let episemaPosition: GregorianEpisemaPosition
    public let liquescence: GregorianLiquescence
    public let isCavum: Bool
    public let hasIctus: Bool
    public let sourceRange: GregorianSourceRange

    public init(
        id: String,
        pitch: Int,
        relativePitch: Int,
        shape: GregorianNoteShape,
        accidental: GregorianAccidental?,
        hasMora: Bool,
        hasEpisema: Bool,
        moraCount: Int = 0,
        episemaPosition: GregorianEpisemaPosition = .above,
        liquescence: GregorianLiquescence = .none,
        isCavum: Bool = false,
        hasIctus: Bool = false,
        sourceRange: GregorianSourceRange
    ) {
        self.id = id
        self.pitch = pitch
        self.relativePitch = relativePitch
        self.shape = shape
        self.accidental = accidental
        self.hasMora = hasMora
        self.hasEpisema = hasEpisema
        self.moraCount = max(moraCount, hasMora ? 1 : 0)
        self.episemaPosition = episemaPosition
        self.liquescence = liquescence
        self.isCavum = isCavum
        self.hasIctus = hasIctus
        self.sourceRange = sourceRange
    }
}

public struct GregorianNeume: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let syllableID: String
    public let lyric: String
    public let lyricStyle: GregorianLyricStyle
    public let startsWord: Bool
    public let notes: [GregorianNote]
    public let form: GregorianNeumeForm
    public let sourceRange: GregorianSourceRange

    public var eventIDs: [String] {
        notes.map(\.id)
    }

    public init(
        id: String,
        syllableID: String,
        lyric: String,
        lyricStyle: GregorianLyricStyle = .regular,
        startsWord: Bool,
        notes: [GregorianNote],
        form: GregorianNeumeForm? = nil,
        sourceRange: GregorianSourceRange
    ) {
        self.id = id
        self.syllableID = syllableID
        self.lyric = lyric
        self.lyricStyle = lyricStyle
        self.startsWord = startsWord
        self.notes = notes
        self.form = form ?? GregorianNeumeClassifier.classify(notes)
        self.sourceRange = sourceRange
    }
}

public struct GregorianLyricMark: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        "lyric-mark-\(sourceRange.lowerBound)-\(sourceRange.upperBound)"
    }

    public let text: String
    public let style: GregorianLyricStyle
    public let startsWord: Bool
    public let sourceRange: GregorianSourceRange

    public init(
        text: String,
        style: GregorianLyricStyle,
        startsWord: Bool,
        sourceRange: GregorianSourceRange
    ) {
        self.text = text
        self.style = style
        self.startsWord = startsWord
        self.sourceRange = sourceRange
    }
}

public enum GregorianNotationElement: Codable, Hashable, Sendable {
    case clef(GregorianClef)
    case accidental(GregorianAccidentalMark)
    case neume(GregorianNeume)
    case lyricMark(GregorianLyricMark)
    case division(GregorianDivision)
    case forcedBreak
}

public struct GregorianScore: Codable, Hashable, Sendable {
    public let elements: [GregorianNotationElement]

    public init(elements: [GregorianNotationElement]) {
        self.elements = elements
    }

    public var neumes: [GregorianNeume] {
        elements.compactMap { element in
            guard case let .neume(neume) = element else { return nil }
            return neume
        }
    }

    public var eventIDs: [String] {
        neumes.flatMap(\.eventIDs)
    }
}

public enum GregorianScoreParserError: Error, Equatable, LocalizedError, Sendable {
    case missingBody
    case unterminatedNotation(offset: Int)
    case invalidClef(String, offset: Int)
    case unsupportedToken(String, offset: Int)
    case tooManyNotationNotes(offset: Int)
    case timelineMismatch(expected: Int, parsed: Int)
    case eventSyllableMismatch(eventID: String)

    public var errorDescription: String? {
        switch self {
        case .missingBody:
            "The GABC score does not contain a notation body."
        case let .unterminatedNotation(offset):
            "The GABC notation beginning at offset \(offset) is not closed."
        case let .invalidClef(token, offset):
            "Invalid clef \(token) at offset \(offset)."
        case let .unsupportedToken(token, offset):
            "Unsupported GABC token \(token) at offset \(offset)."
        case let .tooManyNotationNotes(offset):
            "The notation contains more notes than its compiled timeline near offset \(offset)."
        case let .timelineMismatch(expected, parsed):
            "The compiled timeline contains \(expected) notes but the notation contains \(parsed)."
        case let .eventSyllableMismatch(eventID):
            "Timeline event \(eventID) is assigned to a different syllable than its neume."
        }
    }
}

public enum GregorianScoreParser {
    public static func parse(gabc: String, timeline: ChantTimeline) throws -> GregorianScore {
        guard let bodyRange = gabc.range(of: "%%") else {
            throw GregorianScoreParserError.missingBody
        }

        let body = String(gabc[bodyRange.upperBound...])
            // In GABC, a single percent sign begins a comment through the end
            // of its line. Preserve the newline so surrounding lyric fragments
            // cannot be joined accidentally.
            .replacingOccurrences(
                of: #"%[^\r\n]*"#,
                with: "",
                options: .regularExpression
            )
        var elements: [GregorianNotationElement] = []
        var cursor = body.startIndex
        var eventIndex = 0
        var sourceOffset = 0

        while let open = body[cursor...].firstIndex(of: "(") {
            let lyricSource = String(body[cursor..<open])
            guard let close = body[open...].firstIndex(of: ")") else {
                throw GregorianScoreParserError.unterminatedNotation(
                    offset: body.distance(from: body.startIndex, to: open)
                )
            }

            let notationStart = body.index(after: open)
            let notation = String(body[notationStart..<close])
            let groupOffset = body.distance(from: body.startIndex, to: notationStart)
            let lyric = cleanLyric(lyricSource)
            let parsedLyricStyle = lyricStyle(lyricSource)
            let startsWord = lyricStartsWord(lyricSource, isFirst: elements.isEmpty)

            let parsed = try parseNotationGroup(notation, baseOffset: groupOffset)
            let hasNotes = parsed.contains { token in
                if case .notes = token { return true }
                return false
            }
            if !lyric.isEmpty, !hasNotes {
                let displayLyric = standaloneLyricText(lyric)
                let lyricStart = body.distance(from: body.startIndex, to: cursor)
                let lyricEnd = body.distance(from: body.startIndex, to: open)
                elements.append(
                    .lyricMark(
                        GregorianLyricMark(
                            text: displayLyric,
                            style: standaloneLyricStyle(
                                displayLyric,
                                parsedStyle: parsedLyricStyle
                            ),
                            startsWord: startsWord,
                            sourceRange: GregorianSourceRange(
                                lowerBound: lyricStart,
                                upperBound: lyricEnd
                            )
                        )
                    )
                )
            }
            var appliedLyric = false

            for token in parsed {
                switch token {
                case let .clef(clef):
                    elements.append(.clef(clef))
                case let .accidental(accidental):
                    elements.append(.accidental(accidental))
                case let .division(division):
                    elements.append(.division(division))
                case .forcedBreak:
                    elements.append(.forcedBreak)
                case let .notes(notes):
                    var mappedNotes: [GregorianNote] = []
                    for note in notes {
                        guard timeline.events.indices.contains(eventIndex) else {
                            throw GregorianScoreParserError.tooManyNotationNotes(
                                offset: note.sourceRange.lowerBound
                            )
                        }
                        let event = timeline.events[eventIndex]
                        mappedNotes.append(
                            GregorianNote(
                                id: event.id,
                                pitch: note.pitch,
                                relativePitch: event.relativePitch,
                                shape: note.shape,
                                accidental: note.accidental,
                                hasMora: note.hasMora,
                                hasEpisema: note.hasEpisema,
                                moraCount: note.moraCount,
                                episemaPosition: note.episemaPosition,
                                liquescence: note.liquescence,
                                isCavum: note.isCavum,
                                hasIctus: note.hasIctus,
                                sourceRange: note.sourceRange
                            )
                        )
                        eventIndex += 1
                    }

                    guard let first = mappedNotes.first else { continue }
                    let event = timeline.events[eventIndex - mappedNotes.count]
                    let neumeLyric = appliedLyric ? "" : lyric
                    if !neumeLyric.isEmpty,
                       mappedNotes.contains(where: { mapped in
                           timeline.events.first(where: { $0.id == mapped.id })?.syllableID != event.syllableID
                       }) {
                        throw GregorianScoreParserError.eventSyllableMismatch(eventID: first.id)
                    }
                    let segments = GregorianNeumeSegmenter.segment(mappedNotes)
                    for (segmentIndex, segment) in segments.enumerated() {
                        guard let segmentFirst = segment.first else { continue }
                        elements.append(
                            .neume(
                                GregorianNeume(
                                    id: segmentFirst.id,
                                    syllableID: event.syllableID,
                                    lyric: segmentIndex == 0 ? neumeLyric : "",
                                    lyricStyle: segmentIndex == 0 && !neumeLyric.isEmpty
                                        ? parsedLyricStyle
                                        : .regular,
                                    startsWord: segmentIndex == 0 && !appliedLyric ? startsWord : false,
                                    notes: segment,
                                    sourceRange: GregorianSourceRange(
                                        lowerBound: segment.first?.sourceRange.lowerBound ?? groupOffset,
                                        upperBound: segment.last?.sourceRange.upperBound ?? groupOffset
                                    )
                                )
                            )
                        )
                    }
                    appliedLyric = true
                }
            }

            cursor = body.index(after: close)
            sourceOffset = body.distance(from: body.startIndex, to: cursor)
        }

        guard eventIndex == timeline.events.count else {
            throw GregorianScoreParserError.timelineMismatch(
                expected: timeline.events.count,
                parsed: eventIndex
            )
        }
        guard !elements.isEmpty || timeline.events.isEmpty else {
            throw GregorianScoreParserError.unsupportedToken("empty score", offset: sourceOffset)
        }
        return GregorianScore(elements: elements)
    }

    private enum ParsedToken {
        case clef(GregorianClef)
        case accidental(GregorianAccidentalMark)
        case notes([ParsedNote])
        case division(GregorianDivision)
        case forcedBreak
    }

    private struct ParsedNote {
        let pitch: Int
        let shape: GregorianNoteShape
        let accidental: GregorianAccidental?
        let hasMora: Bool
        let hasEpisema: Bool
        let moraCount: Int
        let episemaPosition: GregorianEpisemaPosition
        let liquescence: GregorianLiquescence
        let isCavum: Bool
        let hasIctus: Bool
        let sourceRange: GregorianSourceRange
    }

    private static func parseNotationGroup(
        _ notation: String,
        baseOffset: Int
    ) throws -> [ParsedToken] {
        let characters = Array(notation)
        var result: [ParsedToken] = []
        var currentNotes: [ParsedNote] = []
        var index = 0

        func flushNotes() {
            if !currentNotes.isEmpty {
                result.append(.notes(currentNotes))
                currentNotes.removeAll(keepingCapacity: true)
            }
        }

        while index < characters.count {
            let character = characters[index]

            if character == "[" {
                flushNotes()
                if let close = characters[(index + 1)...].firstIndex(of: "]") {
                    index = close + 1
                } else {
                    index = characters.count
                }
                continue
            }

            if character.isWhitespace || character == "/" {
                flushNotes()
                index += 1
                continue
            }

            if character == "!" {
                flushNotes()
                index += 1
                continue
            }

            let isFlatCClef = character == "c"
                && index + 2 < characters.count
                && characters[index + 1] == "b"
                && characters[index + 2].isNumber
            if (character == "c" || character == "f"),
               index + 1 < characters.count,
               characters[index + 1].isNumber || isFlatCClef {
                flushNotes()
                let lineIndex = index + (isFlatCClef ? 2 : 1)
                let token = String(characters[index...lineIndex])
                guard let line = Int(String(characters[lineIndex])), (1...4).contains(line) else {
                    throw GregorianScoreParserError.invalidClef(
                        token,
                        offset: baseOffset + index
                    )
                }
                result.append(
                    .clef(
                        GregorianClef(
                            kind: character == "c" ? .c : .f,
                            line: line,
                            flattensB: isFlatCClef
                        )
                    )
                )
                index = lineIndex + 1
                continue
            }

            if character == ":" || character == ";" || character == "," || character == "`" {
                flushNotes()
                if character == ":", index + 1 < characters.count, characters[index + 1] == ":" {
                    result.append(.division(.final))
                    index += 2
                } else {
                    let division: GregorianDivision = switch character {
                    case ",", "`": .minima
                    case ";": .minor
                    default: .major
                    }
                    result.append(.division(division))
                    index += 1
                }
                continue
            }

            if character == "z" || character == "Z" {
                flushNotes()
                result.append(.forcedBreak)
                index += 1
                continue
            }

            guard let pitch = pitchValue(character) else {
                if isIgnorableControl(character) {
                    index += 1
                    continue
                }
                throw GregorianScoreParserError.unsupportedToken(
                    String(character),
                    offset: baseOffset + index
                )
            }

            let noteStart = index
            if index + 1 < characters.count {
                let accidentalCharacter = characters[index + 1]
                let accidental: GregorianAccidental? = switch accidentalCharacter {
                case "x": .flat
                case "y": .natural
                case "#": .sharp
                default: nil
                }
                if let accidental {
                    flushNotes()
                    result.append(
                        .accidental(
                            GregorianAccidentalMark(
                                kind: accidental,
                                pitch: pitch,
                                sourceRange: GregorianSourceRange(
                                    lowerBound: baseOffset + noteStart,
                                    upperBound: baseOffset + noteStart + 2
                                )
                            )
                        )
                    )
                    index += 2
                    continue
                }
            }
            index += 1
            var suffix = ""
            while index < characters.count {
                let next = characters[index]
                if next == "[" {
                    if let close = characters[(index + 1)...].firstIndex(of: "]") {
                        index = close + 1
                    } else {
                        index = characters.count
                    }
                    continue
                }
                if next.isWhitespace || next == "/" || next == ":" || next == ";" || next == ","
                    || next == "`" || next == "z" || next == "Z"
                    || pitchValue(next) != nil
                    || ((next == "c" || next == "f")
                        && index + 1 < characters.count
                        && (
                            characters[index + 1].isNumber
                            || (
                                next == "c"
                                && index + 2 < characters.count
                                && characters[index + 1] == "b"
                                && characters[index + 2].isNumber
                            )
                        )) {
                    break
                }
                suffix.append(next)
                index += 1
            }

            let liquescence: GregorianLiquescence
            if suffix.contains("<") {
                liquescence = .ascending
            } else if suffix.contains(">") {
                liquescence = .descending
            } else if suffix.contains("~") {
                liquescence = .small
            } else {
                liquescence = .none
            }

            let shape: GregorianNoteShape
            if suffix.contains("w") || suffix.contains("W") {
                shape = .quilisma
            } else if suffix.contains("<") || suffix.contains(">") || suffix.contains("~") {
                shape = .liquescent
            } else if suffix.contains("v") || suffix.contains("V") {
                shape = .virga
            } else if character.isUppercase {
                shape = .inclinatum
            } else if suffix.contains("o") || suffix.contains("O") {
                shape = .oriscus
            } else if suffix.contains("s") || suffix.contains("S") {
                shape = .stropha
            } else {
                shape = .punctum
            }

            let accidental: GregorianAccidental?
            if suffix.contains("x") {
                accidental = .flat
            } else if suffix.contains("y") {
                accidental = .natural
            } else if suffix.contains("#") {
                accidental = .sharp
            } else {
                accidental = nil
            }

            let unsupported = suffix.filter { !isSupportedSuffix($0) }
            if let token = unsupported.first {
                throw GregorianScoreParserError.unsupportedToken(
                    String(token),
                    offset: baseOffset + noteStart + 1
                )
            }

            currentNotes.append(
                ParsedNote(
                    pitch: pitch,
                    shape: shape,
                    accidental: accidental,
                    hasMora: suffix.contains("."),
                    hasEpisema: suffix.contains("_"),
                    moraCount: suffix.filter { $0 == "." }.count,
                    episemaPosition: suffix.contains("_0") ? .below : .above,
                    liquescence: liquescence,
                    isCavum: suffix.contains("r") || suffix.contains("R"),
                    hasIctus: suffix.contains("'"),
                    sourceRange: GregorianSourceRange(
                        lowerBound: baseOffset + noteStart,
                        upperBound: baseOffset + index
                    )
                )
            )
            if suffix.contains("!") {
                flushNotes()
            }
        }

        flushNotes()
        return result
    }

    private static func pitchValue(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1 else {
            return nil
        }
        let normalized = String(character).lowercased()
        guard let normalizedScalar = normalized.unicodeScalars.first,
              normalized.unicodeScalars.count == 1 else {
            return nil
        }
        let lower = Character("a").unicodeScalars.first!.value
        let upper = Character("m").unicodeScalars.first!.value
        guard normalizedScalar.value >= lower, normalizedScalar.value <= upper else { return nil }
        return Int(normalizedScalar.value - lower)
    }

    private static func isSupportedSuffix(_ character: Character) -> Bool {
        character.isNumber
            || [".", "_", "w", "W", "<", ">", "~", "x", "y", "#", "v", "V", "o", "O", "q", "Q", "s", "S", "r", "R", "'", "!", "@", "-", "+", "*", "†", "("]
                .contains(character)
    }

    private static func isIgnorableControl(_ character: Character) -> Bool {
        character.isNumber
            || ["'", "!", "@", "]", "-", "+", "_", "*", "†", "(", "."].contains(character)
    }

    private static func cleanLyric(_ source: String) -> String {
        source
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            // Psalm-tone sources use paired underscores for preparatory
            // syllables and paired asterisks for accented syllables. These
            // delimiters describe pointing/style and are not lyric text.
            // The paired patterns intentionally leave a standalone
            // liturgical asterisk unchanged.
            .replacingOccurrences(
                of: #"_([^_]+)_"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\*([^*]+)\*"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lyricStyle(_ source: String) -> GregorianLyricStyle {
        let withoutTags = source.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        if withoutTags.range(of: #"\*[^*]+\*"#, options: .regularExpression) != nil {
            return .accented
        }
        if withoutTags.range(of: #"_([^_]+)_"#, options: .regularExpression) != nil {
            return .preparatory
        }
        return .regular
    }

    private static func standaloneLyricText(_ lyric: String) -> String {
        switch lyric {
        case "V/.":
            "℣."
        case "R/.":
            "℟."
        default:
            lyric
        }
    }

    private static func standaloneLyricStyle(
        _ lyric: String,
        parsedStyle: GregorianLyricStyle
    ) -> GregorianLyricStyle {
        guard parsedStyle == .regular else { return parsedStyle }
        let rubricMarks: Set<String> = [
            "*", "†", "‡", "+", "℣.", "℟."
        ]
        return rubricMarks.contains(lyric) ? .rubric : .regular
    }

    private static func lyricStartsWord(_ source: String, isFirst: Bool) -> Bool {
        guard !isFirst else { return true }
        let withoutTags = source.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return withoutTags.first?.isWhitespace == true
    }
}

public enum GregorianNeumeClassifier {
    public static func classify(_ notes: [GregorianNote]) -> GregorianNeumeForm {
        guard let first = notes.first else { return .punctum }
        let pitches = notes.map(\.pitch)
        let directions = zip(pitches, pitches.dropFirst()).map { nextDirection(from: $0, to: $1) }
        let allEqual = Set(pitches).count == 1
        let allInclinata = notes.allSatisfy { $0.shape == .inclinatum }
        let allStropha = notes.allSatisfy { $0.shape == .stropha }
        let allVirga = notes.allSatisfy { $0.shape == .virga }

        if allInclinata { return .punctaInclinata }
        if notes.count == 1 {
            return switch first.shape {
            case .virga: .virga
            case .stropha: .apostropha
            case .oriscus: .oriscus
            default: .punctum
            }
        }
        if allEqual, allStropha {
            return notes.count >= 3 ? .tristropha : .distropha
        }
        if allEqual, allVirga {
            return notes.count >= 3 ? .trivirga : .bivirga
        }
        if allEqual {
            return notes.count >= 3 ? .tristropha : .distropha
        }
        if notes.count == 2 {
            if directions[0] > 0 {
                return notes.first?.shape == .oriscus ? .pesQuassus : .podatus
            }
            return directions[0] < 0 ? .clivis : .punctum
        }

        let firstTwo = Array(directions.prefix(2))
        if firstTwo == [1, 1] {
            if notes.dropFirst().contains(where: { $0.shape == .oriscus }) {
                return directions.dropFirst(2).contains(-1) ? .salicusFlexus : .salicus
            }
            return directions.dropFirst(2).contains(-1) ? .scandicusFlexus : .scandicus
        }
        if firstTwo == [-1, -1] {
            return (notes.last?.liquescence ?? .none) != .none ? .ancus : .climacus
        }
        if firstTwo == [1, -1] {
            return directions.dropFirst(2).starts(with: [1, -1])
                ? .torculusResupinusFlexus
                : (directions.dropFirst(2).first == 1 ? .torculusResupinus : .torculus)
        }
        if firstTwo == [-1, 1] {
            return directions.dropFirst(2).first == -1 ? .porrectusFlexus : .porrectus
        }
        if directions.first == 1, directions.dropFirst().allSatisfy({ $0 < 0 }) {
            return .pesSubpunctis
        }
        return .punctum
    }

    private static func nextDirection(from: Int, to: Int) -> Int {
        if to > from { return 1 }
        if to < from { return -1 }
        return 0
    }
}

/// Splits a continuous GABC note run into the named forms accepted by the
/// native compositor. This is the native counterpart of Exsurge's
/// `createHoursFromNotes` state machine.
public enum GregorianNeumeSegmenter {
    public static func segment(_ notes: [GregorianNote]) -> [[GregorianNote]] {
        guard notes.count > 1 else { return notes.isEmpty ? [] : [notes] }
        var result: [[GregorianNote]] = []
        var index = 0

        while index < notes.count {
            let remaining = notes.count - index
            guard remaining > 1 else {
                result.append([notes[index]])
                break
            }

            let first = notes[index]
            let second = notes[index + 1]
            let firstDirection = direction(first.pitch, second.pitch)

            if first.shape == .virga {
                let count = repeatedShapeCount(
                    notes,
                    from: index,
                    shape: .virga,
                    pitch: first.pitch,
                    maximum: 3
                )
                result.append(Array(notes[index..<(index + count)]))
                index += count
                continue
            }
            if first.shape == .stropha {
                let count = repeatedShapeCount(
                    notes,
                    from: index,
                    shape: .stropha,
                    pitch: first.pitch,
                    maximum: 3
                )
                result.append(Array(notes[index..<(index + count)]))
                index += count
                continue
            }
            if first.shape == .inclinatum {
                var end = index + 1
                while end < notes.count, notes[end].shape == .inclinatum { end += 1 }
                result.append(Array(notes[index..<end]))
                index = end
                continue
            }

            var length = 1
            if firstDirection > 0 {
                if remaining >= 3, notes[index + 2].shape == .inclinatum,
                   direction(second.pitch, notes[index + 2].pitch) < 0 {
                    length = 3
                    while index + length < notes.count,
                          notes[index + length].shape == .inclinatum,
                          direction(notes[index + length - 1].pitch, notes[index + length].pitch) < 0 {
                        length += 1
                    }
                } else if remaining >= 3 {
                    let secondDirection = direction(second.pitch, notes[index + 2].pitch)
                    if secondDirection > 0 {
                        length = 3
                        if remaining >= 4,
                           direction(notes[index + 2].pitch, notes[index + 3].pitch) < 0 {
                            length = 4
                        }
                    } else if secondDirection < 0 {
                        length = 3
                        if remaining >= 4,
                           direction(notes[index + 2].pitch, notes[index + 3].pitch) > 0 {
                            length = 4
                            if remaining >= 5,
                               direction(notes[index + 3].pitch, notes[index + 4].pitch) < 0 {
                                length = 5
                            }
                        }
                    } else {
                        length = 2
                    }
                } else {
                    length = 2
                }
            } else if firstDirection < 0 {
                if second.shape == .inclinatum {
                    length = 2
                    while index + length < notes.count,
                          notes[index + length].shape == .inclinatum,
                          direction(notes[index + length - 1].pitch, notes[index + length].pitch) < 0 {
                        length += 1
                    }
                } else if remaining >= 3,
                          direction(second.pitch, notes[index + 2].pitch) < 0,
                          notes[index + 2].liquescence != .none {
                    length = 3
                } else if remaining >= 3,
                          direction(second.pitch, notes[index + 2].pitch) > 0 {
                    length = 3
                    if remaining >= 4,
                       direction(notes[index + 2].pitch, notes[index + 3].pitch) < 0 {
                        length = 4
                    }
                } else {
                    length = 2
                }
            } else {
                length = min(3, repeatedPitchCount(notes, from: index, pitch: first.pitch))
            }

            result.append(Array(notes[index..<(index + length)]))
            index += length
        }
        return result
    }

    private static func direction(_ from: Int, _ to: Int) -> Int {
        if to > from { return 1 }
        if to < from { return -1 }
        return 0
    }

    private static func repeatedShapeCount(
        _ notes: [GregorianNote],
        from index: Int,
        shape: GregorianNoteShape,
        pitch: Int,
        maximum: Int
    ) -> Int {
        var count = 0
        while index + count < notes.count, count < maximum,
              notes[index + count].shape == shape,
              notes[index + count].pitch == pitch {
            count += 1
        }
        return max(1, count)
    }

    private static func repeatedPitchCount(
        _ notes: [GregorianNote],
        from index: Int,
        pitch: Int
    ) -> Int {
        var count = 0
        while index + count < notes.count, notes[index + count].pitch == pitch {
            count += 1
        }
        return max(1, count)
    }
}
