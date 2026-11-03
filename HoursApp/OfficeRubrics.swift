import Foundation
import HoursCore

/// What a breviary prints in red among the words of the Office, beside the
/// signs and the marks of a line: the directions to the one who prays, and
/// the parts that are a rubric in their whole, a citation, a lesson's title,
/// a note that the Glory be is omitted.
nonisolated enum OfficeRubrics {
    /// The marks that open a line said or sung: a versicle's, a response's,
    /// an antiphon's. A line they open is said, though it stand in a
    /// rubric's part.
    private static let spokenMark = try! NSRegularExpression(pattern: #"^(?:℣|℟|Ant\.|V/|R/)"#)

    /// The directions the editions print as lines of their own among the
    /// words to be said, in Latin and in English. Each is the whole line, in
    /// lower case, its last stop aside.
    private static let directionLines = patterns([
        // Latin
        "secreto",
        "flexis genibus",
        "(?:sequens|prima) stropha(?: sequentis hymni)?(?:, si coram sanctissimo exposito officium persolvatur,)? dicitur flexis genibus",
        "et recto tono dicitur benedictio",
        "deinde dicitur secreto",
        "deinde dicitur tantum pater noster secreto, nisi sequatur alia hora",
        "et si tunc terminetur officium, dicitur tantum pater noster secreto",
        "si matutinum a laudibus separatur, tunc dicitur secreto",
        "«? ?pater noster ?»? dicitur (?:totum secreto|secreto usque ad .+)",
        "credo dicitur secreto usque ad .+",
        "examen conscientiæ vel «? ?pater noster ?»? totum secreto",
        "deinde, clara voce, dicitur versus",
        "et sub silentio concluditur",
        "gloria (?:omittitur|adduntur)",
        "secunda ['‘’]?domine, exaudi['‘’]? omittitur",
        "quæ non repetitur in psalmo",
        "reliqua omittuntur, nisi laudes separandæ sint",
        "extra chorum, quando ab uno tantum recitatur officium dicitur: .+",
        "in anno bissextili omittitur: .+",
        "post vesperas diei dicuntur vesper(?:æ|ae) defunctorum",
        "vesperæ ab iis qui .+ intersunt, hodie non dicuntur",
        // English
        "in secret",
        "silently",
        "kneel",
        "finish silently",
        "omit glory be",
        "the glory be is (?:omitted|added)",
        "skip (?:the )?second ['‘’]?o lord, hear my prayer['‘’]?",
        "the second ['‘’]?o lord, hear my prayer['‘’]? is omitted",
        "skip the rest, unless praying lauds separately",
        "it is not repeated in the psalm",
        "our father is said (?:silently until .+|completely in silence)",
        "credo is said silently until .+",
        "thereafter, with hearable voice, the versicle is said",
        "if matins and lauds are separated, then is said silently",
        "thereafter, only pater noster is said silently, unless another hour follows immediately",
        "and if thus the office is ended, only pater noster is said silently",
        "thereafter is said silently",
        "after vespers of the day, vespers of the dead are said",
        "if the office is celebrated before the exposed blessed sacrament, the following verses are said on bended knee",
        "the following verse is said on bended knee",
        "there follows an examination of conscience, or the our father said silently",
        "today, vespers are not said by those who assist at .+",
        "what follows is read in the usual lesson tone, and all stand",
    ])

    /// The directions printed within a line, between parentheses: the bow,
    /// the genuflexion, the striking of the breast. The words between the
    /// parentheses are the whole direction, in lower case, its last stop
    /// aside; a Father's aside in parentheses ("ut refert beátus Gregórius
    /// Papa") is his own words.
    private static let bracketedDirections = patterns([
        // Latin
        "genuflectitur",
        "fit reverentia(?:, secundum consuetudinem)?",
        "percutit sibi pectus",
        "secreto",
        "flexis genibus",
        "sequens versus dicitur flexis genibus",
        "prima stropha (?:hymni )?sequentis(?: hymni)? dicitur flex(?:is|ibus) genibus",
        "quod sequitur, legitur in tono lectionis consueto; et surgunt omnes",
        // English
        "genuflect",
        "bow head",
        "strikes his breast",
        "kneel for the following verse",
        "during the following verse,? (?:by local custom,? )?all make a profound bow",
        "the first verse of the following hymn is said genuflecting",
        "all kneel down",
        "what follows is read in the usual lesson tone, and all stand",
    ])

    private static let bracketed = try! NSRegularExpression(pattern: #"\(([^()]*)\)"#)

    private static func patterns(_ sources: [String]) -> [NSRegularExpression] {
        sources.map { try! NSRegularExpression(pattern: "^(?:\($0))[.:;,]?$") }
    }

    private static func matches(_ pattern: NSRegularExpression, _ words: String) -> Bool {
        pattern.firstMatch(in: words, range: NSRange(location: 0, length: (words as NSString).length)) != nil
    }

    private static func matchesAny(_ patterns: [NSRegularExpression], _ words: String) -> Bool {
        let lowered = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return patterns.contains { matches($0, lowered) }
    }

    /// Whether a part is a rubric in its whole, printed as a part of its own
    /// and not sung.
    static func isRubric(_ section: OfficeSection) -> Bool {
        section.kind == .rubric && section.chant == nil
    }

    /// The rubrics in a part's text, in order, as ranges of its UTF-16
    /// units: each line of a rubric's own part (`isRubric`) but those said, a
    /// line that is a direction, and a direction in parentheses.
    static func ranges(in text: String, isRubric: Bool = false) -> [NSRange] {
        var result: [NSRange] = []
        var location = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { location += line.utf16.count + 1 }
            guard let first = line.firstIndex(where: { !$0.isWhitespace }),
                  let last = line.lastIndex(where: { !$0.isWhitespace }) else { continue }
            let words = String(line[first...last])
            let lower = location + line.utf16.distance(from: line.startIndex, to: first)
            if isRubric ? !matches(spokenMark, words) : matchesAny(directionLines, words) {
                result.append(NSRange(location: lower, length: words.utf16.count))
                continue
            }
            let string = words as NSString
            for match in bracketed.matches(in: words, range: NSRange(location: 0, length: string.length)) {
                guard matchesAny(bracketedDirections, string.substring(with: match.range(at: 1))) else { continue }
                result.append(NSRange(location: lower + match.range.location, length: match.range.length))
            }
        }
        return result
    }
}
