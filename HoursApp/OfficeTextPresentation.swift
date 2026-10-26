import Foundation
import HoursCore

nonisolated enum OfficePrayerText {
    private static let layLatinGreeting = """
    ℣. Dómine, exáudi oratiónem meam.

    ℟. Et clamor meus ad te véniat.
    """
    private static let clericalLatinGreeting = """
    ℣. Dóminus vobíscum.

    ℟. Et cum spíritu tuo.
    """
    private static let layEnglishGreeting = """
    ℣. O Lord, hear my prayer.

    ℟. And let my cry come unto thee.
    """
    private static let clericalEnglishGreeting = """
    ℣. The Lord be with you.

    ℟. And with thy spirit.
    """

    /// The direction to omit the second lay greeting, as each edition
    /// prints it.
    private static let omittedLatinGreetings = [
        "secunda Domine, exaudi omittitur",
        "secunda 'Domine, exaudi' omittitur"
    ]
    private static let omittedEnglishGreetings = [
        "skip second O Lord, hear my prayer",
        "The second ‘O Lord, hear my prayer’ is omitted."
    ]
    /// The request for a blessing as one who recites the Office alone makes
    /// it, of the Lord. A reader makes it of the priest who presides: Jube,
    /// domne, benedícere. A rubric that quotes the words has no versicle
    /// mark before them and is left as it is.
    private static let layLatinRequest = #"(℣\.\s*[IJ]ube,?\s+)Dómine(,?\s+benedícere)"#
    /// The lay greeting as a text may hold it, on lines or in paragraphs.
    private static let layLatinVersicle =
        #"℣\. Dómine, exáudi oratiónem meam\.\s+℟\. Et clamor meus ad te véniat\."#
    private static let layGreetingWords = [
        "domine", "exaudi", "orationem", "meam",
        "et", "clamor", "meus", "ad", "te", "veniat"
    ]
    private static let layRequestWords = ["iube", "domine", "benedicere"]

    static func adjusted(_ text: String, isPriestOrDeaconPresent: Bool) -> String {
        guard isPriestOrDeaconPresent else { return text }
        let text = text.replacingOccurrences(
            of: layLatinRequest,
            with: "$1domne$2",
            options: .regularExpression
        )

        // The Office of the Dead retains Domine exaudi as a versicle;
        // clergy add their greeting where the second lay greeting is omitted.
        for direction in omittedLatinGreetings where text.contains(direction) {
            return text.replacingOccurrences(
                of: direction,
                with: clericalLatinGreeting
            )
        }
        for direction in omittedEnglishGreetings where text.contains(direction) {
            return text.replacingOccurrences(
                of: direction,
                with: clericalEnglishGreeting
            )
        }
        return replacingGreeting(
            in: replacingGreeting(in: text, greeting: layLatinGreeting, replacement: clericalLatinGreeting),
            greeting: layEnglishGreeting,
            replacement: clericalEnglishGreeting
        )
    }

    /// Older source packs store the required versicle and the omitted
    /// second greeting separately. Keep that distinction when presenting
    /// them, including while another tradition still uses its older pack.
    static func groupingDeadOfficeGreeting(in sections: [OfficeSection]) -> [OfficeSection] {
        var result: [OfficeSection] = []
        for section in sections {
            if section.latin.trimmingCharacters(in: .whitespacesAndNewlines) == "secunda Domine, exaudi omittitur",
               let previous = result.last,
               previous.latin.contains("Et clamor meus ad te véniat.") {
                // Where neither part is translated the greeting has no English.
                let english = [previous.english, section.english].compactMap { $0 }
                result.removeLast()
                result.append(OfficeSection(id: previous.id, kind: previous.kind,
                    title: previous.title, titleEnglish: previous.titleEnglish,
                    rubric: previous.rubric, rubricEnglish: previous.rubricEnglish,
                    latin: previous.latin + "\n" + section.latin,
                    english: english.isEmpty ? nil : english.joined(separator: "\n"),
                    chant: nil))
            } else {
                result.append(section)
            }
        }
        return result
    }

    static func requiresTextFallback(_ latin: String, isPriestOrDeaconPresent: Bool) -> Bool {
        adjusted(latin, isPriestOrDeaconPresent: isPriestOrDeaconPresent) != latin
    }

    /// A text of a section, as it is said by those present: what all say is
    /// left as it stands.
    static func adjusted(
        _ text: String,
        in section: OfficeSection,
        isPriestOrDeaconPresent: Bool
    ) -> String {
        section.isSaidByAll ? text : adjusted(text, isPriestOrDeaconPresent: isPriestOrDeaconPresent)
    }

    /// Whether a section's words are set as text in place of its score.
    static func requiresTextFallback(for section: OfficeSection, isPriestOrDeaconPresent: Bool) -> Bool {
        !section.isSaidByAll
            && requiresTextFallback(section.latin, isPriestOrDeaconPresent: isPriestOrDeaconPresent)
    }

    /// The lay greeting's words are also a versicle: the last of the ferial
    /// preces, and in the Office of the Dead. There all say them, and the
    /// direction that follows (the second greeting is omitted) is what a
    /// priest's greeting replaces. A section that ends with those words and
    /// stands before that direction is marked as said by all. (A section
    /// that holds the direction with its own versicle needs no mark: the
    /// rule keeps the one and replaces the other.)
    static func markingWhatAllSay(in sections: [OfficeSection]) -> [OfficeSection] {
        sections.indices.map { index in
            var section = sections[index]
            guard index + 1 < sections.count,
                  omittedLatinGreetings.contains(where: sections[index + 1].latin.contains),
                  sections[index + 1].latin.range(of: layLatinVersicle, options: .regularExpression) == nil,
                  !omittedLatinGreetings.contains(where: section.latin.contains) else { return section }
            let latin = section.latin.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsWithTheVersicle = latin.range(
                of: layLatinVersicle + "$",
                options: .regularExpression
            ) != nil
            let singsTheVersicle = section.chant.map { sungWords(sungText($0.gabc)) == layGreetingWords } ?? false
            guard endsWithTheVersicle || singsTheVersicle else { return section }
            section.isSaidByAll = true
            return section
        }
    }

    /// A section may print only its versicle mark where its words are sung,
    /// as the Roman 1960 edition's greeting and request for a blessing do.
    /// Such a section is given those words for its Latin, so that they give
    /// place to what is said where a priest or deacon is present. The
    /// versicle that stands before the direction to omit the second greeting
    /// is said by all, and is left as it is.
    static func writingOutSungLayForms(in sections: [OfficeSection]) -> [OfficeSection] {
        sections.indices.map { index in
            let section = sections[index]
            guard let chant = section.chant,
                  ["V/", "V/.", "℣", "℣."].contains(
                    section.latin.trimmingCharacters(in: .whitespacesAndNewlines)
                  ) else { return section }
            let sung = sungText(chant.gabc)
            let words = sungWords(sung)
            let latin: String
            if words == layGreetingWords {
                let following = index + 1 < sections.count
                    ? sections[index + 1].latin.trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                guard !omittedLatinGreetings.contains(where: following.contains) else { return section }
                latin = layLatinGreeting
            } else if words == layRequestWords {
                // The first letter is the edition's own, as it is sung.
                latin = sung.contains("Iube")
                    ? "℣. Iube, Dómine, benedícere."
                    : "℣. Jube, Dómine, benedícere."
            } else {
                return section
            }
            return OfficeSection(
                id: section.id, kind: section.kind,
                title: section.title, titleEnglish: section.titleEnglish,
                rubric: section.rubric, rubricEnglish: section.rubricEnglish,
                latin: latin, english: section.english, chant: section.chant
            )
        }
    }

    /// The words of a score, without its notes, tags and header.
    private static func sungText(_ gabc: String) -> String {
        let body = gabc.components(separatedBy: "%%").dropFirst().joined(separator: "%%")
        return (body.isEmpty ? gabc : body)
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    /// Sung words without accents or case, a `j` read as `i`. The versicle
    /// marks, being single letters, are no words.
    private static func sungWords(_ sung: String) -> [String] {
        sung.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "la")
        )
        .lowercased()
        .replacingOccurrences(of: "j", with: "i")
        .components(separatedBy: CharacterSet.letters.inverted)
        .filter { $0.count > 1 }
    }

    private static func replacingGreeting(in text: String, greeting: String, replacement: String) -> String {
        let lines = greeting.components(separatedBy: "\n\n")
        let pattern = lines.map(NSRegularExpression.escapedPattern(for:)).joined(separator: #"(\s+)"#)
        let replacementLines = replacement.components(separatedBy: "\n\n")
        // Preserve the source's line spacing, including single-newline imports.
        return text.replacingOccurrences(of: pattern,
            with: replacementLines.joined(separator: "$1"), options: .regularExpression)
    }

}

