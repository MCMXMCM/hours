import HoursCore
import SQLite3
@testable import Hours
import XCTest

@MainActor
final class OfficeReaderSectionBuilderTests: XCTestCase {
    func testDistinctEnglishOmitsEquivalentDisplayedText() {
        XCTAssertNil(
            OfficeBilingualText.distinctEnglish(
                " 1 PET 5:8-9 ",
                from: "1 Pet 5:8-9"
            )
        )
        XCTAssertEqual(
            OfficeBilingualText.distinctEnglish(
                "Blessing:",
                from: "Benedictio:"
            ),
            "Blessing:"
        )
    }

    func testSearchResultUsesSemanticTitlesInsteadOfInheritedSourceHeadings() {
        let context = LiturgicalUsageContext(
            firstDate: LocalDay(year: 1962, month: 6, day: 1),
            lastDate: LocalDay(year: 2100, month: 6, day: 1),
            hour: .matins,
            observanceTitleLatin: "Feria Quinta"
        )
        let inheritedPaterReading = LiturgicalSearchResult(
            id: "acts-reading",
            kind: .prayer,
            titleLatin: "Pater",
            latin: "Respóndit autem Paulus, annuénte sibi prǽside dícere.",
            contexts: [context]
        )
        let confiteor = LiturgicalSearchResult(
            id: "confiteor",
            kind: .prayer,
            titleLatin: "Prex poenitentialis",
            latin: "Confíteor Deo omnipoténti.",
            contexts: [context]
        )
        let hymn = LiturgicalSearchResult(
            id: "hymn",
            kind: .hymn,
            titleLatin: "Hymnus",
            latin: "Te lucis ante términum.",
            contexts: [context]
        )
        let incipit = LiturgicalSearchResult(
            id: "incipit",
            kind: .opening,
            titleLatin: "Incipit",
            latin: "Deus in adiutórium meum inténde.",
            contexts: [context]
        )

        XCTAssertEqual(
            SearchResultPresentation.title(for: inheritedPaterReading),
            "Matins Reading"
        )
        XCTAssertEqual(SearchResultPresentation.title(for: confiteor), "Confiteor")
        XCTAssertEqual(SearchResultPresentation.title(for: hymn), "Hymn")
        XCTAssertEqual(SearchResultPresentation.title(for: incipit), "Incipit")
    }

    func testOutlineSheetRowIDsDoNotCollideWithReaderSectionIDs() {
        let entries = [
            OfficeReaderOutlineEntry(id: "hymn", title: "Hymnus"),
            OfficeReaderOutlineEntry(
                id: "canticle",
                title: "Canticum: Nunc dimittis"
            ),
        ]
        let rowIDs = entries.map {
            OfficeReaderSectionJump.outlineRowID(for: $0.id)
        }

        XCTAssertEqual(Set(rowIDs).count, rowIDs.count)
        for entry in entries {
            XCTAssertFalse(
                rowIDs.contains(entry.id),
                "Sheet rows must not reuse \(entry.id); ScrollViewReader matches the first view with that ID, so a still-presented Hymnus row wins over a lazy, unrealized hymn."
            )
        }
    }

    func testBundledCollectOutsideTheCatalogTakesTheChantedFrameOnce() async throws {
        // St Anthony on a Friday (17 January 2025) has no 2026 counterpart:
        // its collect takes the chanted frame of a collect of the same class.
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(forResource: "base-office", withExtension: "sqlite", subdirectory: "Resources")
                ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(on: LocalDay(year: 2025, month: 1, day: 17), hour: .vespers)
        let displayed = OfficeReaderSectionBuilder.displaySections(from: office.sections, format: office.format)
        let collect = try XCTUnwrap(displayed.firstIndex { $0.title == "Oratio" })
        let part = Array(displayed[collect...])
        XCTAssertNotNil(part.first?.chant, "The versicle is sung")
        XCTAssertTrue(part.contains { $0.chant == nil && $0.latin.hasPrefix("Intercéssio nos, quǽsumus, Dómine, beáti Antónii") })
        XCTAssertEqual(
            part.filter { $0.chant == nil && $0.latin.contains("Dómine, exáudi oratiónem meam") }.count, 0,
            "The versicle's words are shown once, in its score"
        )
        XCTAssertTrue(part.contains { $0.title == "Conclusio" && $0.chant != nil })
    }

