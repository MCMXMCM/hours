import Foundation

extension RubricsCitation {
    /// The earlier General Rubrics must be read with the subsequent Additions.
    nonisolated private static func earlierRoman(_ label: String, file: String) -> Self {
        Self(label: label, url: URL(string:
            "https://github.com/DivinumOfficium/divinum-officium/blob/79a596eeb68268c35334f25122af7ffc376934d5/web/www/horas/Help/Rubrics/\(file).txt"
        )!)
    }

    nonisolated static func additions(_ title: String, numbers: String, file: String) -> Self {
        earlierRoman("Additions to the Roman Breviary, tit. \(title), \(numbers)", file: file)
    }

    nonisolated static func earlierGeneral(_ title: String, numbers: String, file: String) -> Self {
        earlierRoman("Earlier General Rubrics, tit. \(title), \(numbers)", file: file)
    }

    nonisolated static func liberBrevior(_ pages: String, pdfPage: Int) -> Self {
        Self(label: "Liber Brevior (1954), \(pages)", url: URL(string:
            "https://cdn.restorethe54.com/media/pdf/liber-brevior-1954.pdf#page=\(pdfPage)"
        )!)
    }
}

/// Principles of the Roman Office before the simplification of 1955.
/// These summaries read the earlier rubrics in the light of the Divino afflatu additions.
nonisolated enum Rubrics1954Guide {
    static let introduction = """
    The principles of the Roman Office in its 1954 form, following the Psalter of \
    St Pius X and the earlier rubrics with their additions. Its ranks, octaves, and \
    order of Vespers differ from those of 1960. The reference is available offline; \
    citations beside each rule and the Sources page lead to the authorities online.
    """

    static let topics: [RubricsTopic] = [
        RubricsTopic(
            id: "order", title: "Understanding the Office of the day",
            summary: "The calendar, the weekly Psalter, and the Proper and Common.",
            rules: [
                RubricsRule(id: "framework", title: "The earlier order of the Office", text: """
                The 1954 form follows the Roman Psalter arranged under St Pius X. Its ordinary rule is to take the psalms of each Hour from the current weekday. The celebration, its rank, and its particular privileges determine when that rule gives way to festal or proper psalmody.

                These directions belong to the earlier system of doubles, semidoubles, and simples. They must not be interpreted by substituting the four classes of the 1960 code. Nor should the older General Rubrics be read without the subsequent Additions, which changed, among other matters, the distribution of the psalms.
                """, citations: [.additions("I", numbers: "nos. 1–8", file: "N1")]),
                RubricsRule(id: "books", title: "How the parts are chosen", text: """
                The Psalter supplies the weekly psalms and antiphons. The Proper of the Season and the Proper of Saints supply the texts appointed for particular days; the Common supplies those shared by a class of feasts. One Office may draw from all these sources.

                Thus a saint's feast may retain the weekday psalms while taking its chapter, hymn, lessons, and collect from the Proper or Common. A proper antiphon assigned to a particular major Hour may also bring its own psalms, without changing the psalmody of the other Hours.
                """, citations: [.additions("I", numbers: "nos. 3–7", file: "N1")])
            ]),
        RubricsTopic(
            id: "classes", title: "Doubles, semidoubles, and simples",
            summary: "The earlier ranks, their privileges, and their limits.",
            rules: [
                RubricsRule(id: "ranks", title: "Rank and rite", text: """
                Among feasts the principal degrees are double of the first class, double of the second class, greater double, double, semidouble, and simple. The rite governs the manner of celebrating the Office; the degree of solemnity and the other privileges of a day help determine its precedence.

                The words “first class” and “second class” here qualify a double. They do not establish the fourfold classification of all liturgical days used in 1960. Sundays, privileged ferias, vigils, and octaves have their own rules.
                """, citations: [.additions("II", numbers: "nos. 1–2", file: "N2"), .additions("IV", numbers: "nos. 1–4", file: "N4")]),
                RubricsRule(id: "double-antiphons", title: "What is doubled", text: """
                In a double Office the antiphons at Matins, Lauds, and Vespers are said in full both before and after the psalms. At the other Hours they are not doubled merely because the feast is a double. In a semidouble or simple Office the antiphon is ordinarily begun before the psalm and completed afterwards.

                “Double” therefore describes a liturgical rite; it does not mean that the psalms or the entire Office are repeated. Proper directions for particular days remain in force.
                """, citations: [.earlierGeneral("I", numbers: "no. 4", file: "R01"), .earlierGeneral("XXI", numbers: "nos. 7–8", file: "R21")]),
                RubricsRule(id: "lessons", title: "Nine lessons and three lessons", text: """
                Doubles and semidoubles ordinarily have nine lessons at Matins. Simple feasts and the Saturday Office of Our Lady have three: ordinarily the first two of the feria, from the occurring Scripture, and the third of the feast or of Our Lady. Where a saint has two proper lessons, only the first is of Scripture. Special Offices, including those of Easter and Pentecost, have their own arrangement.

                The number of lessons helps identify the form of an Office, but does not by itself decide whether its psalms are of the weekday or of the feast.
                """, citations: [.earlierGeneral("I", numbers: "no. 5", file: "R01"), .earlierGeneral("III", numbers: "no. 4", file: "R03"), .earlierGeneral("XXVI", numbers: "no. 4", file: "R26"), .additions("I", numbers: "nos. 2–6, 8", file: "N1")])
            ]),
        RubricsTopic(
            id: "psalms", title: "Why the psalms change",
            summary: "The weekday rule and the feasts which receive festal psalmody.",
            rules: [
                RubricsRule(id: "weekday", title: "The ordinary rule", text: """
                At each Hour the psalms ordinarily belong to the current weekday. This remains true on many saints' feasts, including doubles and greater doubles which do not enjoy a special exception. Their antiphons also ordinarily come from the weekday Psalter, while other parts are of the feast.

                If such a feast has proper or specially assigned antiphons at a major Hour, it retains them with their psalms at that Hour. The remaining Hours continue to follow the weekday unless another rule intervenes.
                """, citations: [.additions("I", numbers: "nos. 1, 3, 5", file: "N1")]),
                RubricsRule(id: "festal", title: "The principal exceptions", text: """
                The festal arrangement belongs to all nine-lesson feasts of Our Lord, Our Lady, the Angels, St John the Baptist, St Joseph, the Apostles, and the Evangelists, and to doubles of the first and second class of other saints.

                In these Offices the psalms at Lauds, Prime, Terce, Sext, None, and Compline are of Sunday, save that at Prime Psalm 53 takes the place of Psalm 117, even when the feast falls on a Sunday. At Matins and Vespers they are from the Common, unless special psalms are assigned. The Additions extend this arrangement to certain vigils and days connected with the universal octaves of the Lord; special directions govern Christmas Eve, the last three days of Holy Week, and All Souls.
                """, citations: [.additions("I", numbers: "no. 2", file: "N1")]),
                RubricsRule(id: "little-hours", title: "A difference from 1960", text: """
                A double of the second class in this earlier system receives Sunday psalms at the little Hours as well as at Compline. This differs from the ordinary 1960 rule for a second-class feast, which retains weekday psalmody at Prime, Terce, Sext, and None.

                When comparing editions, establish first which rubrics govern the Office. The same feast and the same civil weekday need not produce the same psalmody.
                """, citations: [.additions("I", numbers: "no. 2", file: "N1"), .breviary("no. 168(b–d), for comparison", anchor: "4D")])
            ]),
        RubricsTopic(
            id: "compline", title: "Sunday Compline on a weekday",
            summary: "Why Psalm 4 may appear, and why the hymn or prayers may vary.",
            rules: [
                RubricsRule(id: "sunday-compline", title: "Sunday psalms do not require a Sunday date", text: """
                The Sunday set at Compline comprises Psalms 4, 90, and 133, in the numbering of the Latin Psalter. These are also appointed on the feasts which receive festal psalmody under the earlier rubrics. Thus a Marian feast of nine lessons may have Sunday Compline even when it falls on Tuesday.

                The ordinary weekday set is retained on feasts outside these exceptions. Neither the name “double” alone nor the civil weekday alone is sufficient to decide the matter.
                """, citations: [.additions("I", numbers: "nos. 1–3, 5", file: "N1"), .liberBrevior("pp. 582–584", pdfPage: 616)]),
                RubricsRule(id: "compline-variations", title: "The same psalms, with other changes", text: """
                The melody of Te lucis ante terminum varies with the season and feast. Its conclusion may also change according to the earlier rules for hymn doxologies. Sunday psalms therefore do not imply that every other part of Compline has its ordinary Sunday form.

                The preces are omitted in double Offices and within octaves. A commemoration of a double or an octave can also suppress the dominical preces in an otherwise less solemn Office. These changes concern the prayers surrounding the psalms, rather than the choice of the psalms themselves.
                """, citations: [.liberBrevior("pp. 584–586", pdfPage: 618), .earlierGeneral("XVIII", numbers: "no. 1", file: "R18"), .additions("VIII", numbers: "nos. 1, 3", file: "N8")])
            ]),
        RubricsTopic(
            id: "vespers", title: "First and Second Vespers",
            summary: "The preceding evening, the feast's own evening, and divided Vespers.",
            rules: [
                RubricsRule(id: "two-vespers", title: "Where the evening belongs", text: """
                First Vespers are celebrated on the evening before a feast; Second Vespers on the evening of the feast itself. Doubles and semidoubles ordinarily have both, subject to the claims of the adjoining Office. The earlier system grants First Vespers much more widely than the 1960 code.

                A simple feast has no Second Vespers: its Office ends at None. Its First Vespers, when admitted, begin at the chapter, the preceding psalms being of the feria. When a preceding Office of nine lessons concurs, the simple feast receives only a commemoration at Vespers; after a double of the first or second class, not even that.
                """, citations: [.earlierGeneral("I", numbers: "no. 3", file: "R01"), .earlierGeneral("II", numbers: "no. 3", file: "R02"), .earlierGeneral("III", numbers: "no. 3", file: "R03"), .earlierGeneral("XI", numbers: "nos. 3, 8", file: "R11"), .additions("VII", numbers: "nos. 1–2", file: "N7")]),
                RubricsRule(id: "divided-vespers", title: "When Vespers change at the chapter", text: """
                Concurrence is the meeting of the preceding day's Second Vespers with the following day's First Vespers. The earlier rubrics may give the whole Hour to one Office, or divide it at the chapter.

                In a divided Office the psalms and their antiphons belong to the preceding celebration; from the chapter onwards the texts belong to the following celebration, with the prescribed commemoration of the preceding. This is the meaning of “from the chapter” or a capitulo. It accounts for an evening in which the psalms and the later texts appear to belong to different feasts.

                Equal solemnity can lead to this arrangement, but does not invariably do so. The dignity of the celebrations, Sunday privileges, and special rules for Offices of the same Person must also be considered.
                """, citations: [.earlierGeneral("XI", numbers: "nos. 1–4", file: "R11"), .additions("II", numbers: "nos. 1–2", file: "N2"), .additions("VI", numbers: "nos. 1–4", file: "N6")]),
                RubricsRule(id: "sunday-vespers", title: "Sunday's First Vespers and Saturday psalms", text: """
                Sunday's First Vespers ordinarily use Saturday's psalms and antiphons. In Advent the antiphons are taken from Sunday's proper Lauds, with the Saturday psalms; a privileged octave of the Lord may require its own arrangement.

                Ordinary Sundays yield Vespers to doubles of the first or second class and to feasts of the Lord under the stated rules. Their claims against lesser feasts are stronger. Thus the right to First Vespers and the choice of psalms are related questions, but are not the same question.
                """, citations: [.additions("VI", numbers: "nos. 1–3", file: "N6")])
            ]),
        RubricsTopic(
            id: "precedence", title: "When celebrations meet",
            summary: "Occurrence, concurrence, transfer, and commemoration.",
            rules: [
                RubricsRule(id: "occurrence", title: "Two celebrations on one date", text: """
                Occurrence concerns celebrations falling on the same day; concurrence concerns their meeting at Vespers. Rank, solemnity, the dignity of the feast, and the privileges of the season or local calendar govern the outcome. A rank label alone does not express the whole order of precedence.

                An ordinary Sunday yields to a double of the first or second class, or to a nine-lesson feast of the Lord, but not to their octave days. The Sunday is then commemorated at both Vespers and at Lauds, and its homily is read as the ninth lesson. This differs from the 1960 rule under which a second-class Sunday ordinarily takes precedence over a second-class feast of a saint. The greater Sundays have their own protections.
                """, citations: [.additions("II", numbers: "nos. 1–2", file: "N2"), .additions("IV", numbers: "nos. 1–2", file: "N4"), .general("nos. 15–16, 91, for comparison", anchor: "11")]),
                RubricsRule(id: "transfer", title: "Moving a feast, or commemorating it", text: """
                An impeded double of the first or second class is transferred under the prescribed conditions to an admissible day. Sundays and other privileged days restrict the dates available. Lesser doubles, greater doubles, and semidoubles do not ordinarily acquire a transfer merely because they are accidentally impeded; they are commemorated or omitted according to the rubrics.

                A commemoration preserves a subordinate celebration within the principal Office, ordinarily by an antiphon, versicle, and collect at the appointed Hour. It does not supply a second complete Office. Earlier rules also allow effects on lessons and hymn conclusions in specified cases. The number and order of commemorations depend upon the privileges of the day.
                """, citations: [.additions("IV", numbers: "nos. 3–5", file: "N4"), .additions("VII", numbers: "nos. 1–5", file: "N7"), .additions("VIII", numbers: "no. 1", file: "N8"), .earlierGeneral("IX", numbers: "no. 8", file: "R09")])
            ]),
        RubricsTopic(
            id: "seasons", title: "Octaves, vigils, and special days",
            summary: "Why a feast can continue to affect the following week.",
            rules: [
                RubricsRule(id: "octaves", title: "Not all octaves are alike", text: """
                An octave prolongs the observance of a feast to its eighth day. The earlier calendar contains more octaves than the 1960 calendar, and their privileges differ. A privileged octave may strongly restrict other Offices; a common octave has a less extensive claim.

                In a simple octave only the octave day is observed, with the simple rite; the intervening days do not receive an Office or commemoration merely by belonging to that octave. The presence of an octave, and its kind, must therefore be established before applying its rules. Not every feast is assigned one.
                """, citations: [.additions("III", numbers: "nos. 1–5", file: "N3")]),
                RubricsRule(id: "octave-psalms", title: "The octave does not settle the psalms by itself", text: """
                The universal octaves of the Lord belong to the festal exceptions to the weekday Psalter. Other octaves ordinarily retain weekday psalms, with the remaining parts drawn from the feast unless proper texts are provided. A particular day's directions may supply a further exception.

                This explains how the same feast can continue to furnish chapters, lessons, or collects through a week in which the psalms nevertheless change from day to day.
                """, citations: [.additions("I", numbers: "nos. 2–3, 7", file: "N1")]),
                RubricsRule(id: "vigils", title: "A vigil is not simply First Vespers", text: """
                A vigil is a liturgical day of preparation, with its own Office or commemoration according to the rubrics. First Vespers are the opening evening Hour of a celebration. A day may therefore have a vigil Office before the feast begins at Vespers.

                Christmas Eve, the last three days of Holy Week, and All Souls have specially prescribed psalms and forms. Their proper directions must be consulted before applying the ordinary rules for either a feast or a feria.
                """, citations: [.earlierGeneral("VI", numbers: "nos. 1–3", file: "R06"), .additions("I", numbers: "no. 2", file: "N1")])
            ]),
        RubricsTopic(
            id: "texts", title: "Why other texts appear or disappear",
            summary: "Hymn conclusions, Prime, preces, and the Athanasian Creed.",
            rules: [
                RubricsRule(id: "doxology", title: "The conclusion of a hymn", text: """
                The earlier rubrics prescribe a proper final stanza for hymns according to the feast or season, where the metre admits it and the hymn has no conclusion which must be retained.

                When several observances have a proper conclusion, that of the Office actually celebrated comes first. If it has none, an eligible commemorated Office may supply it; failing that, the common octave or the season may do so. Special restrictions remain, including the rule that the Advent Office of the Season does not take the conclusion Qui natus es de Virgine. A commemoration can therefore affect words sung elsewhere in the Office.
                """, citations: [.earlierGeneral("XX", numbers: "nos. 4–8", file: "R20"), .additions("VIII", numbers: "no. 1", file: "N8")]),
                RubricsRule(id: "prime", title: "The short lesson and versicle at Prime", text: """
                On feasts, whether their psalms be of the weekday or of Sunday, the short lesson at Prime is the chapter of None, from the Proper if there is one, otherwise from the Common. On Sundays and ferias it is the lesson assigned in the Psalter. A proper versicle in Prime's short responsory may likewise follow the Office, an eligible commemoration, the octave, or the season according to the prescribed order.

                These are further reasons why retaining the weekday psalms does not mean retaining every weekday text.
                """, citations: [.earlierGeneral("XV", numbers: "no. 3", file: "R15"), .additions("I", numbers: "no. 5", file: "N1"), .additions("VIII", numbers: "no. 1", file: "N8")]),
                RubricsRule(id: "preces", title: "Preces, suffrage, and Quicumque", text: """
                The presence of the preces and the suffrage depends upon the rite, season, and commemorations. A commemorated double or octave can suppress the suffrage and the dominical preces; this does not, on a feria, automatically suppress the ferial preces when these are due.

                The Athanasian Creed, Quicumque vult, is appointed at Prime on Trinity Sunday and on Sundays after Epiphany and Pentecost when the Sunday Office is celebrated. On those Sundays it is omitted when a double or an octave is commemorated. It is therefore not said on the Sundays of Advent, of Septuagesima and Lent, or of Paschaltide. Its use is more frequent than under the 1960 rubrics, yet still conditional.
                """, citations: [.additions("VIII", numbers: "nos. 2–3", file: "N8"), .earlierGeneral("XXXIII", numbers: "no. 2", file: "R33"), .earlierGeneral("XXXIV", numbers: "nos. 1–2", file: "R34")])
            ]),
        RubricsTopic(
            id: "chant", title: "The psalms and their tones",
            summary: "The antiphon, the psalm formula, and melodies proper to a feast or season.",
            rules: [
                RubricsRule(id: "tone", title: "The psalm and the manner of singing it", text: """
                The rubrics determine which psalm and antiphon belong to the Hour. The chant book then gives their musical setting. A psalm-tone indication, such as 8G, names the tone and its ending; it does not name a feast's rank or prescribe a different psalm.

                The tone and ending belong with the assigned antiphon. The same psalm may accordingly be sung to different formulas in different Offices. In the Sunday Compline of the Liber Brevior, Miserere and the Paschal Alleluia carry the indication 8. G, followed by the setting of Psalm 4.
                """, citations: [.additions("I", numbers: "nos. 1–3", file: "N1"), .liberBrevior("pp. 552–554", pdfPage: 586), .liberBrevior("p. 582", pdfPage: 616)]),
                RubricsRule(id: "melodies", title: "Feast and season in the melody", text: """
                A hymn may retain its ordinary words while receiving the melody appointed for a feast or season. Te lucis provides a familiar example: the chant book distinguishes ordinary Sundays and lesser feasts, solemn feasts, and Paschal use, with further proper directions.

                Musical directions must be applied to the chant for which they are given. The Liber Brevior, for example, permits a solemn Deus in adjutorium at Vespers of solemn feasts; this does not prescribe a solemn formula for every part of the Office. The rank of a feast is not a general instruction to replace all its melodies.
                """, citations: [.liberBrevior("p. 551; pp. 584–586", pdfPage: 585)]),
                RubricsRule(id: "chant-study", title: "Reading the notation", text: """
                Guide to Chant explains the staff, neumes, and psalm-tone endings through musical examples. Its source is the 1961 Liber Usualis. Those lessons may be consulted for the notation; the choice of Office and the earlier rubrical observances must still be governed by the 1954 reference and its sources.
                """, citations: [.liberBrevior("pp. 552–554", pdfPage: 586), .liberBrevior("p. 582", pdfPage: 616), .liber("pp. 112–117, for the musical examples", pdfPage: 224)])
            ]),
        RubricsTopic(
            id: "sources", title: "Sources and the use of this reference",
            summary: "The earlier General Rubrics, their Additions, and the chant book.",
            rules: [
                RubricsRule(id: "source-rubrics", title: "Read the General Rubrics with the Additions", text: """
                This reference presents original explanatory summaries, not a complete translation or a substitute for the Breviary's proper directions. “1954” identifies the earlier Roman form represented here; it is not the title of a newly promulgated code in that year.

                The Earlier General Rubrics are cited by title and numbered paragraph. The Additions to the Roman Breviary, following Divino afflatu and the subsequent decrees, modify those rules. Where the older text and the Additions differ, the older rule must not be applied in isolation. In particular, the distribution of psalms is governed by title I of the Additions.

                The links open the Latin transcriptions preserved by Divinum Officium. Printed pre-1955 breviaries, such as the 1942 Breviarium Romanum, provide the corresponding historical framework and the proper Offices. Citations to the 1960 code elsewhere in this guide are expressly for comparison.
                """, citations: [.earlierGeneral("I", numbers: "nos. 1–7", file: "R01"), .additions("I", numbers: "nos. 1–8", file: "N1"), RubricsCitation(label: "Breviarium Romanum (1942), Pars autumnalis", url: URL(string: "https://librinostri.catholica.cz/download/BrevRom1942Autu-textOCRtri.pdf")!)]),
                RubricsRule(id: "source-music", title: "The musical witness", text: """
                The Liber Brevior, published by Desclée and the Gregorian Institute of America in 1954, supplies the musical examples cited here, including Sunday Vespers and Compline. It is a chant collection, not a complete Breviary; its Sunday forms do not establish that those forms must be used every day.

                Page references are to the printed pages. The source links open the corresponding portion of the scan. The musical setting and the rubric selecting an Office are cited separately where both are needed to explain a result.
                """, citations: [.liberBrevior("pp. 551–554, 580–586", pdfPage: 585)]),
                RubricsRule(id: "use", title: "When an Office differs from the expected form", text: """
                First establish the edition and calendar, then the celebration and its rank, and finally the Hour. For Vespers consider the adjoining day as well. Examine any privileged season, vigil, octave, proper antiphon, or commemoration before applying the ordinary weekday rule.

                These principles explain why an exception may occur; they do not establish that every unexpected display is correct. A particular case must agree with the proper directions and the applicable rules of occurrence or concurrence.
                """, citations: [.additions("I", numbers: "nos. 1–3", file: "N1"), .additions("II", numbers: "nos. 1–2", file: "N2"), .additions("IV", numbers: "nos. 1–5", file: "N4"), .additions("VI", numbers: "nos. 1–4", file: "N6")])
            ])
    ]
}
