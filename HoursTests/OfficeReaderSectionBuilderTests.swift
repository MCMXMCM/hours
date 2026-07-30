import HoursCore
@testable import Hours
import XCTest

@MainActor
final class OfficeReaderSectionBuilderTests: XCTestCase {
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
            rubric: "Signum crucis fit.",
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
        XCTAssertEqual(result[0].rubric, duplicateText.rubric)
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

        let result = OfficeReaderSectionBuilder.sections(from: office.sections)
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
        let remainingCanticleIndex = try XCTUnwrap(
            result.firstIndex(where: {
                $0.chant == nil && $0.latin.contains("2:30 Quia vidérunt")
            })
        )
        let salvaNosIndex = try XCTUnwrap(
            result.firstIndex(where: {
                $0.chant?.gabc.contains("Sal(g)va(hj) nos") == true
                    && $0.kind == .canticle
            })
        )
        XCTAssertLessThan(nuncDimittisIndex, remainingCanticleIndex)
        XCTAssertLessThan(remainingCanticleIndex, salvaNosIndex)
        XCTAssertFalse(
            result.contains(where: {
                $0.chant == nil && $0.latin.contains("2:29 Nunc dimíttis")
            }),
            "The scored first verse must not remain as prose above its notation."
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

        let psalmIDs = OfficeReaderSectionBuilder.sections(from: office.sections)
            .filter { $0.kind == .psalm }
            .map(\.id)

        XCTAssertEqual(
            psalmIDs,
            [
                "terce-source-chant-2",
                "terce-source-chant-3",
                "terce-tertia3",
                "terce-source-chant-4",
                "terce-tertia4",
                "terce-source-chant-5",
                "terce-tertia5",
                "terce-source-chant-2-repeat-terce-tertia5-11"
            ]
        )

        let psalmSections = OfficeReaderSectionBuilder.sections(from: office.sections)
            .filter { $0.kind == .psalm }
        XCTAssertEqual(psalmSections[0].title, "Psalmus 79 (2,8)")
        XCTAssertEqual(psalmSections[1].title, "")
        XCTAssertFalse(psalmSections[2].latin.contains("Psalmi {"))
        XCTAssertFalse(psalmSections[2].latin.contains("Qui regis Israël, inténde:"))
        XCTAssertEqual(psalmSections[3].title, "Psalmus 79 (9,20)")
        XCTAssertFalse(psalmSections[4].latin.contains("Psalmus 79(9-20)"))
        XCTAssertFalse(psalmSections[4].latin.contains("79:9 Víneam"))
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
        let days = try await repository.availableDays()
        var exercisedPrayerCount = 0

        for day in days {
            for hour in [OfficeHour.compline] {
                let office = try await repository.office(on: day.date, hour: hour)
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
                        "\(day.date) \(hour.rawValue) dropped \(marker)"
                    )
                }
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

    private func section(
        id: String,
        kind: OfficeSectionKind = .opening,
        title: String,
        rubric: String? = nil,
        latin: String,
        english: String? = nil,
        chant: ChantScore? = nil
    ) -> OfficeSection {
        OfficeSection(
            id: id,
            kind: kind,
            title: title,
            rubric: rubric,
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
}
