import Foundation

nonisolated enum RubricsEdition: String, CaseIterable, Identifiable, Sendable {
    // The reference order is independent of the edition selected for prayer.
    case roman1960
    case roman1954

    var id: Self { self }
    var year: String { self == .roman1960 ? "1960" : "1954" }
    var subtitle: String {
        switch self {
        case .roman1960: "The four classes and the revised order of the Office"
        case .roman1954: "Doubles, semidoubles, and the earlier order of the Office"
        }
    }
    var introduction: String {
        switch self {
        case .roman1960: RubricsGuide.introduction
        case .roman1954: Rubrics1954Guide.introduction
        }
    }
    var topics: [RubricsTopic] {
        switch self {
        case .roman1960: RubricsGuide.topics
        case .roman1954: Rubrics1954Guide.topics
        }
    }
}

nonisolated struct RubricsTopic: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let rules: [RubricsRule]

    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let content = ([title, summary] + rules.flatMap {
            [$0.title, $0.text] + $0.citations.map(\.label)
        }).joined(separator: " ")
        return words.allSatisfy { content.localizedStandardContains(String($0)) }
    }
}

nonisolated struct RubricsRule: Identifiable, Sendable {
    let id: String
    let title: String
    let text: String
    let citations: [RubricsCitation]
}

nonisolated struct RubricsCitation: Identifiable, Sendable {
    let label: String
    let url: URL
    var id: String { label }

    static func general(_ numbers: String, anchor: String) -> Self {
        Self(label: "General Rubrics (1960), \(numbers)",
             url: URL(string: "https://isidore.co/divinum/www/horas/Help/Rubrics/General%20Rubrics.html#\(anchor)")!)
    }

    static func breviary(_ numbers: String, anchor: String) -> Self {
        Self(label: "Breviary Rubrics (1960), \(numbers)",
             url: URL(string: "https://isidore.co/divinum/www/horas/Help/Rubrics/Breviary%201960.html#\(anchor)")!)
    }

    static func liber(_ pages: String, pdfPage: Int) -> Self {
        Self(label: "Liber Usualis (1961), \(pages)",
             url: URL(string: "https://propria.org/wp-content/uploads/2019/10/liber-usualis-1961.pdf#page=\(pdfPage)")!)
    }
}