    func testBundledCommemorationFollowsTheScoredCollectAndPrecedesTheConclusion() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2029, month: 9, day: 21),
            hour: .vespers
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        // The reader shows a part's first line as its heading.
        func index(_ matches: (OfficeSection) -> Bool) throws -> Int {
            try XCTUnwrap(displayed.firstIndex(where: matches))
        }
        let collect = try index { $0.latin.contains("Beáti Apóstoli et Evangelístæ Matthǽi") }
        let commemoration = try index {
            "\($0.title)\n\($0.latin)".contains("Commemoratio Feria Sexta Quattuor Temporum Septembris")
        }
        let conclusion = try index { $0.title == "Conclusio" }
        XCTAssertLessThan(collect, commemoration)
        XCTAssertLessThan(commemoration, conclusion)
        XCTAssertTrue(
            displayed.contains { $0.title == "Oratio" && $0.chant != nil },
            "The collect keeps its scored versicles"
        )
    }

    func testBundledSeptember5ComplineHymnusOutlineTargetsTheHymn() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 9, day: 5),
            hour: .compline
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let outline = OfficeReaderOutlineBuilder.entries(from: displayed)
        let hymnus = try XCTUnwrap(
            outline.first { $0.title == "Hymnus" }
        )
        let nuncDimittis = try XCTUnwrap(
            outline.first { $0.title.localizedCaseInsensitiveContains("Nunc") }
        )
        let hymnusSection = try XCTUnwrap(
            displayed.first { $0.id == hymnus.id }
        )

        XCTAssertNotEqual(hymnus.id, nuncDimittis.id)
        XCTAssertEqual(hymnusSection.kind, .hymn)
        XCTAssertNotEqual(
            OfficeReaderSectionJump.outlineRowID(for: hymnus.id),
            hymnus.id
        )
    }

    func testOutlineContainsOnlyVisibleSectionHeadingsInOrder() {
        let sections = [
            section(
                id: "opening",
                title: "  Incipit  ",
                latin: "Deus in adiutórium."
            ),
            section(
                id: "opening-continuation",
                title: "",
                latin: "Dómine, ad adiuvándum me festína."
            ),
            section(
                id: "hymn",
                kind: .hymn,
                title: "Hymnus",
                latin: "Nunc Sancte nobis Spíritus."
            )
        ]

        XCTAssertEqual(
            OfficeReaderOutlineBuilder.entries(from: sections),
            [
                OfficeReaderOutlineEntry(
                    id: "opening",
                    title: "Incipit"
                ),
                OfficeReaderOutlineEntry(
                    id: "hymn",
                    title: "Hymnus"
                )
            ]
        )
    }

    func testOutlineRestoresNumberedLessonsAndTeDeumFromMatinsContent() {
        let sections = [
            section(
                id: "pater",
                kind: .prayer,
                title: "Pater",
                latin: "Pater noster."
            ),
            section(
                id: "lesson-1",
                kind: .rubric,
                title: "",
                latin: "  Lectio 1  "
            ),
            section(
                id: "lesson-text",
                kind: .reading,
                title: "",
                latin: "In princípio creávit Deus."
            ),
            section(
                id: "te-deum",
                title: "",
                latin: "Te Deum laudámus"
            )
        ]

        XCTAssertEqual(
            OfficeReaderOutlineBuilder.entries(from: sections),
            [
                OfficeReaderOutlineEntry(id: "pater", title: "Pater"),
                OfficeReaderOutlineEntry(id: "lesson-1", title: "Lectio 1"),
                OfficeReaderOutlineEntry(id: "te-deum", title: "Te Deum")
            ]
        )
    }

    func testOutlineDoesNotPromoteLessonTextThatOnlyBeginsWithLectio() {
        let sections = [
            section(
                id: "homily",
                kind: .reading,
                title: "",
                latin: "Léctio sancti Evangélii secúndum Lucam"
            )
        ]

        XCTAssertTrue(
            OfficeReaderOutlineBuilder.entries(from: sections).isEmpty
        )
    }

    func testAuthoritativeSectionsShareOneHeadingWithoutChangingOrder() {
        let blessing = section(
            id: "blessing",
            kind: .blessing,
            title: "Lectio brevis",
            latin: "Iube, Dómine, benedícere.",
            chant: score(id: "blessing-score")
        )
        let benediction = section(
            id: "benediction",
            kind: .blessing,
            title: "Lectio brevis",
            latin: "Benedictio:"
        )
        let response = section(
            id: "response",
            kind: .blessing,
            title: "Lectio brevis",
            latin: "Noctem quiétam et finem perféctum.",
            chant: score(id: "response-score")
        )
        let lesson = section(
            id: "lesson",
            kind: .reading,
            title: "Lectio brevis",
            latin: "Fratres: Sóbrii estóte, et vigiláte."
        )

        let result = OfficeReaderSectionBuilder.displaySections(
            from: [blessing, benediction, response, lesson],
            format: .authoritativeOrdered
        )

        XCTAssertEqual(
            result.map(\.id),
            ["blessing", "benediction", "response", "lesson"]
        )
        XCTAssertEqual(
            result.map(\.title),
            ["Lectio brevis", "", "", ""]
        )
    }

    func testAuthoritativeMatinsLessonTranslationUsesLatinOrdinal() {
        let result = OfficeReaderSectionBuilder.displaySections(
            from: [
                section(
                    id: "lesson-1",
                    kind: .rubric,
                    title: "Pater",
                    latin: "Lectio 1",
                    english: "Reading 2"
                )
            ],
            format: .authoritativeOrdered
        )

        XCTAssertEqual(result.first?.english, "Reading 1")
    }

    func testAuthoritativeMatchingTextIsFoldedIntoChantWithoutRepeatingLatin() {
        let chant = section(
            id: "chant",
            kind: .responsory,
            title: "Capitulum Responsorium Versus",
            latin: "Tu autem in nobis es, Dómine",
            chant: score(
                gabc: """
                name: Capitulum; %% (c3) Tu(h) au(h)tem(h) in(h) no(h)bis(h) \
                es,(h) Dó(h)mi(f)ne,(f.) et(h) no(h)men(h) sanc(h)tum(h) \
                tu(h)um(h) in(h)vo(h)cá(h)tum(h) est(h) su(g)per(f) nos:(h.) \
                * ne(h) de(h)re(h)lín(h)quas(h) nos,(h) Dó(h)mi(h)ne,(h) \
                De(h)us(h) nos(f)ter.(ef..) (::)
                """
            )
        )
        let duplicateText = section(
            id: "text",
            kind: .responsory,
            title: "Capitulum Responsorium Versus",
            latin: """
            Tu autem in nobis es, Dómine, † et nomen sanctum tuum invocátum \
            est super nos: * ne derelínquas nos, Dómine, Deus noster.
            """,
            english: """
            But thou, O Lord, art among us, and thy name is called upon by us: \
            forsake us not, O Lord our God.
            """
        )

        let result = OfficeReaderSectionBuilder.displaySections(
            from: [chant, duplicateText],
            format: .authoritativeOrdered
        )

        XCTAssertEqual(result.map(\.id), ["chant"])
        XCTAssertEqual(result[0].latin, chant.latin)
        XCTAssertEqual(result[0].english, duplicateText.english)
    }

    func testAuthoritativeChapterTranslationIsNotCopiedToNestedVersicleChants() {
        let chapterEnglish = "She conducted the just through the right ways."
        let chapterScore = section(
            id: "chapter-score",
            kind: .responsory,
            title: "Capitulum Responsorium Versus",
            latin: "Iustum dedúxit Dóminus per vias rectas, et osténdit illi regnum Dei",
            english: "Compiler fallback that presentation should replace.",
            chant: score(
                id: "chapter-score",
                gabc: "name: Capitulum; %% Ius(h)tum(h) de(h)dú(h)xit(h) Dó(h)mi(h)nus(h) per(h) vi(h)as(h) rec(h)tas,(h) et(h) os(h)tén(h)dit(h) il(h)li(h) re(h)gnum(h) De(h)i.(h.) (::)"
            )
        )
        let chapterText = section(
            id: "chapter-text",
            kind: .responsory,
            title: "Capitulum Responsorium Versus",
            latin: "Iustum dedúxit Dóminus per vias rectas, et osténdit illi regnum Dei.",
            english: chapterEnglish
        )
        let versicle = section(
            id: "versicle",
            kind: .responsory,
            title: "Capitulum Responsorium Versus",
            latin: "V/",
            english: "℣. The Lord guided the just in right paths.",
            chant: score(
                id: "versicle-score",
                gabc: "name: Capitulum; %% V/.() Ius(h)tum(h) de(h)dú(h)xit(h) Dó(h)mi(h)nus(h) per(h) vi(h)as(h) rec(h)tas.(h.) (::)"
            )
        )

        let result = OfficeReaderSectionBuilder.displaySections(
            from: [chapterScore, chapterText, versicle],
            format: .authoritativeOrdered
        )

        XCTAssertEqual(result.map(\.id), ["chapter-score", "versicle"])
        XCTAssertEqual(result[0].english, chapterEnglish)
        XCTAssertEqual(
            result[1].english,
            "℣. The Lord guided the just in right paths."
        )
    }

    func testMatchingTextSectionIsFoldedIntoChantWithoutRepeatingLatin() {
        let chant = section(
            id: "chant",
            title: "Incipit",
            latin: "Deus in adiutórium",
            chant: score(
                gabc: """
                name: Incipit; %% (c4) Deus(f) in(g) adiutórium(h) meum(g) \
                inténde.(f.) (::)
                """
            )
        )
        let duplicateText = section(
            id: "text",
            title: "INCÍPIT",
            titleEnglish: "Opening",
            rubric: "Signum crucis fit.",
            rubricEnglish: "The sign of the cross is made.",
            latin: "℣. Deus in adiutórium meum inténde.",
            english: "O God, come to my assistance."
        )
        let followingText = section(
            id: "following",
            kind: .hymn,
            title: "Hymnus",
            latin: "Nunc Sancte nobis Spíritus"
        )

        let result = OfficeReaderSectionBuilder.sections(
            from: [chant, duplicateText, followingText]
        )

        XCTAssertEqual(result.map(\.id), ["chant", "following"])
        XCTAssertEqual(result[0].latin, chant.latin)
        XCTAssertEqual(result[0].english, duplicateText.english)
        XCTAssertEqual(result[0].titleEnglish, duplicateText.titleEnglish)
        XCTAssertEqual(result[0].rubric, duplicateText.rubric)
        XCTAssertEqual(result[0].rubricEnglish, duplicateText.rubricEnglish)
    }

    func testUnmatchedTextSectionRemainsVisibleAfterChant() {
        let chant = section(
            id: "chant",
            title: "Incipit",
            latin: "Deus in adiutórium",
            chant: score()
        )
        let text = section(
            id: "text",
            kind: .hymn,
            title: "Hymnus",
            latin: "Nunc Sancte nobis Spíritus"
        )

        let result = OfficeReaderSectionBuilder.sections(from: [chant, text])

        XCTAssertEqual(result.map(\.id), ["chant", "text"])
    }

    func testCompactPsalmTextDoesNotRepeatItsScoredIncipit() {
        let chant = section(
            id: "chant",
            kind: .psalm,
            title: "Psalmus 72 (0,9)",
            latin: "Quam bonus Israël Deus",
            chant: score(
                gabc: "name: Psalmus 72; %% Quam(h) bo(h)nus(h) Is(h)ra(h)ël.(g.) (::)"
            )
        )
        let duplicateText = section(
            id: "text",
            kind: .psalm,
            title: "Psalmi",
            latin: "Psalmus 72\n\nQuam bonus Israël Deus",
            english: "Psalm 72\n\nHow good is God"
        )

        let result = OfficeReaderSectionBuilder.sections(from: [chant, duplicateText])

        XCTAssertEqual(result.map(\.id), ["chant"])
        XCTAssertEqual(result[0].english, "How good is God")
    }

    func testAuthoritativeScoredPsalmRestoresVerseMislabeledAsAntiphon() {
        let antiphonEnglish = "Ant. The angel of the Lord * shall encamp round about them."
        let antiphon = section(
            id: "antiphon",
            kind: .psalm,
            title: "Psalmus 33 (2,11)",
            latin: "Immíttet Ángelus Dómini in circúitu timéntium eum",
            english: antiphonEnglish,
            chant: score(id: "antiphon-score")
        )
        let psalm = section(
            id: "psalm",
            kind: .psalm,
            title: "Psalmus 33 (2,11)",
            latin: "Benedícam Dóminum in omni témpore",
            english: """
            33:7 This poor man cried, and the Lord heard him.

            \(antiphonEnglish)

            33:9 O taste, and see that the Lord is sweet.
            """,
            chant: score(id: "psalm-score")
        )
        let repeatedAntiphon = section(
            id: "antiphon-repeat",
            kind: .psalm,
            title: "Psalmus 60",
            latin: "Immíttet Ángelus Dómini in circúitu timéntium eum",
            english: antiphonEnglish,
            chant: score(id: "antiphon-repeat-score")
        )

        let result = OfficeReaderSectionBuilder.displaySections(
            from: [antiphon, psalm, repeatedAntiphon],
            format: .authoritativeOrdered
        )

        XCTAssertEqual(result[0].english, antiphonEnglish)
        XCTAssertEqual(
            result[1].english,
            """
            33:7 This poor man cried, and the Lord heard him.

            33:8 The angel of the Lord * shall encamp round about them.

            33:9 O taste, and see that the Lord is sweet.
            """
        )
        XCTAssertEqual(result[2].english, antiphonEnglish)
    }

    func testBundledSeptember2ComplineRestoresPsalm33Verse8() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 9, day: 2),
            hour: .compline
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let psalm = try XCTUnwrap(
            displayed.first(where: {
                $0.english?.contains("33:7 This poor man cried") == true
            })
        )

        XCTAssertTrue(
            psalm.english?.localizedCaseInsensitiveContains(
                "33:8 The angel of the Lord"
            ) == true
        )
        XCTAssertFalse(
            psalm.english?.contains("\n\nAnt. The angel of the Lord") == true
        )
    }

    func testBundledSeptember18ComplinePreservesChantAlignmentAndCompleteScriptureReferences() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 9, day: 18),
            hour: .compline
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let firstHalf = try XCTUnwrap(
            displayed.first(where: {
                $0.english?.contains("76:7 And I meditated in the night") == true
            })
        )
        let secondHalf = try XCTUnwrap(
            displayed.first(where: {
                $0.english?.contains("76:14 Thy way, O God, is in the holy place") == true
            })
        )

        XCTAssertTrue(
            firstHalf.english?.contains(
                "76:8 Will God then cast off for ever"
            ) == true
        )
        XCTAssertFalse(
            firstHalf.english?.contains("\n\nAnt. I have cried") == true
        )
        XCTAssertTrue(
            secondHalf.english?.contains(
                "76:15 Thou hast made thy power known among the nations"
            ) == true
        )
        XCTAssertTrue(
            secondHalf.english?.contains(
                "* 76:16 with thy arm thou hast redeemed thy people"
            ) == true
        )
        let psalm85 = try XCTUnwrap(
            displayed.first(where: {
                $0.english?.contains("85:3 Have mercy on me, O Lord") == true
            })
        )
        XCTAssertTrue(
            psalm85.english?.contains(
                "* 85:4 Give joy to the soul of thy servant"
            ) == true
        )
        let full = PsalmTextFormatter.scriptureParagraphs(from: try XCTUnwrap(secondHalf.english))
        let references = full.components(separatedBy: "\n\n").compactMap {
            PsalmTextFormatter.scriptureVerseNumber(from: $0)
        }
        XCTAssertEqual(references, Array(14...21))
        let compact = OfficeReaderSectionBuilder.displaySections(
            from: office.sections, format: office.format, usesCompactPsalmody: true
        )
        let continuation = try XCTUnwrap(compact.first {
            $0.id == secondHalf.id + "-compact-continuation"
        })
        let lines = PsalmTextFormatter.lines(latin: continuation.latin, english: continuation.english, startsAfterScoredVerse: true)
        XCTAssertTrue(lines.allSatisfy { $0.english != nil })
        XCTAssertTrue(lines.contains { $0.english?.contains("with thy arm thou hast redeemed thy people") == true })
        XCTAssertFalse(lines.contains { $0.english?.contains("76:") == true })
    }

    func testBundledPsalmTranslationsKeepHolyWeekAndDeadOfficeEndingsSeparate() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "base-office", withExtension: "sqlite", subdirectory: "Resources") ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite"))
        let repository = try SQLiteContentRepository(databaseURL: url)
        for day in [3, 4] {
            let office = try await repository.office(on: LocalDay(year: 2026, month: 4, day: day), hour: .matins)
            let psalms = office.sections.filter { $0.kind == .psalm && ["Psalmus 26", "Psalmus 39"].contains($0.title) }
            XCTAssertFalse(psalms.isEmpty)
            for psalm in psalms {
                XCTAssertNotNil(psalm.english)
                XCTAssertFalse(psalm.english?.contains("Eternal rest") == true, "Holy Week must not inherit the Dead Office's ending")
                XCTAssertFalse(psalm.english?.contains("Glory be to the Father") == true)
            }
        }
        let dead = try await repository.office(on: LocalDay(year: 2026, month: 11, day: 2), hour: .matins)
        let psalm24 = try XCTUnwrap(dead.sections.first { $0.title == "Psalmus 24" && $0.english?.contains("24:1 ") == true })
        XCTAssertTrue(psalm24.english?.contains("24:7 The sins of my youth") == true)
        XCTAssertTrue(psalm24.english?.contains("24:7 According to thy mercy") == true)
        XCTAssertTrue(psalm24.english?.contains("Eternal rest") == true)
        XCTAssertFalse(psalm24.english?.contains("Ant.") == true)
        var validatedScores = Set<String>()
        for hour in OfficeHour.allCases {
            let office = try await repository.office(on: LocalDay(year: 2026, month: 11, day: 2), hour: hour)
            for section in office.sections {
                guard let chant = section.chant, chant.id.hasPrefix("reference-requiem-") else { continue }
                let parsed = try GregorianScoreParser.parse(gabc: chant.gabc, timeline: chant.timeline)
                XCTAssertEqual(parsed.eventIDs, chant.timeline.events.map(\.id))
                validatedScores.insert(chant.id)
            }
        }
        XCTAssertFalse(validatedScores.isEmpty)
        let fullPsalm24 = try XCTUnwrap(psalm24.chant)
        XCTAssertFalse(fullPsalm24.timeline.events.map(\.syllable).joined().contains("Glória"))
        let compact = OfficeReaderSectionBuilder.displaySections(from: [psalm24], format: .authoritativeOrdered, usesCompactPsalmody: true)
        XCTAssertEqual(compact.count, 2, "The corrected score and English must align in compact mode")
    }

    func testFullEnglishUsesScriptureBoundariesAndCompactEnglishKeepsChantDivisions() {
        let english = """
        76:14 Thy way, O God, is in the holy place: who is the great God like our God? * 76:15 Thou art the God that dost wonders.

        76:15 Thou hast made thy power known among the nations: * 76:16 with thy arm thou hast redeemed thy people, the children of Jacob and of Joseph.

        76:17 The waters saw thee, O God, the waters saw thee: * and they were afraid, and the depths were troubled.

        76:18 Great was the noise of the waters: * the clouds sent out a sound.

        76:18 For thy arrows pass: * 76:19 the voice of thy thunder in a wheel.

        76:19 Thy lightnings enlightened the world: * the earth shook and trembled.

        Glory be to the Father, and to the Son, * and to the Holy Ghost.
        """
        let full = PsalmTextFormatter.scriptureParagraphs(from: english)
        let paragraphs = full.components(separatedBy: "\n\n")
        XCTAssertEqual(paragraphs.count, 7)
        XCTAssertTrue(paragraphs[1].hasPrefix("76:15 Thou art the God that dost wonders. Thou hast made"))
        XCTAssertTrue(paragraphs[2].hasPrefix("76:16 With thy arm"))
        XCTAssertTrue(paragraphs[4].hasSuffix("For thy arrows pass:"))
        XCTAssertTrue(paragraphs[5].hasPrefix("76:19 The voice of thy thunder in a wheel. Thy lightnings"))
        XCTAssertTrue(paragraphs[6].hasPrefix("Glory be"))
        XCTAssertEqual(PsalmTextFormatter.scriptureParagraphs(from: full), full)
        let chantEnglish = PsalmTextFormatter.strippingVersePrefix(
            from: english.components(separatedBy: "\n\n")[1]
        )
        XCTAssertEqual(chantEnglish, "Thou hast made thy power known among the nations: * with thy arm thou hast redeemed thy people, the children of Jacob and of Joseph.")
    }

    func testFullEnglishDoesNotInventBoundariesFromAnAsteriskOrGap() {
        let text = "76:15 Unverified first half: * unverified second half.\n\n76:17 The waters saw thee."
        XCTAssertFalse(PsalmTextFormatter.scriptureParagraphs(from: text).contains("76:16"))
    }

    func testBundledSeptember19ComplinePsalm87VerseFiveAndSix() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "base-office", withExtension: "sqlite", subdirectory: "Resources") ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite"))
        let repository = try SQLiteContentRepository(databaseURL: url)
        let office = try await repository.office(on: LocalDay(year: 2026, month: 9, day: 19), hour: .compline)
        let psalm = try XCTUnwrap(office.sections.first {
            $0.kind == .psalm && $0.english?.contains("87:5 I am counted") == true
        })
        let english = try XCTUnwrap(psalm.english)
        let full = PsalmTextFormatter.scriptureParagraphs(from: english)
        let paragraphs = full.components(separatedBy: "\n\n")
        XCTAssertEqual(paragraphs.filter { $0.hasPrefix("87:5 ") }, [
            "87:5 I am counted among them that go down to the pit: I am become as a man without help,"
        ])
        XCTAssertEqual(paragraphs.filter { $0.hasPrefix("87:6 ") }, [
            "87:6 Free among the dead. Like the slain sleeping in the sepulchres, whom thou rememberest no more: and they are cast off from thy hand."
        ])
        XCTAssertEqual(PsalmTextFormatter.scriptureParagraphs(from: full), full)

        let compact = OfficeReaderSectionBuilder.displaySections(
            from: [psalm], format: office.format, usesCompactPsalmody: true
        )
        let continuation = try XCTUnwrap(compact.first { $0.id == psalm.id + "-compact-continuation" })
        let lines = PsalmTextFormatter.lines(latin: continuation.latin, english: continuation.english, startsAfterScoredVerse: true)
        XCTAssertTrue(lines.allSatisfy { $0.english != nil })
        XCTAssertTrue(lines.contains {
            $0.english == "I am counted among them that go down to the pit: * I am become as a man without help, free among the dead."
        })
        XCTAssertFalse(lines.contains { $0.english?.contains("87:") == true })
    }

    func testDisplaySectionsPreservesSourceBoundariesWhenThePrintedNumberSkips() {
        let psalm = section(
            id: "psalm-76",
            kind: .psalm,
            title: "Psalmus 76 (14,21)",
            latin: "Notam fecísti in pópulis virtútem tuam.",
            english: [
                "76:15 Thou hast made thy power known among the nations: * with thy arm thou hast redeemed thy people, the children of Jacob and of Joseph.",
                "76:17 The waters saw thee, O God."
            ].joined(separator: "\n\n")
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: [psalm],
            format: .authoritativeOrdered
        )

        XCTAssertEqual(displayed[0].english, psalm.english)
        XCTAssertFalse(displayed[0].english?.contains("76:16") == true)
        XCTAssertTrue(
            displayed[0].english?.contains("76:17 The waters saw thee") == true
        )
    }

    func testDisplaySectionsRemovesAntiphonInsertedBetweenConsecutivePsalmVerses() {
        let psalm = section(
            id: "psalm-76",
            kind: .psalm,
            title: "Psalmus 76 (2,13)",
            latin: "Voce mea ad Dóminum clamávi.",
            english: [
                "76:2 I cried to the Lord with my voice; * to God with my voice, and he gave ear to me.",
                "Ant. I have cried to the Lord with my voice, do not forget to show mercy, O God.",
                "76:3 In the day of my trouble I sought God."
            ].joined(separator: "\n\n")
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: [psalm],
            format: .authoritativeOrdered
        )

        XCTAssertTrue(
            displayed[0].english?.contains("76:2 I cried to the Lord") == true
        )
        XCTAssertTrue(
            displayed[0].english?.contains("76:3 In the day of my trouble") == true
        )
        XCTAssertFalse(
            displayed[0].english?.contains("\n\nAnt. I have cried") == true
        )
    }

    func testCompactPsalmScoresAreInterleavedWithTheirPsalmText() {
        let antiphon = section(
            id: "antiphon",
            kind: .psalm,
            title: "Psalmus 79 (2,8)",
            latin: "Éxcita, Dómine, poténtiam tuam",
            chant: score(
                id: "antiphon-score",
                gabc: "name: Antiphona; %% Éx(f)ci(h)ta(h) Dó(h)mi(h)ne(h) po(h)tén(h)ti(h)am(h) tu(h)am.(g.) (::)"
            )
        )
        let firstPsalm = section(
            id: "psalm-79-2",
            kind: .psalm,
            title: "Psalmus 79 (2,8)",
            latin: "Qui regis Israël, inténde",
            chant: score(
                id: "psalm-79-2-score",
                gabc: "name: Psalmus 79; %% Qui(f) re(h)gis(h) Is(h)ra(h)ël(h) in(h)tén(g)de.(h.) (::)"
            )
        )
        let secondPsalm = section(
            id: "psalm-79-9",
            kind: .psalm,
            title: "Psalmus 79 (9,20)",
            latin: "Víneam de Ægýpto transtulísti",
            chant: score(
                id: "psalm-79-9-score",
                gabc: "name: Psalmus 79; %% Ví(f)ne(h)am(h) de(h) Æ(h)gýp(h)to(h) trans(h)tu(h)lís(g)ti.(h.) (::)"
            )
        )
        let thirdPsalm = section(
            id: "psalm-81",
            kind: .psalm,
            title: "Psalmus 81",
            latin: "Deus stetit in synagóga deórum",
            chant: score(
                id: "psalm-81-score",
                gabc: "name: Psalmus 81; %% De(f)us(h) ste(h)tit(h) in(h) sy(h)na(h)gó(h)ga(h) de(g)ó(h)rum.(h.) (::)"
            )
        )
        let firstText = section(
            id: "psalm-text-79-2",
            kind: .psalm,
            title: "Psalmi",
            latin: "Ant. Éxcita, Dómine, poténtiam tuam.\n\nPsalmus 79\n\n79:2 Qui regis Israël, inténde et dedúcis Ioseph.\n\n79:2 Qui sedes super Chérubim, manifestáre coram Éphraim."
        )
        let secondText = section(
            id: "psalm-text-79-9",
            kind: .psalm,
            title: "Section 4",
            latin: "Psalmus 79\n\n79:9 Víneam de Ægýpto transtulísti et eiecísti gentes.\n\n79:10 Dux itíneris fuísti in conspéctu eius."
        )
        let thirdText = section(
            id: "psalm-text-81",
            kind: .psalm,
            title: "Section 5",
            latin: "Psalmus 81\n\n81:1 Deus stetit in synagóga deórum et diiúdicat.\n\n81:2 Úsquequo iudicátis iniquitátem."
        )

        let result = OfficeReaderSectionBuilder.sections(
            from: [
                antiphon,
                firstPsalm,
                secondPsalm,
                thirdPsalm,
                firstText,
                secondText,
                thirdText
            ]
        )

        XCTAssertEqual(
            result.map(\.id),
            [
                "antiphon",
                "psalm-79-2",
                "psalm-text-79-2",
                "psalm-79-9",
                "psalm-text-79-9",
                "psalm-81",
                "psalm-text-81"
            ]
        )
        XCTAssertFalse(result[2].latin.contains("Ant."))
        XCTAssertFalse(result[2].latin.contains("Qui regis Israël"))
        XCTAssertEqual(result[2].latin, "79:2 Qui sedes super Chérubim, manifestáre coram Éphraim.")
        XCTAssertFalse(result[4].latin.contains("79:9 Víneam"))
        XCTAssertEqual(result[4].latin, "79:10 Dux itíneris fuísti in conspéctu eius.")
    }

    func testDuplicateFollowingSeveralChantsMergesIntoTheLastMatchingChant() {
        let firstChant = section(
            id: "chant-1",
            title: "Psalmus 1",
            latin: "Beatus vir",
            chant: score(
                id: "score-1",
                gabc: "name: Psalmus 1; %% Be(f)a(g)tus(h) vir.(g.) (::)"
            )
        )
        let secondChant = section(
            id: "chant-2",
            title: "Psalmus 1",
            latin: "Quare fremuerunt",
            chant: score(id: "score-2")
        )
        let duplicateText = section(
            id: "text",
            title: "Psalmus 1",
            latin: "Beatus vir…",
            english: "Blessed is the man…"
        )

        let result = OfficeReaderSectionBuilder.sections(
            from: [firstChant, secondChant, duplicateText]
        )

        XCTAssertEqual(result.map(\.id), ["chant-1", "chant-2"])
        XCTAssertEqual(result.map(\.title), ["Psalmus 1", ""])
        XCTAssertEqual(result[0].english, duplicateText.english)
    }

    func testMatchingPlainTextBeforeChantsIsRemoved() {
        let blessingText = section(
            id: "blessing-text",
            kind: .blessing,
            title: "Lectio brevis",
            latin: "℣. Iube, Dómine, benedícere.",
            english: "Grant, Lord, a blessing."
        )
        let blessingChant = section(
            id: "blessing-chant",
            kind: .reading,
            title: "Lectio brevis",
            latin: "Iube, Dómine, benedícere.",
            chant: score(
                id: "blessing-score",
                gabc: "name: Lectio; %% Iu(h)be(h) Dó(h)mi(h)ne(h) be(g)ne(f)dí(h)ce(h)re.(g.) (::)"
            )
        )
        let readingChant = section(
            id: "reading-chant",
            kind: .reading,
            title: "Lectio brevis",
            latin: "Fratres: Sóbrii estóte.",
            chant: score(
                id: "reading-score",
                gabc: "name: Lectio; %% Fra(h)tres(h) Só(h)bri(h)i(h) es(h)tó(h)te(h) et(h) vi(g)gi(f)lá(h)te.(g.) (::)"
            )
        )
        let readingText = section(
            id: "reading-text",
            kind: .reading,
            title: "Lectio brevis",
            latin: "Fratres: Sóbrii estóte, et vigiláte.",
            english: "Brothers: Be sober and watch."
        )

        let result = OfficeReaderSectionBuilder.sections(
            from: [blessingText, blessingChant, readingChant, readingText]
        )

        XCTAssertEqual(result.map(\.id), ["blessing-chant", "reading-chant"])
        XCTAssertEqual(result.map(\.title), ["Lectio brevis", ""])
        XCTAssertEqual(result[0].english, blessingText.english)
        XCTAssertEqual(result[1].english, readingText.english)
    }

    func testCanticlePlacesScoredFirstVerseBeforeProseAndRepeatedAntiphonAfter() {
        let antiphon = section(
            id: "salva-nos",
            kind: .canticle,
            title: "Canticum: Nunc dimittis",
            latin: "Salva nos, Dómine, vigilántes",
            chant: score(
                id: "salva-nos-score",
                gabc: """
                name: Canticum: Nunc dimittis; %% (c4) Sal(g)va(hj) nos,(j.) \
                Dó(jk)mi(j)ne,(ji) vi(h)gi(i')lán(h)tes.(g.) (::)
                """
            )
        )
        let firstVerse = section(
            id: "nunc-dimittis",
            kind: .canticle,
            title: "Canticum: Nunc dimittis",
            latin: "1",
            chant: score(
                id: "nunc-dimittis-score",
                gabc: """
                name: Canticum: Nunc dimittis; %% (c4) 1. Nunc(g) di(hj)mít(j)tis(j) \
                ser(j)vum(j) *tu*(k)um,(j) *Dó*(j)*mi*(ih)ne,(j.) *(:) \
                se(j)cún(j)dum(j) ver(j)bum(j) tu(j)um(j) _in_(h) *pa*(j)ce:(ih..) (::)
                """
            )
        )
        let text = section(
            id: "canticle-text",
            kind: .canticle,
            title: "Canticum: Nunc dimittis",
            latin: """
            Canticum: Nunc dimittis

            Ant. Salva nos, * Dómine, vigilántes.

            Canticum Simeonis

            Luc. 2:29-32

            2:29 Nunc dimíttis ✠ servum tuum, Dómine, * secúndum verbum tuum in pace:

            2:30 Quia vidérunt óculi mei * salutáre tuum,

            ℣. Glória Patri, et Fílio, * et Spirítui Sancto.

            Ant. Salva nos, Dómine, vigilántes.
            """
        )

        let result = OfficeReaderSectionBuilder.sections(
            from: [antiphon, firstVerse, text]
        )

        XCTAssertEqual(
            result.map(\.id),
            [
                "canticle-text",
                "nunc-dimittis",
                "canticle-text-continuation-2",
                "salva-nos"
            ]
        )
        guard result.count == 4 else { return }
        XCTAssertEqual(
            result[0].latin,
            "Canticum Simeonis\n\nLuc. 2:29-32"
        )
        XCTAssertEqual(result[1].chant?.id, "nunc-dimittis-score")
        XCTAssertFalse(result[2].latin.contains("2:29 Nunc dimíttis"))
        XCTAssertTrue(result[2].latin.contains("2:30 Quia vidérunt"))
        XCTAssertEqual(result[3].chant?.id, "salva-nos-score")
    }

    func testPsalmTextFormatterRemovesScripturePrefixesAndUsesOrdinals() {
        let lines = PsalmTextFormatter.lines(
            latin: """
            79:10 Dux itíneris fuísti: * plantásti radíces eius.

            79:11 Opéruit montes umbra eius: * et arbústa eius cedros Dei.

            ℣. Glória Patri, et Fílio.
            """,
            english: """
            79:10 Thou wast the guide of its journey: * thou plantedst its roots.

            79:11 The shadow of it covered the hills: * and its branches the cedars of God.

            ℣. Glory be to the Father, and to the Son.
            """,
            startsAfterScoredVerse: true
        )

        XCTAssertEqual(lines.map(\.number), [2, 3, nil])
        XCTAssertEqual(lines[0].latin, "Dux itíneris fuísti: * plantásti radíces eius.")
        XCTAssertEqual(lines[0].english, "Thou wast the guide of its journey: * thou plantedst its roots.")
        XCTAssertFalse(lines[1].latin.contains("79:11"))
    }

    func testPsalmTextFormatterUsesExplicitScoredVerseOrdinals() {
        let lines = PsalmTextFormatter.lines(
            latin: """
            2. Miserére mei, * et exáudi oratiónem meam.

            3. Fílii hóminum, † úsquequo gravi corde? * quǽritis mendácium?
            """,
            english: """
            4:2 Have mercy on me: * and hear my prayer.

            4:3 O ye sons of men, how long will you be dull of heart?
            """,
            startsAfterScoredVerse: true
        )

        XCTAssertEqual(lines.map(\.number), [2, 3])
        XCTAssertEqual(
            lines[0].latin,
            "Miserére mei, * et exáudi oratiónem meam."
        )
        XCTAssertTrue(lines[1].latin.contains("†"))
        XCTAssertEqual(
            lines[0].english,
            "Have mercy on me: * and hear my prayer."
        )
    }

    func testCompactPsalmodyKeepsOnlyFirstScoredVerse() throws {
        let score = scoredPsalmody(
            id: "psalm-score",
            gabc: threeVerseGABC
        )
        let psalm = section(
            id: "psalm",
            kind: .psalm,
            title: "Psalmus 4",
            latin: "Prima pars, áltera pars.",
            english: """
            4:1 First part, * another part.

            4:2 Second part, * another part.

            4:3 Third part, * another part.
            """,
            chant: score
        )

        let full = OfficeReaderSectionBuilder.displaySections(
            from: [psalm],
            format: .authoritativeOrdered
        )
        XCTAssertEqual(full, [psalm])

        let compact = OfficeReaderSectionBuilder.displaySections(
            from: [psalm],
            format: .authoritativeOrdered,
            usesCompactPsalmody: true
        )

        XCTAssertEqual(compact.count, 2)
        XCTAssertEqual(compact[0].id, "psalm")
        XCTAssertEqual(compact[0].latin, "Prima pars * áltera pars.")
        XCTAssertEqual(compact[0].english, "First part, * another part.")
        XCTAssertEqual(compact[0].chant?.timeline.events.count, 4)
        XCTAssertTrue(compact[0].chant?.gabc.contains("1. Prima") == true)
        XCTAssertFalse(compact[0].chant?.gabc.contains("2. Secúnda") == true)
        XCTAssertEqual(compact[1].id, "psalm-compact-continuation")
        XCTAssertNil(compact[1].chant)

        let lines = PsalmTextFormatter.lines(
            latin: compact[1].latin,
            english: compact[1].english,
            startsAfterScoredVerse: true
        )
        XCTAssertEqual(lines.map(\.number), [2, 3])
        XCTAssertTrue(lines[0].latin.contains("†"))
        XCTAssertTrue(lines.allSatisfy { $0.latin.contains("*") })

        let compactScore = try XCTUnwrap(compact[0].chant)
        let parsed = try GregorianScoreParser.parse(
            gabc: compactScore.gabc,
            timeline: compactScore.timeline
        )
        XCTAssertEqual(parsed.eventIDs, compactScore.timeline.events.map(\.id))
    }

    func testCompactPsalmodyIncludesCanticles() {
        let canticle = section(
            id: "canticle",
            kind: .canticle,
            title: "Canticum Simeonis",
            latin: "Prima pars, áltera pars.",
            english: """
            2:29 First part, * another part.

            2:30 Second part, * another part.

            2:31 Third part, * another part.
            """,
            chant: scoredPsalmody(
                id: "canticle-score",
                gabc: threeVerseGABC
            )
        )

        let compact = OfficeReaderSectionBuilder.displaySections(
            from: [canticle],
            format: .authoritativeOrdered,
            usesCompactPsalmody: true
        )

        XCTAssertEqual(compact.map(\.id), [
            "canticle",
            "canticle-compact-continuation",
        ])
        XCTAssertEqual(compact[1].kind, .canticle)
        XCTAssertNil(compact[1].chant)
    }

    func testCompactPsalmodyLeavesSingleVerseAndMismatchedTranslationsIntact() {
        let singleVerseScore = scoredPsalmody(
            id: "single",
            gabc: "name: Antiphona; %% (c4) Mi(f)se(g)ré(h)re.(g.) (::)",
            noteCount: 4
        )
        let antiphon = section(
            id: "antiphon",
            kind: .psalm,
            title: "Psalmus 4",
            latin: "Miserére",
            english: "Have mercy",
            chant: singleVerseScore
        )
        let mismatched = section(
            id: "mismatched",
            kind: .psalm,
            title: "Psalmus 4",
            latin: "Prima pars",
            english: "Only one paragraph",
            chant: scoredPsalmody(id: "mismatched-score", gabc: threeVerseGABC)
        )

        let compact = OfficeReaderSectionBuilder.displaySections(
            from: [antiphon, mismatched],
            format: .authoritativeOrdered,
            usesCompactPsalmody: true
        )

        XCTAssertEqual(compact.map(\.id), ["antiphon", "mismatched"])
        XCTAssertEqual(compact.map { $0.chant?.id }, ["single", "mismatched-score"])
        XCTAssertEqual(compact[0].latin, antiphon.latin)
        XCTAssertEqual(compact[1].latin, mismatched.latin)
        XCTAssertEqual(compact[1].english, mismatched.english)
    }

    func testPsalmTextFormatterEmphasizesCadenceSyllablesAroundMediant() {
        let verses = [
            (
                "Miserére mei, * et exáudi oratiónem meam.",
                ["me", "me"]
            ),
            (
                "Fílii hóminum, úsquequo gravi corde? * "
                    + "ut quid dilígitis vanitátem, et quǽritis mendácium?",
                ["cor", "dá"]
            ),
            (
                "Et scitóte quóniam mirificávit Dóminus sanctum suum: * "
                    + "Dóminus exáudiet me cum clamávero ad eum.",
                ["su", "e"]
            ),
            (
                "Opéruit montes umbra eius: * et arbústa eius cedros Dei.",
                ["e", "De"]
            )
        ]

        for (verse, expected) in verses {
            let emphasized = PsalmTextFormatter
                .emphasizedSyllableRanges(in: verse)
                .map { String(verse[$0]) }
            XCTAssertEqual(emphasized, expected)
        }
    }

    func testPsalmTextFormatterDoesNotEmphasizeNonPsalmProse() {
        XCTAssertTrue(
            PsalmTextFormatter
                .emphasizedSyllableRanges(in: "Miserére mei.")
                .isEmpty
        )
    }

    func testBundledAugust29ComplineCompactsEveryScoredPsalmodySection()
        async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 8, day: 29),
            hour: .compline
        )
        let compact = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format,
            usesCompactPsalmody: true
        )
        let originals = Dictionary(
            uniqueKeysWithValues: office.sections.map { ($0.id, $0) }
        )

        let compactedIDs = [
            "2026-08-29-compline-section-20",
            "2026-08-29-compline-section-21",
            "2026-08-29-compline-section-22",
            "2026-08-29-compline-section-33",
        ]
        for id in compactedIDs {
            let scoreSection = try XCTUnwrap(
                compact.first(where: { $0.id == id })
            )
            let continuation = try XCTUnwrap(
                compact.first(where: {
                    $0.id == "\(id)-compact-continuation"
                })
            )
            XCTAssertNotNil(scoreSection.chant, id)
            XCTAssertNil(continuation.chant, id)
            XCTAssertFalse(continuation.latin.isEmpty, id)
            XCTAssertLessThan(
                try XCTUnwrap(scoreSection.chant).timeline.events.count,
                try XCTUnwrap(originals[id]?.chant).timeline.events.count,
                id
            )
        }

        let psalm87 = try XCTUnwrap(
            compact.first(where: {
                $0.id == "2026-08-29-compline-section-20-compact-continuation"
            })
        )
        XCTAssertTrue(psalm87.english?.contains("Amen.") == true)

        let psalm102FirstHalf = try XCTUnwrap(
            compact.first(where: {
                $0.id == "2026-08-29-compline-section-21-compact-continuation"
            })
        )
        let psalm102FirstHalfLines = PsalmTextFormatter.lines(
            latin: psalm102FirstHalf.latin,
            english: psalm102FirstHalf.english,
            startsAfterScoredVerse: true
        )
        let secondVerse = try XCTUnwrap(psalm102FirstHalfLines.first)
        XCTAssertEqual(
            secondVerse.emphasizedRanges.map {
                String(secondVerse.latin[$0])
            },
            ["Dó", "ó", "e"]
        )
        XCTAssertFalse(
            secondVerse.latin.contains(PsalmTextFormatter.emphasisStartMarker)
        )

        let psalm102 = try XCTUnwrap(
            compact.first(where: {
                $0.id == "2026-08-29-compline-section-22-compact-continuation"
            })
        )
        let lines = PsalmTextFormatter.lines(
            latin: psalm102.latin,
            english: psalm102.english,
            startsAfterScoredVerse: true
        )
        XCTAssertEqual(lines.first?.number, 2)
        XCTAssertTrue(
            lines.first?.english?.hasPrefix("He remembereth that we are dust")
                == true
        )
        XCTAssertEqual(lines.dropFirst().first?.number, 3)
        XCTAssertTrue(
            lines.dropFirst().first?.english?.hasPrefix("For the spirit")
                == true
        )
    }

    func testBundledAugustComplineCompactsPsalmsAndNuncDimittis() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 8, day: 30),
            hour: .compline
        )
        let compact = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format,
            usesCompactPsalmody: true
        )
        let originalByID = Dictionary(
            uniqueKeysWithValues: office.sections.map { ($0.id, $0) }
        )
        let compactedIDs = [
            "2026-08-30-compline-section-20",
            "2026-08-30-compline-section-21",
            "2026-08-30-compline-section-22",
            "2026-08-30-compline-section-33",
        ]

        for id in compactedIDs {
            let original = try XCTUnwrap(originalByID[id])
            let scoreSection = try XCTUnwrap(
                compact.first(where: { $0.id == id })
            )
            let continuation = try XCTUnwrap(
                compact.first(where: {
                    $0.id == "\(id)-compact-continuation"
                })
            )
            let originalScore = try XCTUnwrap(original.chant)
            let compactScore = try XCTUnwrap(scoreSection.chant)

            XCTAssertLessThan(
                compactScore.timeline.events.count,
                originalScore.timeline.events.count,
                id
            )
            XCTAssertFalse(scoreSection.latin.hasSuffix("2."), id)
            XCTAssertFalse(continuation.latin.isEmpty, id)
            XCTAssertNil(continuation.chant, id)
            XCTAssertNotNil(continuation.english, id)
            let continuationLines = PsalmTextFormatter.lines(
                latin: continuation.latin,
                english: continuation.english,
                startsAfterScoredVerse: true
            )
            XCTAssertEqual(continuationLines.first?.number, 2, id)
            XCTAssertFalse(
                continuationLines.first?.latin.hasSuffix("3.") == true,
                id
            )
            XCTAssertNoThrow(
                try GregorianScoreParser.parse(
                    gabc: compactScore.gabc,
                    timeline: compactScore.timeline
                ),
                id
            )
        }

        let antiphonID = "2026-08-30-compline-section-19"
        let originalAntiphon = try XCTUnwrap(originalByID[antiphonID])
        let displayedAntiphon = try XCTUnwrap(
            compact.first(where: { $0.id == antiphonID })
        )
        XCTAssertEqual(displayedAntiphon.chant, originalAntiphon.chant)
        XCTAssertFalse(
            compact.contains(where: {
                $0.id == "\(antiphonID)-compact-continuation"
            })
        )
    }

    func testBundledAugust30VespersCompactsPsalmWithAntiphonTranslation()
        async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 8, day: 30),
            hour: .vespers
        )
        let compact = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format,
            usesCompactPsalmody: true
        )
        let psalm113ID = "2026-08-30-vespers-section-15"
        let originalScore = try XCTUnwrap(
            office.sections.first(where: { $0.id == psalm113ID })?.chant
        )
        let compactScore = try XCTUnwrap(
            compact.first(where: { $0.id == psalm113ID })?.chant
        )
        let psalm113 = try XCTUnwrap(
            compact.first(where: {
                $0.id == "\(psalm113ID)-compact-continuation"
            })
        )
        XCTAssertLessThan(
            compactScore.timeline.events.count,
            originalScore.timeline.events.count
        )
        XCTAssertNil(psalm113.chant)
        XCTAssertFalse(psalm113.latin.isEmpty)
        let psalm113Lines = PsalmTextFormatter.lines(
            latin: psalm113.latin,
            english: psalm113.english,
            startsAfterScoredVerse: true
        )
        let verse11 = try XCTUnwrap(
            psalm113Lines.first(where: { $0.number == 11 })
        )
        XCTAssertEqual(
            verse11.english,
            "But our God is in heaven: * he hath done all things whatsoever he would."
        )
    }

    func testBundledAugust30CompactsEveryMultiVersePsalmodyAcrossAllHours()
        async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let date = LocalDay(year: 2026, month: 8, day: 30)
        var failures: [String] = []

        for hour in OfficeHour.allCases {
            let office = try await repository.office(on: date, hour: hour)
            let displayed = OfficeReaderSectionBuilder.displaySections(
                from: office.sections,
                format: office.format
            )
            let compact = OfficeReaderSectionBuilder.displaySections(
                from: office.sections,
                format: office.format,
                usesCompactPsalmody: true
            )

            for section in displayed
            where section.kind == .psalm || section.kind == .canticle {
                guard let score = section.chant,
                      try scoredVerseCount(in: score) > 1 else {
                    continue
                }
                let continuationID = "\(section.id)-compact-continuation"
                if !compact.contains(where: { $0.id == continuationID }) {
                    failures.append(
                        "\(hour.rawValue): \(section.id) \(section.title)"
                    )
                }
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Multi-verse psalmody did not compact:\n\(failures.joined(separator: "\n"))"
        )
    }

    func testReprintedHeadingsAndSourceNotesAppearOnce() {
        let collect = OfficeSection(
            id: "collect",
            kind: .collect,
            title: "Oratio",
            titleEnglish: "Prayer",
            rubric: "ex Proprio Sanctorum",
            rubricEnglish: "from the Proper of Saints",
            latin: "Oratio {ex Proprio Sanctorum}\n\nOrémus.",
            english: "Prayer {from the Proper of Saints}\n\nLet us pray."
        )
        let conclusion = OfficeSection(
            id: "conclusion",
            kind: .conclusion,
            title: "Oratio",
            rubric: "ex Proprio de Tempore",
            latin: "Oratio {ex Proprio de Tempore}\n\n℣. Benedicámus Dómino."
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: [collect, conclusion],
            format: .authoritativeOrdered
        )
        XCTAssertEqual(displayed.map(\.latin), ["Orémus.", "℣. Benedicámus Dómino."])
        XCTAssertEqual(displayed.first?.english, "Let us pray.")
        XCTAssertEqual(displayed.first?.rubric, "ex Proprio Sanctorum")
        // A repeated heading is shown once, but its section keeps its own note.
        XCTAssertEqual(displayed.last?.title, "")
        XCTAssertEqual(displayed.last?.rubric, "ex Proprio de Tempore")
    }

    func testMechanicalSourceHeadingsAreCorrected() {
        func section(_ id: String, _ kind: OfficeSectionKind, _ title: String, _ latin: String, english: String? = nil) -> OfficeSection {
            OfficeSection(id: id, kind: kind, title: title, titleEnglish: english, latin: latin)
        }
        let combined = "Capitulum Responsorium Versus"
        // At Lauds the chapter is followed by the hymn, not a short responsory.
        let lauds = OfficeReaderSectionBuilder.withCorrectedHeadings(in: [
            section("chapter", .reading, combined, "Iac 1:12", english: "Chapter Responsory Verse"),
            section("response", .responsory, combined, "R/"),
            section("hymn", .hymn, "Hymnus", "Iam lucis orto sídere")
        ])
        XCTAssertEqual(lauds.map(\.title), ["Capitulum", "Capitulum", "Hymnus"])
        XCTAssertEqual(lauds.first?.titleEnglish, "Chapter")
        // At Terce the short responsory and its versicle keep the full heading.
        let terce = OfficeReaderSectionBuilder.withCorrectedHeadings(in: [
            section("chapter", .reading, combined, "Iac 1:12"),
            section("versicle", .responsory, combined, "V/")
        ])
        XCTAssertEqual(terce.map(\.title), [combined, combined])
        let others = OfficeReaderSectionBuilder.withCorrectedHeadings(in: [
            section("psalm", .psalm, "Section 5", "Psalmus 27 [3]", english: "Section 5"),
            section("lesson", .reading, "Lectio brevis", "Tu autem", english: "Start")
        ])
        XCTAssertEqual(others.map(\.title), ["", "Lectio brevis"])
        XCTAssertNil(others.first?.titleEnglish)
        XCTAssertEqual(others.last?.titleEnglish, "Short reading")
    }

    func testStandaloneDirectionsBecomeTheRubricOfWhatFollows() {
        let direction = OfficeSection(id: "d", kind: .prayer, title: "Conclusio", latin: "secreto", english: "silently")
        let prayer = OfficeSection(id: "p", kind: .prayer, title: "", latin: "Pater noster, qui es in cælis.")
        let closing = OfficeSection(id: "c", kind: .prayer, title: "", latin: "Reliqua omittuntur, nisi Laudes separandæ sint.")
        let shown = OfficeReaderSectionBuilder.showingDirectionsAsRubrics(in: [direction, prayer, closing])
        XCTAssertEqual(shown.map(\.id), ["p", "c"])
        XCTAssertEqual(shown.first?.rubric, "secreto")
        XCTAssertEqual(shown.first?.rubricEnglish, "silently")
        XCTAssertEqual(shown.first?.title, "Conclusio")
        // A direction with nothing after it to govern is left as it is.
        let trailing = OfficeReaderSectionBuilder.showingDirectionsAsRubrics(in: [prayer, direction])
        XCTAssertEqual(trailing.map(\.id), ["p", "d"])
    }

    func testSignOfTheCrossPrintedAsAPlusSignIsShownAsACross() {
        let opening = OfficeSection(
            id: "opening",
            kind: .opening,
            title: "Incipit",
            latin: "℣. Dómine, lábia \u{FE0E}+\u{FE0E} mea apéries.",
            english: "℣. O Lord, \u{FE0E}+\u{FE0E} open thou my lips."
        )
        for format in [OfficeDocument.Format.sourceOrdered, .authoritativeOrdered] {
            let displayed = OfficeReaderSectionBuilder.displaySections(from: [opening], format: format)
            XCTAssertEqual(displayed.first?.latin, "℣. Dómine, lábia ✠ mea apéries.", "\(format)")
            XCTAssertEqual(displayed.first?.english, "℣. O Lord, ✠ open thou my lips.", "\(format)")
        }
    }

    func testComplineDoesNotMoveDeusInAdiutoriumAheadOfTheShortLesson() {
        let blessing = section(
            id: "blessing",
            kind: .blessing,
            title: "Incipit",
            latin: "Incipit\n\n℣. Iube, Dómine, benedícere.",
            english: "Start\n\n℣. Grant, Lord, a blessing."
        )
        let reading = section(
            id: "reading",
            kind: .reading,
            title: "Lectio brevis",
            latin: "Lectio brevis\n\nFratres: Sóbrii estóte, et vigiláte."
        )
        let misplacedChant = section(
            id: "deus-chant",
            title: "Incipit",
            latin: "Fratres",
            chant: score(
                id: "deus-score",
                gabc: """
                name: Incipit; %% (c3) Deus(h) in(h) adiutórium(i) meum(h) \
                inténde.(g.) (::)
                """
            )
        )
        let penitential = section(
            id: "penitential",
            title: "Section 3",
            latin: "℣. Convérte nos Deus, salutáris noster."
        )
        let deusText = section(
            id: "deus-text",
            title: "Section 4",
            latin: """
            ℣. Deus in adiutórium meum inténde.

            ℟. Dómine, ad adiuvándum me festína.
            """
        )

        let result = OfficeReaderSectionBuilder.sections(
            from: [misplacedChant, blessing, reading, penitential, deusText]
        )

        XCTAssertEqual(
            result.map(\.id),
            ["blessing", "reading", "penitential", "deus-chant", "deus-text-continuation-1"]
        )
        XCTAssertEqual(result.first?.title, "Lectio brevis")
        XCTAssertEqual(result.first?.latin, "℣. Iube, Dómine, benedícere.")
        XCTAssertEqual(result.first?.english, "℣. Grant, Lord, a blessing.")
        XCTAssertEqual(result[result.count - 2].latin, misplacedChant.latin)
        XCTAssertEqual(
            result.last?.latin,
            "℟. Dómine, ad adiuvándum me festína."
        )
    }

    func testBundledJulyComplineBeginsWithLectioBrevis() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 24),
            hour: .compline
        )

        let result = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let shortLessonIndex = try XCTUnwrap(
            result.firstIndex(where: { $0.title == "Lectio brevis" })
        )
        let deusIndex = try XCTUnwrap(
            result.firstIndex(where: {
                $0.title == "Incipit" && $0.chant != nil
            })
        )

        XCTAssertEqual(result.first?.title, "Lectio brevis")
        XCTAssertNotEqual(result.first?.title.lowercased(), "incipit")
        XCTAssertGreaterThan(deusIndex, shortLessonIndex)
        XCTAssertTrue(
            result.contains(where: {
                $0.chant?.provenance.collection == "Chant Tools"
                    && $0.latin.contains("Noctem quiétam")
            }),
            "The pinned ordinary-tone blessing must render as notation."
        )
        XCTAssertTrue(
            result.contains(where: {
                $0.chant?.provenance.collection == "Chant Tools"
                    && $0.latin.contains("Tu autem in nobis es")
            }),
            "The pinned Compline chapter tone must render as notation."
        )
        XCTAssertFalse(
            result.contains(where: {
                $0.chant == nil && $0.latin.contains("Noctem quiétam")
            })
        )
        let visibleLatin = result.map(\.latin).joined(separator: "\n")
        XCTAssertTrue(visibleLatin.contains("Pater noster"))
        XCTAssertTrue(visibleLatin.contains("Confíteor"))
        XCTAssertTrue(visibleLatin.contains("Indulgéntiam"))
        XCTAssertTrue(visibleLatin.contains("Vísita, quǽsumus, Dómine"))
        XCTAssertTrue(visibleLatin.contains("Benedícat et custódiat nos"))
        XCTAssertTrue(visibleLatin.contains("Omnípotens sempitérne Deus"))
        let paterIndex = try XCTUnwrap(
            result.firstIndex(where: { $0.latin.contains("Pater noster") })
        )
        let aidIndex = try XCTUnwrap(
            result.firstIndex(where: {
                $0.chant?.gabc.contains("A(h)dju(h)tó") == true
            })
        )
        let convertIndex = try XCTUnwrap(
            result.firstIndex(where: {
                $0.chant?.gabc.contains("Con(h)vér(h)te") == true
            })
        )
        XCTAssertLessThan(aidIndex, paterIndex)
        XCTAssertLessThan(paterIndex, convertIndex)
        XCTAssertEqual(
            result.filter { $0.title == "Lectio brevis" }.count,
            1,
            "A multi-score short lesson should render one shared heading."
        )
        let nuncDimittisIndex = try XCTUnwrap(
            result.firstIndex(where: {
                $0.chant?.gabc.contains("Nunc(g) di(hj)mít(j)tis") == true
            })
        )
        let salvaNosIndices = result.indices.filter {
            result[$0].chant?.gabc.contains("Sal(g)va(hj) nos") == true
                && result[$0].kind == .canticle
        }
        let firstSalvaNosIndex = try XCTUnwrap(salvaNosIndices.first)
        let repeatedSalvaNosIndex = try XCTUnwrap(salvaNosIndices.last)
        XCTAssertLessThan(firstSalvaNosIndex, nuncDimittisIndex)
        XCTAssertLessThan(nuncDimittisIndex, repeatedSalvaNosIndex)
        XCTAssertEqual(
            salvaNosIndices.count,
            2,
            "The canticle antiphon must frame the scored Nunc dimittis."
        )
        XCTAssertFalse(
            result.contains(where: {
                $0.chant == nil
                    && ($0.latin.contains("2:29 Nunc dimíttis")
                        || $0.latin.contains("2:30 Quia vidérunt"))
            }),
            "The fully scored canticle must not remain as duplicate prose."
        )
    }

    func testBundledAuthoritativeOfficesShareHeadingsAcrossEveryHour() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let date = LocalDay(year: 2026, month: 7, day: 26)
        var hoursWithRawRepeatedHeadings: Set<OfficeHour> = []

        for hour in OfficeHour.allCases {
            let office = try await repository.office(on: date, hour: hour)
            guard office.format == .authoritativeOrdered else {
                XCTFail("\(date) \(hour.rawValue) is not authoritative.")
                continue
            }

            if !repeatedVisibleHeadings(in: office.sections).isEmpty {
                hoursWithRawRepeatedHeadings.insert(hour)
            }

            let displayed = OfficeReaderSectionBuilder.displaySections(
                from: office.sections,
                format: office.format
            )
            XCTAssertTrue(
                repeatedVisibleHeadings(in: displayed).isEmpty,
                "\(date) \(hour.rawValue) still repeats a shared heading."
            )
        }

        XCTAssertEqual(
            hoursWithRawRepeatedHeadings,
            Set(OfficeHour.allCases),
            "The fixture must exercise repeated headings in every canonical hour."
        )
    }

    func testBundledJuly26OutlinesContainMajorSectionsForEveryHour() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let date = LocalDay(year: 2026, month: 7, day: 26)
        let requiredTitles: [OfficeHour: Set<String>] = [
            .matins: [
                "Incipit", "Invitatorium", "Hymnus", "Versus", "Pater",
                "Lectio 1", "Lectio 2", "Lectio 3", "Te Deum", "Oratio",
                "Conclusio"
            ],
            .lauds: [
                "Incipit", "Capitulum", "Hymnus",
                "Versus", "Canticum: Canticum Zachariæ", "Oratio",
                "Conclusio"
            ],
            .prime: [
                "Incipit", "Hymnus", "Capitulum Responsorium Versus",
                "Oratio", "Martyrologium", "Lectio brevis", "Conclusio"
            ],
            .terce: [
                "Incipit", "Hymnus", "Capitulum Responsorium Versus",
                "Oratio", "Conclusio"
            ],
            .sext: [
                "Incipit", "Hymnus", "Capitulum Responsorium Versus",
                "Oratio", "Conclusio"
            ],
            .none: [
                "Incipit", "Hymnus", "Capitulum Responsorium Versus",
                "Oratio", "Conclusio"
            ],
            .vespers: [
                "Incipit", "Capitulum", "Hymnus",
                "Versus", "Canticum: Canticum B. Mariæ Virginis", "Oratio",
                "Conclusio"
            ],
            .compline: [
                "Lectio brevis", "Prex poenitentialis", "Incipit", "Hymnus",
                "Capitulum Responsorium Versus", "Canticum: Nunc dimittis",
                "Oratio", "Conclusio", "Antiphona finalis B.M.V."
            ]
        ]

        for hour in OfficeHour.allCases {
            let office = try await repository.office(on: date, hour: hour)
            let displayed = OfficeReaderSectionBuilder.displaySections(
                from: office.sections,
                format: office.format
            )
            let outlineTitles = Set(
                OfficeReaderOutlineBuilder.entries(from: displayed).map(\.title)
            )
            let expected = try XCTUnwrap(requiredTitles[hour])

            XCTAssertTrue(
                outlineTitles.isSuperset(of: expected),
                "\(hour.rawValue) is missing \(expected.subtracting(outlineTitles))."
            )
            XCTAssertTrue(
                outlineTitles.contains(where: {
                    $0.hasPrefix("Psalmus ") || $0.hasPrefix("Canticum: ")
                }),
                "\(hour.rawValue) has no psalm or canticle jump target."
            )
        }
    }

    func testBundledAugust19SextDisplaysCompleteAvailableEnglish() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 8, day: 19),
            hour: .sext
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let allEnglish = displayed.compactMap(\.english).joined(separator: "\n")

        XCTAssertTrue(allEnglish.localizedCaseInsensitiveContains(
            "come to my assistance"
        ))
        XCTAssertTrue(allEnglish.localizedCaseInsensitiveContains(
            "world without end"
        ))
        XCTAssertTrue(allEnglish.localizedCaseInsensitiveContains(
            "The law of his God is in his heart"
        ))
        XCTAssertTrue(allEnglish.localizedCaseInsensitiveContains(
            "None of his steps shall slide"
        ))
        XCTAssertTrue(allEnglish.localizedCaseInsensitiveContains(
            "O God, who did wondrously inspire blessed John"
        ))

        let completePsalms = displayed.filter {
            $0.kind == .psalm && ($0.chant?.gabc.count ?? 0) > 1_200
        }
        XCTAssertEqual(completePsalms.count, 3)
        for psalm in completePsalms {
            let englishWords = (psalm.english ?? "").split(whereSeparator: \.isWhitespace)
            XCTAssertGreaterThan(
                englishWords.count,
                80,
                "A scored psalm displays only a fragment of its English translation."
            )
        }
    }

    func testBundledAugust19NoneDoesNotRepeatChapterEnglishForVersicleChants() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 8, day: 19),
            hour: .none
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let chapterSections = displayed.filter {
            $0.title == "Capitulum Responsorium Versus" || $0.title.isEmpty
        }
        let fullTranslation = "She conducted the just, when he fled from his brother's wrath"

        XCTAssertEqual(
            chapterSections.filter {
                $0.english?.localizedCaseInsensitiveContains(fullTranslation) == true
            }.count,
            1
        )
        let versicle = try XCTUnwrap(chapterSections.first(where: {
            $0.chant?.gabc.contains("Ju(h)stu(h)m de(h)dú(h)xi(h)t") == true
        }))
        let response = try XCTUnwrap(chapterSections.first(where: {
            $0.chant?.gabc.contains("E(h)t o(h)sté(h)ndi(h)t") == true
        }))
        XCTAssertEqual(
            versicle.english,
            "℣. The Lord guided the just in right paths."
        )
        XCTAssertEqual(
            response.english,
            "℟. And showed him the kingdom of God."
        )
    }

    func testEveryBundledMatinsOutlineContainsEveryNumberedLesson() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)

        for day in try await repository.availableDays() {
            let office = try await repository.office(on: day.date, hour: .matins)
            let lessonTitles = office.sections.compactMap { section -> String? in
                let latin = section.latin.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let parts = latin.split(whereSeparator: \.isWhitespace)
                guard parts.count == 2,
                      parts[0] == "Lectio",
                      Int(parts[1]) != nil
                else {
                    return nil
                }
                return latin
            }
            let displayed = OfficeReaderSectionBuilder.displaySections(
                from: office.sections,
                format: office.format
            )
            let outlineTitles = OfficeReaderOutlineBuilder.entries(
                from: displayed
            ).map(\.title)

            for title in lessonTitles {
                XCTAssertTrue(
                    outlineTitles.contains(title),
                    "\(day.date) Matins is missing \(title)."
                )
            }
        }
    }

    func testBundledJuly26ComplineDoesNotRepeatScoredChapterAsProse() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 26),
            hour: .compline
        )

        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let chapter = try XCTUnwrap(
            displayed.first(where: {
                $0.chant?.gabc.contains("Tu(h) au(h)tem(h) in(h) no(h)bis") == true
            })
        )

        XCTAssertEqual(
            chapter.english,
            """
            But thou, O Lord, art among us, and thy name is called upon by us: \
            forsake us not, O Lord our God.
            """
        )
        XCTAssertFalse(
            displayed.contains(where: {
                $0.chant == nil && $0.latin.contains("Tu autem in nobis es")
            }),
            "The scored Compline chapter must not also render as Latin prose."
        )
    }

    func testBundledJulyTerceInterleavesEachPsalmScoreWithItsText() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 24),
            hour: .terce
        )

        let psalmIDs = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
            .filter { $0.kind == .psalm }
            .map(\.id)

        XCTAssertEqual(
            psalmIDs,
            [
                "2026-07-24-terce-section-2",
                "2026-07-24-terce-section-3",
                "2026-07-24-terce-section-4",
                "2026-07-24-terce-section-5",
                "2026-07-24-terce-section-6"
            ]
        )

        let psalmSections = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
            .filter { $0.kind == .psalm }
        XCTAssertEqual(psalmSections[0].title, "Psalmus 79 (2,8)")
        XCTAssertEqual(psalmSections[1].title, "")
        XCTAssertEqual(psalmSections[2].title, "Psalmus 79 (9,20)")
        XCTAssertTrue(psalmSections[2].latin.contains("Víneam de Ægýpto"))
        XCTAssertEqual(psalmSections[3].title, "Psalmus 81")
        XCTAssertEqual(psalmSections[4].title, "")
        XCTAssertTrue(psalmSections[4].latin.contains("Éxcita, Dómine"))
    }

    func testBundledCorpusPreservesUnscoredPrayersSharingChantedHeadings() async throws {
        let bundledDatabaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: bundledDatabaseURL)
        let dates = try representativeDatesForUniqueRecipes(
            databaseURL: bundledDatabaseURL,
            hour: .compline
        )
        var exercisedPrayerCount = 0

        for date in dates {
            let office = try await repository.office(on: date, hour: .compline)
            let rawLatin = office.sections
                .filter { $0.chant == nil }
                .map(\.latin)
                .joined(separator: "\n")
            let markers = [
                "Pater noster",
                "Confíteor"
            ].filter {
                rawLatin.localizedCaseInsensitiveContains($0)
            }
            guard !markers.isEmpty else { continue }
            exercisedPrayerCount += markers.count
            let displayedLatin = OfficeReaderSectionBuilder.sections(
                from: office.sections
            ).map(\.latin).joined(separator: "\n")
            for marker in markers {
                XCTAssertTrue(
                    displayedLatin.localizedCaseInsensitiveContains(marker),
                    "\(date) compline dropped \(marker)"
                )
            }
        }

        XCTAssertGreaterThan(
            exercisedPrayerCount,
            0,
            "The regression test must exercise prayers in the bundled corpus."
        )
    }

    func testLayGreetingRemainsWhenNoPriestOrDeaconIsPresent() {
        let text = """
        Oratio

        ℣. Dómine, exáudi oratiónem meam.

        ℟. Et clamor meus ad te véniat.

        Orémus.
        """

        XCTAssertEqual(
            OfficePrayerText.adjusted(text, isPriestOrDeaconPresent: false),
            text
        )
    }

    func testClericalGreetingReplacesLayGreetingWhenPriestOrDeaconIsPresent() {
        let latin = """
        Oratio

        ℣. Dómine, exáudi oratiónem meam.

        ℟. Et clamor meus ad te véniat.

        Orémus.
        """
        let english = """
        Prayer

        ℣. O Lord, hear my prayer.

        ℟. And let my cry come unto thee.

        Let us pray.
        """

        XCTAssertEqual(
            OfficePrayerText.adjusted(latin, isPriestOrDeaconPresent: true),
            """
            Oratio

            ℣. Dóminus vobíscum.

            ℟. Et cum spíritu tuo.

            Orémus.
            """
        )
        XCTAssertEqual(
            OfficePrayerText.adjusted(english, isPriestOrDeaconPresent: true),
            """
            Prayer

            ℣. The Lord be with you.

            ℟. And with thy spirit.

            Let us pray.
            """
        )
    }

    func testImportedGreetingUsesClericalTextFallbackWithSingleNewlines() {
        let latin = "℣. Dómine, exáudi oratiónem meam.\n℟. Et clamor meus ad te véniat.\nOrémus."
        let english = "℣. O Lord, hear my prayer.\n℟. And let my cry come unto thee.\nLet us pray."
        XCTAssertEqual(OfficePrayerText.adjusted(latin, isPriestOrDeaconPresent: true),
            "℣. Dóminus vobíscum.\n℟. Et cum spíritu tuo.\nOrémus.")
        XCTAssertEqual(OfficePrayerText.adjusted(english, isPriestOrDeaconPresent: true),
            "℣. The Lord be with you.\n℟. And with thy spirit.\nLet us pray.")
        XCTAssertTrue(OfficePrayerText.requiresTextFallback(latin, isPriestOrDeaconPresent: true))
        XCTAssertFalse(OfficePrayerText.requiresTextFallback(latin, isPriestOrDeaconPresent: false))
        XCTAssertFalse(OfficePrayerText.requiresTextFallback("℣. Dómine, exáudi oratiónem meam.", isPriestOrDeaconPresent: true))
    }

    func testDeadOfficeRetainsRequiredVersicleBeforeClericalGreeting() {
        let latin = "℣. Dómine, exáudi oratiónem meam.\n℟. Et clamor meus ad te véniat.\nsecunda Domine, exaudi omittitur"
        let english = "℣. O Lord, hear my prayer.\n℟. And let my cry come unto thee.\nskip second O Lord, hear my prayer"
        let adjusted = OfficePrayerText.adjusted(latin, isPriestOrDeaconPresent: true)
        XCTAssertTrue(adjusted.hasPrefix("℣. Dómine, exáudi oratiónem meam."))
        XCTAssertTrue(adjusted.hasSuffix("℣. Dóminus vobíscum.\n\n℟. Et cum spíritu tuo."))
        let translated = OfficePrayerText.adjusted(english, isPriestOrDeaconPresent: true)
        XCTAssertTrue(translated.hasPrefix("℣. O Lord, hear my prayer."))
        XCTAssertTrue(translated.hasSuffix("℣. The Lord be with you.\n\n℟. And with thy spirit."))
        XCTAssertEqual(OfficePrayerText.adjusted(latin, isPriestOrDeaconPresent: false), latin)
    }

    func testOlderSourcePackKeepsDeadOfficeVersicleAndGreetingTogether() {
        let source = [
            section(id: "versicle", title: "Oratio", latin: "℣. Dómine, exáudi oratiónem meam.\n℟. Et clamor meus ad te véniat.", english: "℣. O Lord, hear my prayer.\n℟. And let my cry come unto thee."),
            section(id: "direction", title: "", latin: "secunda Domine, exaudi omittitur", english: "skip second O Lord, hear my prayer")
        ]
        let displayed = OfficeReaderSectionBuilder.displaySections(from: source, format: .sourceOrdered)
        XCTAssertEqual(displayed.count, 1)
        let adjusted = OfficePrayerText.adjusted(displayed[0].latin, isPriestOrDeaconPresent: true)
        XCTAssertTrue(adjusted.hasPrefix("℣. Dómine, exáudi oratiónem meam."))
        XCTAssertTrue(adjusted.contains("Dóminus vobíscum."))
    }

    private func section(
        id: String,
        kind: OfficeSectionKind = .opening,
        title: String,
        titleEnglish: String? = nil,
        rubric: String? = nil,
        rubricEnglish: String? = nil,
        latin: String,
        english: String? = nil,
        chant: ChantScore? = nil
    ) -> OfficeSection {
        OfficeSection(
            id: id,
            kind: kind,
            title: title,
            titleEnglish: titleEnglish,
            rubric: rubric,
            rubricEnglish: rubricEnglish,
            latin: latin,
            english: english,
            chant: chant
        )
    }

    private func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func repeatedVisibleHeadings(
        in sections: [OfficeSection]
    ) -> [String] {
        var lastHeading: String?
        var repeated: [String] = []

        for section in sections {
            let heading = normalizedTitle(section.title)
            guard !heading.isEmpty else { continue }
            if heading == lastHeading {
                repeated.append(section.title)
            }
            lastHeading = heading
        }
        return repeated
    }

    private func representativeDatesForUniqueRecipes(
        databaseURL: URL,
        hour: OfficeHour
    ) throws -> [LocalDay] {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard opened == SQLITE_OK, let database else {
            throw ContentRepositoryError.databaseUnavailable(
                "SQLite could not open the bundled corpus for recipe audit."
            )
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT MIN(date)
        FROM office_schedule
        WHERE hour = ?
        GROUP BY recipe_id
        ORDER BY MIN(date)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ContentRepositoryError.databaseUnavailable(
                "SQLite could not prepare the unique-recipe audit."
            )
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, hour.rawValue, -1, transient) == SQLITE_OK else {
            throw ContentRepositoryError.databaseUnavailable(
                "SQLite could not bind the audited office hour."
            )
        }

        var dates: [LocalDay] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return dates }
            guard step == SQLITE_ROW,
                  let value = sqlite3_column_text(statement, 0),
                  let date = LocalDay(iso8601: String(cString: value)) else {
                throw ContentRepositoryError.invalidContent(
                    "The unique-recipe audit returned a malformed date."
                )
            }
            dates.append(date)
        }
    }

    private func score(
        id: String = "score",
        gabc: String = "name: Incipit; %% (c4) De(f)us(g) (::)"
    ) -> ChantScore {
        ChantScore(
            id: id,
            incipit: "Deus in adiutórium",
            gabc: gabc,
            reviewStatus: .humanReviewed,
            provenance: ChantProvenance(
                collection: "Test",
                sourceBook: "Test",
                license: "CC0-1.0",
                snapshot: "test"
            ),
            timeline: ChantTimeline(events: [])
        )
    }

    private var threeVerseGABC: String {
        """
        name: Psalmody; %% (c4) 1. Prima(f) pars(g.) *(:) \
        áltera(h) pars.(g.) (::) 2. Secúnda(f) pars(g.) †(,) *(:) \
        áltera(h) pars.(g.) (::) 3. Tértia(f) pars(g.) *(:) \
        áltera(h) pars.(g.) (::)
        """
    }

    private func scoredPsalmody(
        id: String,
        gabc: String,
        noteCount: Int = 12
    ) -> ChantScore {
        ChantScore(
            id: id,
            incipit: "Prima pars",
            gabc: gabc,
            mode: "8g",
            reviewStatus: .humanReviewed,
            provenance: ChantProvenance(
                collection: "Test",
                sourceBook: "Test",
                license: "CC0-1.0",
                snapshot: "test"
            ),
            timeline: ChantTimeline(
                events: (0..<noteCount).map { index in
                    ChantEvent(
                        id: "\(id)-note-\(index)",
                        phraseID: "\(id)-phrase-\(index / 4)",
                        syllableID: "\(id)-syllable-\(index)",
                        syllable: "syllable",
                        relativePitch: 0
                    )
                }
            )
        )
    }

    private func scoredVerseCount(in score: ChantScore) throws -> Int {
        let parsed = try GregorianScoreParser.parse(
            gabc: score.gabc,
            timeline: score.timeline
        )
        var count = 0
        var current: [GregorianNotationElement] = []

        for element in parsed.elements {
            current.append(element)
            if case .division(.final) = element {
                if !GregorianScore(elements: current).lyricText.isEmpty {
                    count += 1
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if !GregorianScore(elements: current).lyricText.isEmpty {
            count += 1
        }
        return count
    }
}
