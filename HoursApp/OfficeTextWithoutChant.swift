import Foundation
import HoursCore

/// The words of an Hour as they are read without its chant.
///
/// The Roman 1960 edition prints only the opening words of a psalm,
/// canticle or hymn that it sings, and only the mark of a versicle or a
/// response: the words are in the score. Where the chant is not shown,
/// those words are written out from the score as the books set them: a
/// psalm or canticle verse by verse, pointed as its tone points it; a hymn
/// stanza by stanza, line by line; each versicle and response on its line.
/// An antiphon is marked "Ant." as a breviary marks it.
nonisolated extension OfficeReaderSectionBuilder {
    static func writingOutSungWords(in sections: [OfficeSection]) -> [OfficeSection] {
        sections.map { section in
            let written = writtenOut(section)
            // A response follows its versicle on the next line, as a
            // breviary sets them; psalmody keeps its verses apart.
            guard isAntiphon(written)
                    || ![.psalm, .canticle, .hymn].contains(written.kind) else { return written }
            let latin = tightened(written.latin)
            let english = written.english.map(tightened)
            guard latin != written.latin || english != written.english else { return written }
            return written.with(latin: latin, english: english)
        }
    }

    private static func tightened(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<=\S)[ \t]*\n[ \t]*\n\s*(?=℟)"#, with: "\n", options: .regularExpression)
    }

    /// Whether a section is an antiphon: one marked "Ant." in its Latin,
    /// or whose English opens with the antiphon, so marked, and whose Latin
    /// is not a psalm's numbered verses.
    static func isAntiphon(_ section: OfficeSection) -> Bool {
        guard section.kind == .psalm || section.kind == .canticle || section.kind == .antiphon else {
            return false
        }
        if isAntiphonParagraph(section.latin) { return true }
        guard let first = section.english.flatMap({ paragraphs(in: $0).first }),
              isAntiphonParagraph(first) else { return false }
        return section.latin.range(of: #"^\s*\d+[.:]"#, options: .regularExpression) == nil
    }

    /// Whether a section is sung from its score: the chant is shown, and the
    /// words those present say need not stand as text in its place.
    static func isSungFromScore(
        _ section: OfficeSection,
        showsScores: Bool,
        isPriestOrDeaconPresent: Bool
    ) -> Bool {
        showsScores && section.chant != nil
            && !OfficePrayerText.requiresTextFallback(
                for: section,
                isPriestOrDeaconPresent: isPriestOrDeaconPresent
            )
    }

    /// Whether a section is set as a psalter sets it: psalms, and canticles
    /// set as psalms, verse by verse, and hymns stanza by stanza, those
    /// without chant and those whose chant is not shown. An antiphon is set
    /// as prose. The reader and print set them alike.
    static func usesPointedPsalmodyLayout(
        _ section: OfficeSection,
        isSungFromScore: Bool,
        usesCompactPsalmody: Bool
    ) -> Bool {
        !isSungFromScore
            && !isAntiphon(section)
            && (section.kind == .psalm
                || section.kind == .canticle
                    && (usesCompactPsalmody || section.chant != nil
                        || PsalmTextFormatter.isSetVerseByLine(section.latin))
                || section.kind == .hymn && section.chant != nil)
    }

    /// Whether a section is an antiphon read without its chant, set as a
    /// psalter sets one: in italic after its red "Ant.", at the size of the
    /// psalm's verses.
    static func isAntiphonText(
        _ section: OfficeSection,
        isSungFromScore: Bool,
        isMass: Bool
    ) -> Bool {
        !isSungFromScore && !isMass && isAntiphon(section)
    }

    /// The English of the sung parts set as their Latin is set. A hymn's
    /// is without a second copy of the hymn, or the versicle and response
    /// after it, which have their own sections, and its lines are in the
    /// stanzas of the Latin. An antiphon's is without the "Let us pray"
    /// that some print after it, which its Latin does not say.
    static func settingEnglishOfSungParts(in sections: [OfficeSection]) -> [OfficeSection] {
        sections.indices.map { index in
            let section = sections[index]
            guard let english = section.english else { return section }
            if isAntiphon(section) {
                var values = paragraphs(in: english)
                guard values.count > 1, values.last == "Let us pray.",
                      !section.latin.localizedCaseInsensitiveContains("orémus"),
                      !section.latin.localizedCaseInsensitiveContains("oremus") else {
                    return section
                }
                values.removeLast()
                return section.with(latin: section.latin, english: values.joined(separator: "\n\n"))
            }
            guard section.kind == .hymn,
                  let chant = section.chant,
                  let score = try? GregorianScoreParser.parse(gabc: chant.gabc, timeline: chant.timeline) else {
                return section
            }
            let following = sections[(index + 1)...].prefix(3).compactMap(\.english)
            let set = hymnEnglish(
                english,
                stanzaLineCounts: hymnStanzas(scoredVerseElements(in: score)).map(\.count),
                versiclesFollowing: following
            )
            guard set != english else { return section }
            return section.with(latin: section.latin, english: set)
        }
    }

    static func hymnEnglish(
        _ english: String,
        stanzaLineCounts counts: [Int],
        versiclesFollowing following: [String] = []
    ) -> String {
        var values = paragraphs(in: english)
        // A second copy of the hymn, headed again.
        if let heading = values.indices.dropFirst().first(where: {
            ["hymn", "hymnus"].contains(values[$0].lowercased().trimmingCharacters(in: .punctuationCharacters))
        }), heading + 1 < values.count, values[heading + 1] == values[0] {
            values.removeSubrange(heading...)
        }
        // The versicle and response that follow the hymn in sections of
        // their own.
        let followingParagraphs = Set(following.flatMap { paragraphs(in: $0) })
        while values.count > 1, let last = values.last,
              last.hasPrefix("℣.") || last.hasPrefix("℟."),
              followingParagraphs.contains(last) {
            values.removeLast()
        }
        var amen: String?
        if values.count > 1, let last = values.last,
           ["amen.", "amen"].contains(last.lowercased()) {
            amen = values.removeLast()
        }
        var stanzas: [[String]]
        if values.contains(where: { $0.contains("\n") }) {
            stanzas = values.map { $0.components(separatedBy: "\n") }
        } else if !counts.isEmpty, counts.reduce(0, +) == values.count {
            stanzas = []
            var start = 0
            for count in counts {
                stanzas.append(Array(values[start..<(start + count)]))
                start += count
            }
        } else if counts.count > 1, values.count % counts.count == 0 {
            let size = values.count / counts.count
            stanzas = stride(from: 0, to: values.count, by: size).map { Array(values[$0..<($0 + size)]) }
        } else {
            stanzas = values.map { [$0] }
        }
        if let amen, !stanzas.isEmpty, !stanzas[stanzas.count - 1].isEmpty {
            stanzas[stanzas.count - 1][stanzas[stanzas.count - 1].count - 1] += " " + amen
        }
        let set = stanzas.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
        return set == paragraphs(in: english).joined(separator: "\n\n") ? english : set
    }

    private static func writtenOut(_ section: OfficeSection) -> OfficeSection {
        let antiphon = isAntiphon(section)
        var latin = section.latin
        var english = section.english
        if let chant = section.chant,
           let score = try? GregorianScoreParser.parse(gabc: chant.gabc, timeline: chant.timeline),
           wordCount(in: score.lyricText) > wordCount(in: section.latin) {
            let verses = scoredVerseElements(in: score)
            if section.kind == .hymn {
                latin = hymnStanzas(verses).map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
            } else if !antiphon, section.kind == .psalm || section.kind == .canticle, verses.count > 1 {
                let pointed = numberingFirstVerse(normalizingTrailingVerseOrdinals(verses.map {
                    pointedLyricText(in: $0).trimmingCharacters(in: .whitespacesAndNewlines)
                }))
                latin = pointed.joined(separator: "\n\n")
                if let source = english,
                   let alignment = aligningPsalmodyEnglish(
                       paragraphs(in: source),
                       with: pointed.map(PsalmTextFormatter.removingEmphasisMarkers)
                   ) {
                    english = serializedPsalmodyEnglish(alignment.verses, trailing: alignment.trailing)
                }
            } else {
                let lines = lines(of: verses, breaksBeforeFormulas: !antiphon)
                latin = lines.joined(separator: "\n")
                // The antiphon repeated after its psalm is printed without
                // the mark where the cantor's intonation ends.
                if antiphon, !section.latin.contains("*") {
                    latin = latin.replacingOccurrences(of: " * ", with: " ")
                }
                // The English set line by line, as the Latin is.
                if let source = english, lines.count > 1 {
                    english = paragraphs(in: source).joined(separator: "\n")
                }
            }
            latin = withPlainOpening(latin)
                // A score's transcription may space a colon as French
                // printing spaces it.
                .replacingOccurrences(of: #"[ \t\x{00A0}\x{2009}\x{202F}]+([:;?!])"#, with: "$1", options: .regularExpression)
        }
        // A versicle and response marked in the edition's own letters.
        latin = latin.replacingOccurrences(of: #"(^|\s)V/\."#, with: "$1℣.", options: .regularExpression)
            .replacingOccurrences(of: #"(^|\s)R/\."#, with: "$1℟.", options: .regularExpression)
        if antiphon {
            if latin.last?.isLetter == true { latin += "." }
            if !isAntiphonParagraph(latin) { latin = "Ant. " + latin }
        } else if let first = english.flatMap({ paragraphs(in: $0).first }),
                  first.hasPrefix("℟.br."), !latin.hasPrefix("℟") {
            latin = "℟.br. " + latin
        }
        guard latin != section.latin || english != section.english else { return section }
        return section.with(latin: latin, english: english)
    }

    /// The words of a text, versicles' and responses' marks apart.
    private static func wordCount(in text: String) -> Int {
        text.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count > 1 }.count
    }

    /// A psalm's first verse numbered as the rest are.
    private static func numberingFirstVerse(_ verses: [String]) -> [String] {
        guard verses.count > 1,
              verses[1].hasPrefix("2. "),
              verses[0].range(of: #"^\d+\.\s"#, options: .regularExpression) == nil else {
            return verses
        }
        return ["1. " + verses[0]] + verses.dropFirst()
    }

    /// The words of a score's verses, a line to each verse and to each
    /// versicle and response within one; the doxology and the Alleluia
    /// that close an opening begin lines of their own.
    private static func lines(
        of verses: [[GregorianNotationElement]],
        breaksBeforeFormulas: Bool
    ) -> [String] {
        var result: [String] = []
        for verse in verses {
            var line = SungLine()
            for element in verse {
                switch element {
                case .neume(let neume):
                    line.append(neume.lyric, startsWord: neume.startsWord, isMark: false)
                case .lyricMark(let mark):
                    if mark.text == "℣." || mark.text == "℟." {
                        result.append(contentsOf: line.finished())
                    }
                    line.append(mark.text, startsWord: mark.startsWord, isMark: true)
                case .clef, .accidental, .division, .forcedBreak:
                    continue
                @unknown default:
                    continue
                }
            }
            result.append(contentsOf: line.finished())
        }
        // A score may set the mark of the line that follows (℟., ℣., T.P.)
        // at the bar that ends the line before.
        var carried: [String] = []
        var mark: String?
        for line in result {
            var line = line
            if let held = mark {
                line = held + " " + line
                mark = nil
            }
            if ["℣.", "℟.", "T.P."].contains(line) {
                mark = line
                continue
            }
            if line.hasSuffix(" T.P.") {
                line.removeLast(" T.P.".count)
                mark = "T.P."
            }
            carried.append(line)
        }
        if let mark { carried.append(mark) }
        result = carried
        guard breaksBeforeFormulas else { return result }
        return result.flatMap {
            $0.replacingOccurrences(
                of: #"(?<=\p{Ll}[.!?])\s+(?=(?:Gl[oó]ria Patri|Sicut erat|Allel[uú][ij]a))"#,
                with: "\n",
                options: .regularExpression
            ).components(separatedBy: "\n")
        }
    }

    /// A hymn's stanzas, each a list of its lines. A line ends at a division
    /// after which the words begin with a capital, as the books begin each
    /// line of a hymn. The stanzas' numbers are left to the score; an Amen
    /// sung apart closes the last stanza.
    static func hymnStanzas(_ verses: [[GregorianNotationElement]]) -> [[String]] {
        var stanzas: [[String]] = []
        for verse in verses {
            var lines: [String] = []
            var line = SungLine()
            var divided = false
            for element in verse {
                switch element {
                case .neume(let neume):
                    if divided, neume.startsWord,
                       neume.lyric.first(where: \.isLetter)?.isUppercase == true {
                        lines.append(contentsOf: line.finished())
                    }
                    divided = false
                    line.append(neume.lyric, startsWord: neume.startsWord, isMark: false)
                case .lyricMark(let mark):
                    line.append(mark.text, startsWord: mark.startsWord, isMark: true)
                case .division(let division):
                    divided = divided || division != .final
                case .clef, .accidental, .forcedBreak:
                    continue
                @unknown default:
                    continue
                }
            }
            lines.append(contentsOf: line.finished())
            let lastIndex = lines.count - 1
            lines = lines.enumerated().map { index, value in
                var value = value
                if index == 0 {
                    value = value.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                }
                if index == lastIndex {
                    value = value.replacingOccurrences(of: #"\s*\d+\.$"#, with: "", options: .regularExpression)
                }
                return value
            }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            if lines.count == 1, ["amen.", "amen"].contains(lines[0].lowercased()), !stanzas.isEmpty {
                stanzas[stanzas.count - 1][stanzas[stanzas.count - 1].count - 1] += " " + lines[0]
            } else {
                stanzas.append(lines)
            }
        }
        return stanzas
    }

    /// The first word as a book prints it in the text, its opening capitals
    /// (set large in a score, beside its initial) in small letters again:
    /// "PAcíficus" as "Pacíficus". A word set wholly in capitals is left.
    private static func withPlainOpening(_ text: String) -> String {
        guard let first = text.firstIndex(where: \.isLetter) else { return text }
        let word = text[first...].prefix { $0.isLetter }
        let capitals = word.prefix { $0.isUppercase }
        guard capitals.count > 1, capitals.count < word.count else { return text }
        let rest = text[word.startIndex...].dropFirst(capitals.count)
        return String(text[..<first]) + String(capitals.prefix(1)) + capitals.dropFirst().lowercased() + rest
    }

    /// A line of sung words, spaced as a score's lyric is spaced.
    private struct SungLine {
        private var text = ""
        private var separatesFollowingLyric = false

        mutating func append(_ value: String, startsWord: Bool, isMark: Bool) {
            guard !value.isEmpty else { return }
            if !text.isEmpty,
               startsWord || separatesFollowingLyric,
               text.last?.isWhitespace != true {
                text.append(" ")
            }
            text.append(value)
            separatesFollowingLyric = isMark
        }

        /// The line, if it holds any words; it is begun afresh.
        mutating func finished() -> [String] {
            defer { self = SungLine() }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? [] : [value]
        }
    }
}

/// The English of the headings the Roman 1960 edition prints in Latin
/// alone, for a reader that shows the English.
nonisolated enum OfficeHeadingTranslation {
    static func english(for title: String) -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let english = named[title] { return english }
        if let match = title.wholeMatch(of: /Psalmus (.+)/) { return "Psalm \(match.1)" }
        if let match = title.wholeMatch(of: /Lectio (\d+)/) { return "Reading \(match.1)" }
        if let match = title.wholeMatch(of: /Responsorium (\d+)/) { return "Responsory \(match.1)" }
        if let match = title.wholeMatch(of: /Canticum: Canticum (.+?)(?: \[\d+\])?/) {
            let name = String(match.1)
            if let english = canticles[name] { return english }
            return "Canticle of \(canticleAuthors[name] ?? name)"
        }
        if let match = title.wholeMatch(of: /Canticum: (.+)/) { return "Canticle: \(match.1)" }
        if let match = title.wholeMatch(of: /Commemoratio (.+)/) { return "Commemoration: \(match.1)" }
        return nil
    }

    private static let named: [String: String] = [
        "Absolutio": "Absolution",
        "Antiphona finalis B.M.V.": "Final Antiphon of the Blessed Virgin Mary",
        "Benedictio": "Blessing",
        "Capitulum": "Chapter",
        "Capitulum Hymnus Versus": "Chapter Hymn Verse",
        "Capitulum Responsorium Versus": "Chapter Responsory Verse",
        "Conclusio": "Conclusion",
        "Hymnus": "Hymn",
        "Incipit": "Beginning",
        "Invitatorium": "Invitatory",
        "Lectio brevis": "Short reading",
        "Martyrologium": "Martyrology",
        "Oratio": "Prayer",
        "Pater": "Our Father",
        "Prex poenitentialis": "Penitential Prayer",
        "Psalmi": "Psalms",
        "Psalmi cum lectionibus": "Psalms with lections",
        "Psalmus": "Psalm",
        "Te Deum": "Te Deum",
        "Versus": "Versicle",
    ]

    /// The Gospel canticles, by the names the 1954 edition gives them.
    private static let canticles: [String: String] = [
        "B. Mariæ Virginis": "Canticle: Magnificat",
        "Zachariæ": "Canticle: Benedictus",
        "Simeonis": "Canticle: Nunc dimittis",
        "Quicumque": "Athanasian Creed",
    ]

    private static let canticleAuthors: [String: String] = [
        "Annæ": "Anna",
        "David": "David",
        "Ecclesiastici": "Ecclesiasticus",
        "Ezechiæ": "Ezechias",
        "Habacuc": "Habacuc",
        "Ieremiæ": "Jeremias",
        "Isaiæ": "Isaias",
        "Iudith": "Judith",
        "Moysis": "Moses",
        "Tobiæ": "Tobias",
        "Trium Puerorum": "the Three Children",
    ]
}

private extension OfficeSection {
    /// A copy with other words, all else kept.
    nonisolated func with(latin: String, english: String?) -> OfficeSection {
        var copy = OfficeSection(
            id: id,
            kind: kind,
            title: title,
            titleEnglish: titleEnglish,
            rubric: rubric,
            rubricEnglish: rubricEnglish,
            latin: latin,
            english: english,
            chant: chant,
            ordinary: ordinary
        )
        copy.isSaidByAll = isSaidByAll
        return copy
    }
}