/// Original explanatory summaries; source locations are kept beside each rule.
/// Editorial scope and the source map are documented in Tools/RubricsGuide/README.md.
nonisolated enum RubricsGuide {
    static let introduction = """
    The principles which govern the choice of the Office, its psalms, and its chant, \
    under the Roman rubrics of 1960. These explanations concern the Roman 1960 option; \
    other editions follow their own rules. The reference is available offline; \
    source links open online.
    """

    static let topics: [RubricsTopic] = [
        RubricsTopic(
            id: "order", title: "Understanding the Office of the day",
            summary: "The calendar, the Psalter, the Proper, and the Common.",
            rules: [
                RubricsRule(id: "calendar", title: "Begin with the celebration", text: """
                The weekday alone does not determine the Office. First consider the celebration appointed by the calendar: a Sunday, feria, vigil, feast, or day within an octave. Its place in the order of precedence determines which Office is celebrated when several observances meet. A feria is a weekday considered in the liturgical calendar; it need not be a day of low rank.

                Then consider the Hour. The same feast may use festal psalms at Lauds and Vespers, yet retain the weekday psalms at Prime, Terce, Sext, and None. At Vespers the following day's celebration may already have begun.
                """, citations: [.general("nos. 4–8, 21", anchor: "2"), .breviary("nos. 165–177", anchor: "4")]),
                RubricsRule(id: "books", title: "Where the several parts are found", text: """
                The Ordinary supplies the recurring order and prayers of the Hours. The Psalter distributes psalms and antiphons through the week. The Proper of the Season supplies texts for the course of the liturgical year; the Proper of Saints supplies those appointed for individual feasts. The Common supplies texts shared by a class of feasts, such as those of apostles or martyrs.

                An Office draws from these sources according to its appointed form. A feast's title therefore does not imply that every text is peculiar to that feast. Nor does the use of Sunday psalms make a weekday celebration into a Sunday.
                """, citations: [.breviary("nos. 166–171", anchor: "4B")]),
                RubricsRule(id: "particular-calendar", title: "The calendar being followed", text: """
                The universal calendar and a particular calendar need not give the same rank to a feast. A principal patron, the title of a church, or its dedication may have a higher rank in the place to which it belongs. Such a difference can affect both the choice of psalms and the right to First Vespers.

                When comparing the Office with another book or calendar, establish that both follow the same edition and the same calendar before applying a rule from one to the other.
                """, citations: [.general("nos. 38–50", anchor: "6"), .breviary("nos. 148–157", anchor: "3")])
            ]),
        RubricsTopic(
            id: "classes", title: "The four classes of liturgical days",
            summary: "What I, II, III, and IV class signify, and why rank alone is insufficient.",
            rules: [
                RubricsRule(id: "four-classes", title: "Class and kind of day", text: """
                Liturgical days are divided into four classes, I being the highest. Feasts belong to I, II, or III class; Sundays to I or II; ferias to any of the four classes; and vigils to I, II, or III. Days within the octaves of Easter and Pentecost are of I class, and those within the octave of Christmas of II class, its octave day being of I class. IV class belongs to ferias alone, not to a fourth class of saints' feasts.

                The class expresses liturgical rank. The kind of day must also be known: a I-class feria of Holy Week does not take the festive Office of a I-class feast. Special directions for such days remain in force.
                """, citations: [.general("nos. 8–12, 21–36", anchor: "2"), .general("nos. 66–67", anchor: "7"), .breviary("no. 173", anchor: "4G")]),
                RubricsRule(id: "feast-forms", title: "The three forms of a feast", text: """
                A I-class feast has the festive Office; a II-class feast the semifestive Office; and a III-class feast the ordinary Office. These names describe how the Hours are arranged. They determine such matters as the sources of the psalms, antiphons, and lessons.

                The semifestive Office resembles the festive Office at Matins, Lauds, and Vespers, but retains the weekday psalmody at Prime, Terce, Sext, and None. Compline is of Sunday. The ordinary Office generally retains the weekday psalmody, subject to the proper directions of the feast.
                """, citations: [.breviary("nos. 167–169, 177", anchor: "4C")]),
                RubricsRule(id: "same-rank", title: "Two days of the same class", text: """
                For celebrations falling on the same date, the table of precedence decides which is kept. The class number by itself does not settle every case. A II-class Sunday, for example, ordinarily takes precedence over a II-class feast of a saint; a II-class feast of the Lord takes the place of a II-class Sunday.

                The meeting of two celebrations at Vespers is governed by a distinct rule, explained under First and Second Vespers.
                """, citations: [.general("nos. 15–16, 91", anchor: "11"), .general("nos. 103–105", anchor: "15")])
            ]),
        RubricsTopic(
            id: "psalms", title: "Why the psalms change",
            summary: "Weekday psalmody, Sunday psalms, and the proper psalms of feasts.",
            rules: [
                RubricsRule(id: "weekday-psalms", title: "The weekday Psalter", text: """
                In the ferial Office the psalms ordinarily follow the current weekday. III-class feasts likewise retain the weekday psalmody, unless proper antiphons with psalms from the Common, or specially assigned psalms, are prescribed at a particular Hour.

                Thus the general rule is a starting point, not a reason to disregard a feast's own directions. A change at one Hour does not of itself require the same change at all the others.
                """, citations: [.breviary("nos. 169–171, 177, 196", anchor: "4E")]),
                RubricsRule(id: "festal-psalms", title: "The festive arrangement", text: """
                On I-class feasts, Matins and both Vespers take their appointed texts from the Proper or Common. Lauds uses the Sunday psalms of the first scheme. At Prime the psalms are 53 and the first two divisions of 118; at Terce, Sext, and None the Sunday psalms are used. Compline is also of Sunday.

                It would therefore be too broad to say that a feast simply takes all the Sunday psalms. Each Hour has its own direction, and the psalms of festal Vespers must be sought in the Proper or Common.
                """, citations: [.breviary("no. 167", anchor: "4C")]),
                RubricsRule(id: "semifestal-psalms", title: "The II-class distinction", text: """
                On II-class feasts, Matins, Lauds, and Vespers follow the festive arrangement. At Prime, Terce, Sext, and None, however, the antiphons and psalms are those of the weekday. The other parts are taken as the rubrics direct. Compline follows Sunday.

                A Tuesday II-class feast may therefore have Tuesday psalms at the daytime little Hours and Sunday psalms at Compline. Both selections belong to the same semifestive Office.
                """, citations: [.breviary("no. 168(a–d)", anchor: "4D")]),
                RubricsRule(id: "omitted-psalms", title: "Psalms displaced by a celebration", text: """
                A psalm which cannot be said at the Hour to which it is assigned is omitted, not moved to another Hour. The weekly Psalter is consequently not a requirement to make up every displaced psalm elsewhere in that week. Feasts and the seasons modify its actual course according to the rubrics.
                """, citations: [.breviary("nos. 196, 199", anchor: "5F")])
            ]),
        RubricsTopic(
            id: "compline", title: "Sunday Compline on a weekday",
            summary: "Why Psalm 4, Psalm 90, and Psalm 133 appear on certain feasts.",
            rules: [
                RubricsRule(id: "sunday-compline", title: "The rule for I- and II-class feasts", text: """
                Compline is treated separately from the other little Hours in many rubrics. On I-class feasts it is of Sunday, both after First Vespers and on the evening of the feast. On II-class feasts it is also of Sunday. The Sunday psalmody consists of Psalms 4, 90, and 133.

                For example, in a year when the Seven Sorrows of the Blessed Virgin Mary, a II-class feast, falls on Tuesday, September 15, as in 2026, these Sunday psalms are prescribed at Compline. The selection follows the feast's form of Office, although the civil weekday is Tuesday.
                """, citations: [.breviary("nos. 138, 167(b, h), 168(d)", anchor: "4C"), .liber("pp. 264–266", pdfPage: 388), .liber("p. xlvii, Calendar, September 15", pdfPage: 47)]),
                RubricsRule(id: "weekday-compline", title: "When the weekday returns", text: """
                On III-class feasts and in the ferial Office, Compline takes the current weekday's psalmody. The Sunday form is therefore not prescribed merely because a saint is celebrated.

                The evening Office must nevertheless be considered: First Vespers of a following I-class feast brings Sunday Compline with it. Conversely, the Compline following an ordinary Sunday's First Vespers on Saturday uses Saturday's psalms. Sunday Compline is said on Sunday evening.
                """, citations: [.breviary("nos. 166(b, h), 167(b), 169(e), 171(e)", anchor: "4B")]),
                RubricsRule(id: "special-compline", title: "Special seasons and Offices", text: """
                The days within the octave of Christmas also prescribe Sunday Compline. In the octaves of Easter and Pentecost Compline is likewise of Sunday; in the Easter octave it is said without antiphons. The Sacred Triduum and Offices of the Dead follow special directions.

                These provisions should be read with the general rule. Neither the weekday nor the class number alone accounts for every form of Compline.
                """, citations: [.breviary("nos. 172–176", anchor: "4G")])
            ]),
        RubricsTopic(
            id: "vespers", title: "First and Second Vespers",
            summary: "The preceding evening, the evening of the feast, and the meeting of two Offices.",
            rules: [
                RubricsRule(id: "two-vespers", title: "Two evenings of one celebration", text: """
                First Vespers belongs to a celebration which begins on the preceding evening. Second Vespers belongs to the evening of the celebration's own day. The terms do not mean that two Vespers are said on a single evening.

                Sundays and I-class feasts have First Vespers. II- and III-class feasts ordinarily begin with Matins of their own day. A II-class feast of the Lord, however, acquires First Vespers when it replaces a II-class Sunday. These rights remain subject to the rules governing the meeting of Offices.
                """, citations: [.general("nos. 5, 13, 37", anchor: "6")]),
                RubricsRule(id: "concurrence", title: "Which Vespers is celebrated?", text: """
                Concurrence is the meeting of the present day's Vespers with First Vespers of the following day. The Office of the higher class takes precedence. When the two are of equal class, Second Vespers of the present day is celebrated in full. The other celebration is commemorated only as the rubrics permit.

                For example, if a II-class feast falls on Saturday before a II-class Sunday, the feast retains its Vespers, with a commemoration of the Sunday; if the feast is of the Lord, the Sunday is not commemorated. If the following Sunday is I class, its First Vespers takes precedence instead. There is no division of Vespers into halves from the two Offices.
                """, citations: [.general("nos. 103–105", anchor: "15"), .general("no. 112(b)", anchor: "16")]),
                RubricsRule(id: "vespers-psalmody", title: "The psalms of First Vespers", text: """
                First Vespers of a Sunday draws its psalms from Saturday in the Psalter, except for proper assignments. First Vespers of a I-class feast draws from the Proper or Common. The following celebration may therefore supply the title of the Office while the weekly Psalter supplies its psalms.

                A feast which of itself lacks First Vespers, but acquires them under the rubrics, takes everything from Second Vespers, except whatever is given as proper to First Vespers.
                """, citations: [.breviary("nos. 164, 166(a), 167(a)", anchor: "4A")])
            ]),
        RubricsTopic(
            id: "precedence", title: "When celebrations coincide",
            summary: "Occurrence, transfers, omitted feasts, and commemorations.",
            rules: [
                RubricsRule(id: "occurrence", title: "One date, several observances", text: """
                Occurrence means that two or more Offices fall on the same day. The table of precedence determines the celebration. The lower Office may be commemorated, transferred, or omitted, according to the applicable rule; it is not necessarily celebrated on the next available weekday.

                I-class Sundays take precedence over feasts, with the stated exception of the Immaculate Conception on an Advent Sunday. The weekdays of Holy Week and other privileged days likewise have their own place in the table. Such provisions explain why a familiar feast may yield to the season.
                """, citations: [.general("nos. 15, 23, 91–94", anchor: "11")]),
                RubricsRule(id: "transfers", title: "A transferred feast", text: """
                In accidental occurrence, the right of transfer belongs to I-class feasts impeded by a day above them in the table. They are ordinarily transferred to the next following day which is neither I nor II class, retaining their rank. Particular rules govern such cases as the Annunciation transferred beyond Easter.

                Lower feasts accidentally impeded are commemorated or omitted for that year. Perpetual coincidence, in which the same celebrations meet every year, is governed by separate rules for reassignment.
                """, citations: [.general("nos. 95–102", anchor: "13")]),
                RubricsRule(id: "commemorations", title: "Remembered within another Office", text: """
                A commemoration is a limited remembrance within the Office being celebrated. In its usual form it adds the appropriate canticle antiphon, versicle, and collect after the collect of the day. It does not substitute the commemorated feast's psalms for those of the principal Office. Privileged commemorations are made at Lauds and Vespers; ordinary commemorations at Lauds only.

                Admission and number depend upon the day and the kind of commemoration; some are excluded altogether. A second title or an additional collect therefore need not signify a second complete Office. Nor does a commemorated Office impose its own hymn doxology upon the Office of the day.
                """, citations: [.general("nos. 106–114", anchor: "16"), .liber("p. lvii, for no. 109", pdfPage: 57), .breviary("nos. 250–253", anchor: "5R"), .breviary("no. 189", anchor: "5D")])
            ]),
        RubricsTopic(
            id: "seasons", title: "The seasons and exceptional Offices",
            summary: "The two schemes of Lauds, octaves, Holy Week, and the Office of the Dead.",
            rules: [
                RubricsRule(id: "lauds-schemes", title: "The first and second schemes", text: """
                The Psalter provides two schemes for Lauds each day and for Matins on Wednesday. The second scheme is used on the Sundays of Septuagesima, Lent, and Passiontide; on ferias of Advent, Septuagesima, Lent, and Passiontide; in the ferial Office of the September Ember Days; and on II- and III-class vigils outside Paschaltide. On the remaining days the first scheme is used.

                This is a rule about the Office actually celebrated. A feast occurring during a penitential season still follows its own prescribed arrangement; its Lauds is not changed to the ferial second scheme merely because the date falls in Lent.
                """, citations: [.breviary("no. 197", anchor: "5F"), .breviary("nos. 167(d), 168(a)", anchor: "4C")]),
                RubricsRule(id: "octaves", title: "The continuation of a feast", text: """
                An octave continues a feast through eight days. Under the 1960 rubrics only the octaves of Christmas, Easter, and Pentecost remain. They do not all follow one arrangement: the Easter and Pentecost octaves prescribe Sunday psalms at the little Hours, with the festal psalms at Prime.

                On days within the Christmas octave free from saints' feasts, the weekday antiphons and psalms remain at the daytime little Hours, while Compline is of Sunday. The other Hours have the assignments specified for that octave.
                """, citations: [.general("nos. 63–70", anchor: "7"), .breviary("nos. 172, 175–176", anchor: "4G")]),
                RubricsRule(id: "special-offices", title: "When the usual structure gives way", text: """
                The Sacred Triduum, the vigil of Christmas, and Offices of the Dead are expressly governed by directions in their own places. Their arrangement must not be inferred simply from the usual pattern for a feast or feria.

                In the Triduum the Gloria Patri is omitted; in the Office of the Dead its place is taken by Requiem aeternam as appointed. Hymns, antiphons, chapters, and short responsories also have specified omissions, some continuing until None of Saturday in the Easter octave. A shorter or markedly different Hour on such days can therefore be the prescribed form of the Office.
                """, citations: [.breviary("no. 173", anchor: "4G"), .breviary("nos. 185, 190, 201, 240, 243", anchor: "5")])
            ]),
        RubricsTopic(
            id: "texts", title: "Antiphons, lessons, and changing texts",
            summary: "Alleluia, the number of readings, and the parts retained through different feasts.",
            rules: [
                RubricsRule(id: "antiphons", title: "The antiphon and its psalm", text: """
                Where antiphons are said, they are always said in full both before and after the psalms or canticles, at the major and the little Hours alike. The asterisk within the opening of an antiphon marks the end of its intonation; it does not direct the remainder to be omitted before the psalm.

                The number of antiphons varies with the Hour and the Office, and several psalms may belong under one antiphon. Express exceptions must be observed: at the little Hours and Compline antiphons are omitted in the Sacred Triduum, on Easter Sunday and throughout its octave, and in the Office of the Dead on November 2.
                """, citations: [.breviary("nos. 190–191", anchor: "5E")]),
                RubricsRule(id: "alleluia", title: "The expression of the season", text: """
                Paschaltide adds Alleluia to antiphons which do not already have it. From Septuagesima to Holy Saturday, an Alleluia occurring in an antiphon is omitted. Versicles and short responsories have their own seasonal directions; a change prescribed for one part must not be extended indiscriminately to the rest.

                Thus a familiar text can return with a different conclusion while the identity of its psalm remains unchanged.
                """, citations: [.breviary("nos. 195, 206, 245", anchor: "5E")]),
                RubricsRule(id: "matins", title: "Three lessons or nine", text: """
                I- and II-class feasts ordinarily have three nocturns at Matins, with nine psalms and nine lessons. Sundays other than Easter and Pentecost, all ferias except those of the Triduum, vigils, III-class feasts, the days within the octave of Christmas, and the Saturday Office of Our Lady have one nocturn with nine psalms and three lessons. A feast of I or II class kept on a Sunday has its own three nocturns. Easter, Pentecost, and the days within their octaves have one nocturn with three psalms and three lessons. The Triduum, the octave day of Christmas, and All Souls also belong to the nine-lesson arrangement.

                These changes follow the form of Office. A shorter Matins need not be an abridgment chosen by the reader.
                """, citations: [.breviary("nos. 161–163, 211", anchor: "4A")]),
                RubricsRule(id: "fixed-parts", title: "What remains constant", text: """
                Certain parts retain their place through many different celebrations. Benedictus belongs to Lauds, Magnificat to Vespers, and Nunc dimittis to Compline. The short lesson at Prime is taken according to the season. The chapter and short responsory of Compline have their fixed assignments, subject to the omissions and manner of recitation prescribed for exceptional Offices and seasons.

                A new feast title consequently need not bring a new text or melody to every section of an Hour.
                """, citations: [.breviary("no. 200", anchor: "5F"), .breviary("nos. 240–245", anchor: "5O")])
            ]),
        RubricsTopic(
            id: "chant", title: "Psalm tones and the chant of the Office",
            summary: "The antiphon's mode, endings such as 8G, and seasonal hymn melodies.",
            rules: [
                RubricsRule(id: "tone-selection", title: "The psalm and its musical setting", text: """
                The choice of a psalm and the choice of its chant are distinct matters. The rubrics appoint the psalm for the Hour; its musical setting is read with the antiphon and the tone designation supplied in the chant book. The same psalm may consequently be sung to different tones under different antiphons.

                In ordinary antiphonal psalmody, the intonation joins the antiphon to the reciting note, and the termination prepares the return to the antiphon. Follow the tone and ending actually assigned. Feast class I or II is a liturgical rank, not an instruction to sing tone I or II.
                """, citations: [.breviary("no. 196", anchor: "5F"), .liber("pp. xxxii–xxxiv, 112–117", pdfPage: 32)]),
                RubricsRule(id: "tone-endings", title: "The number and the ending", text: """
                A designation such as 8G identifies the eighth tone and its G termination. The number names the tone; the letter, sometimes accompanied by a further distinguishing number, identifies a particular ending. It is neither the psalm number nor the class of the feast.

                Several endings may belong to one tone. The complete designation matters because the final cadence must agree with the appointed return to the antiphon. The vowels E u o u a e, where printed with the ending, represent the syllables of sæculorum Amen at the close of the doxology.
                """, citations: [.liber("pp. 112–117, 128, 133", pdfPage: 224)]),
                RubricsRule(id: "canticle-tones", title: "Psalms and Gospel canticles", text: """
                In ordinary psalmody the first verse has the intonation; subsequent verses begin upon the reciting note. The intonation is repeated at each verse of Benedictus, Magnificat, and Nunc dimittis.

                The Liber Usualis also permits the more ornate intonation and mediation for Benedictus and Magnificat, at least on the principal feasts of I and II class. This permission should not be turned into a requirement that every psalm on such a feast have a solemn tone.
                """, citations: [.liber("pp. 112–113", pdfPage: 224)]),
                RubricsRule(id: "hymn-melodies", title: "Hymn text and hymn melody", text: """
                Hymns follow their own musical directions. In the 1961 Liber Usualis, the second Sunday melody marked for solemn feasts at the little Hours is retained for I-class feasts, while specified seasonal melodies remain in use under the revised directions. Thus a recurring hymn text may have a seasonal melody even where the psalms are of the weekday.

                The prescribed doxology must be distinguished from the melody. Each hymn keeps the conclusion assigned to it in the Breviary: under the 1960 rubrics neither a feast, nor a season, nor a commemorated Office changes that conclusion. The revised directions in the Liber Usualis must also be consulted where an older rubric remains printed in the body of the book.
                """, citations: [.liber("pp. lxviii–lxix", pdfPage: 68), .breviary("nos. 186–189", anchor: "5D")])
            ]),
        RubricsTopic(
            id: "sources", title: "Sources and use of this reference",
            summary: "The 1960 Code of Rubrics and the 1961 Liber Usualis.",
            rules: [
                RubricsRule(id: "rubrics-source", title: "The governing rubrics", text: """
                References to the General Rubrics and the Breviary Rubrics use the continuous numbered paragraphs of the Code of Rubrics promulgated in 1960 and effective from 1961. General Rubrics covers nos. 1–137; General Rubrics of the Roman Breviary covers nos. 138–268. The linked English transcriptions are hosted by the Divinum Officium mirror at Isidore.

                These lessons are explanatory summaries, not verbatim translations or a complete replacement for the liturgical books. Particular rubrics qualify the general rules. The directions for the celebration and the Hour in question must therefore be read together.
                """, citations: [.general("no. 3; complete text", anchor: "1"), .breviary("nos. 138–268", anchor: "top")]),
                RubricsRule(id: "chant-source", title: "The chant reference", text: """
                Musical references are to The Liber Usualis, with Introduction and Rubrics in English, edited by the Benedictines of Solesmes, Desclée & Co., 1961. Page references follow the printed pagination: Roman numerals identify the introductory pages, and Arabic numerals the body of the book. The links open the corresponding starting page in an online scan.

                The section Changes in the Liber Usualis gives the revisions required by the 1960 rubrics. It must be read with the older directions retained in the body of the volume. The musical explanations describe this edition's practice; the practical examples in Guide to Chant develop its notation and psalm-tone formulas.
                """, citations: [.liber("pp. li–lxi, lxviii–lxix, lxxxii", pdfPage: 51)]),
                RubricsRule(id: "using-reference", title: "Reading an unexpected Office", text: """
                Establish the edition and calendar, the celebration and its class, and whether the Hour belongs to the day's Office or to the following celebration's First Vespers. Then consult the appointed form of that Hour, including any directions peculiar to the season or feast. Finally, read the chant designation with its antiphon.

                This order keeps separate the questions which a single date cannot answer: which celebration is kept, which psalms belong to the Hour, and how those texts are sung. The topics above give the governing principles and a few examples, rather than a separate rule for every date.
                """, citations: [.general("nos. 7, 91, 103–105", anchor: "11"), .breviary("nos. 165–177, 196", anchor: "4B"), .liber("pp. 112–117", pdfPage: 224)])
            ])
    ]
}