nonisolated enum OfficeBilingualText {
    static func distinctEnglish(
        _ english: String?,
        from latin: String
    ) -> String? {
        guard let english else { return nil }
        let englishComparison = english.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !englishComparison.isEmpty else { return nil }
        let latinComparison = latin.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard englishComparison.caseInsensitiveCompare(latinComparison)
                != .orderedSame else {
            return nil
        }
        return english
    }
}

/// Presentation of source-edition annotations, after the stored digest has been
/// checked. Prayer words, psalm divisions and all score/timeline data stay intact.
nonisolated enum SourceOfficeTextPresentation {
    static func text(_ source: String) -> String {
        var value = source
        // These are source-engine trace labels; the selected doxology is
        // already written out in the hymn (specials/hymni.pl).
        value = value.replacingOccurrences(of: #"\s*\{Doxology: (?:Special|Pasch|Corp|Epi|Nat|Asc|Pent|Heart)\}"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "{default}", with: "")
        // Four witnessed typographical errors in English source readings.
        for annotation in ["Here ends St Bernard.", "Comm. on Matth. xxv.", "Bk. x, Chap. xvi, on Job xii.", "Here, if necessary, the Lesson is divided."] {
            value = value.replacingOccurrences(of: "{" + annotation + ")", with: "(" + annotation + ")")
        }
        // The braces mark source-selection rubrics, not spoken prayer text.
        // Keep their words; hide only the internal Lauds-psalter selector.
        value = value.replacingOccurrences(of: #"\{Laudes:[12] "#, with: "{", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\{((?:(?:Antiphon(?:a|æ|s)?|Psalmi|Psalms|ex|from) [^{}\n]+)|anticipatur|anticipated|Per Annum|Throughout the Year|paschale|for Easter time|habentur|included|specialis|special|per annum)\}"#, with: "($1)", options: .regularExpression)
        // Bracketed ordinal numbers are the position within this hour's
        // psalmody, not verses or footnotes. Anchor to a complete heading.
        value = value.replacingOccurrences(
            of: #"(?m)^((?:Psalmus|Psalm) \d+(?:\([0-9a-b,–-]+\))?|(?:Canticum|Canticle) [^\n\[\]]+) \[\d+\]$"#,
            with: "$1", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Unscored psalmody in the source edition prints one verse per line,
    /// under the psalm's name. The reader pairs Latin and English by verse
    /// paragraph, so each verse becomes a paragraph and the name becomes the
    /// heading — only where the two languages have the same lines, so that no
    /// verse is ever paired with the wrong translation.
    static func versedPsalmody(
        latin: String,
        english: String?,
        title: String,
        titleEnglish: String?
    ) -> (latin: String, english: String?, title: String, titleEnglish: String?)? {
        guard !latin.contains("\n\n"), english?.contains("\n\n") != true else { return nil }
        func lines(_ value: String) -> [String] {
            value.components(separatedBy: "\n").filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        var latinLines = lines(latin)
        var englishLines = english.map(lines)
        let verse = #"^\d+:\d+[a-z]? "#
        guard latinLines.filter({ $0.range(of: verse, options: .regularExpression) != nil }).count >= 2 else {
            return nil
        }
        var heading = title
        var headingEnglish = titleEnglish
        if heading.isEmpty, let first = latinLines.first,
           first.range(of: #"^(?:Psalmus \d+|Canticum )"#, options: .regularExpression) != nil {
            heading = first
            latinLines.removeFirst()
            if let firstEnglish = englishLines?.first,
               firstEnglish.range(of: #"^(?:Psalm \d+|Canticle )"#, options: .regularExpression) != nil {
                headingEnglish = firstEnglish
                englishLines?.removeFirst()
            }
        }
        guard englishLines == nil || englishLines?.count == latinLines.count else { return nil }
        return (
            latinLines.joined(separator: "\n\n"),
            englishLines?.joined(separator: "\n\n"),
            heading,
            headingEnglish
        )
    }

    static func sections(_ source: [OfficeSection]) -> [OfficeSection] {
        let displayed = source.compactMap { section -> OfficeSection? in
            let latin = text(section.latin)
            let english = section.english.map(text) ?? (section.latin == "Extra Chorum, quando ab uno tantum recitatur Officium dicitur: Jube, Dómine, benedícere; et subjungitur congruens Benedictio."
                ? "Outside choir, when the Office is recited by one person alone, Jube, Dómine, benedícere is said; the appropriate blessing follows."
                : nil)
            // "Psalmi" is the source table's inherited part label, not the
            // title of each antiphon, psalm and doxology in that table.
            let isPsalmGroup = section.title == "Psalmi"
            let title = isPsalmGroup ? "" : text(section.title)
            let titleEnglish = isPsalmGroup ? nil : section.titleEnglish.map(text)
            guard !latin.isEmpty || !(english ?? "").isEmpty || !title.isEmpty || !(titleEnglish ?? "").isEmpty || section.chant != nil else { return nil }
            let annotationOnly = section.chant == nil && section.rubric == nil
                && latin.hasPrefix("(") && latin.hasSuffix(")") && section.latin
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: #"^\{[^{}\n]+\}$"#, options: .regularExpression) != nil
            // Every standalone source rubric needs rubric typography, including
            // unbraced directions such as Gloria omittitur and Extra Chorum.
            let directionOnly = annotationOnly || (section.kind == .rubric && section.chant == nil && section.rubric == nil)
            if section.chant == nil, !directionOnly,
               let psalmody = versedPsalmody(
                   latin: latin,
                   english: english,
                   title: title,
                   titleEnglish: titleEnglish
               ) {
                return OfficeSection(id: section.id, kind: .psalm,
                    title: psalmody.title, titleEnglish: psalmody.titleEnglish,
                    rubric: section.rubric.map(text), rubricEnglish: section.rubricEnglish.map(text),
                    latin: psalmody.latin, english: psalmody.english)
            }
            if section.kind == .psalm, section.chant == nil,
               latin.range(of: #"^Psalmus \d+(?:\([0-9a-b,–-]+\))?$"#, options: .regularExpression) != nil,
               english == nil || english?.range(of: #"^Psalm \d+(?:\([0-9a-b,–-]+\))?$"#, options: .regularExpression) != nil {
                return OfficeSection(id: section.id, kind: .psalm,
                    title: latin, titleEnglish: english,
                    rubric: section.rubric.map(text), rubricEnglish: section.rubricEnglish.map(text),
                    latin: "", english: nil)
            }
            return OfficeSection(id: section.id, kind: directionOnly ? .rubric : section.kind,
                title: title, titleEnglish: titleEnglish,
                rubric: directionOnly ? latin : section.rubric.map(text),
                rubricEnglish: directionOnly ? english : section.rubricEnglish.map(text),
                latin: directionOnly ? "" : latin, english: directionOnly ? nil : english, chant: section.chant)
        }
        // Keep a standalone heading with its content. This also joins a
        // hymn's title to its score when a hidden doxology trace occupied
        // the source's first text block.
        return displayed.reduce(into: []) { result, section in
            if let heading = result.last, !heading.title.isEmpty,
               heading.latin.isEmpty, heading.english?.isEmpty != false,
               heading.chant == nil, heading.rubric == nil, heading.rubricEnglish == nil,
               section.kind == heading.kind, section.title.isEmpty {
                result.removeLast()
                result.append(OfficeSection(id: section.id, kind: section.kind,
                    title: heading.title, titleEnglish: heading.titleEnglish,
                    rubric: section.rubric, rubricEnglish: section.rubricEnglish,
                    latin: section.latin, english: section.english, chant: section.chant))
            } else {
                result.append(section)
            }
        }
    }
}
