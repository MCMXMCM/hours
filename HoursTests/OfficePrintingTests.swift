import HoursCore
@testable import Hours
import UIKit
import XCTest

@MainActor
final class OfficePrintingTests: XCTestCase {
    func testSnapshotCapturesReaderSettingsAndClericWording() {
        let office = makeOffice(
            sections: [
                OfficeSection(
                    id: "collect",
                    kind: .collect,
                    title: "Oratio",
                    latin: """
                    ℣. Dómine, exáudi oratiónem meam.

                    ℟. Et clamor meus ad te véniat.
                    """,
                    english: """
                    ℣. O Lord, hear my prayer.

                    ℟. And let my cry come unto thee.
                    """
                )
            ]
        )

        let snapshot = OfficePrintSnapshot(
            office: office,
            showsEnglish: true,
            usesCompactPsalmody: true,
            isPriestOrDeaconPresent: true,
            readerScale: 4
        )

        XCTAssertTrue(snapshot.showsEnglish)
        XCTAssertTrue(snapshot.usesCompactPsalmody)
        XCTAssertTrue(snapshot.isPriestOrDeaconPresent)
        XCTAssertEqual(
            snapshot.readerScale,
            GregorianLayoutMetrics.maximumNotationScale
        )
        XCTAssertEqual(snapshot.jobName, "Compline — 2026-08-30")
        XCTAssertEqual(
            snapshot.sections,
            OfficeReaderSectionBuilder.displaySections(
                from: office.sections,
                format: office.format,
                usesCompactPsalmody: true
            )
        )
        XCTAssertEqual(
            snapshot.adjustedPrayerText(office.sections[0].latin),
            """
            ℣. Dóminus vobíscum.

            ℟. Et cum spíritu tuo.
            """
        )
    }

    func testLongOfficePaginatesWithinLetterAndA4Bounds() async throws {
        let paragraph = """
        Deus, in adiutórium meum inténde. Dómine, ad adiuvándum me festína.
        Glória Patri, et Fílio, et Spirítui Sancto.
        """
        let office = makeOffice(
            sections: (0..<80).map { index in
                OfficeSection(
                    id: "prayer-\(index)",
                    kind: .prayer,
                    title: "Prayer \(index + 1)",
                    latin: paragraph,
                    english: "O God, come to my assistance."
                )
            }
        )
        let renderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: office,
                showsEnglish: true,
                usesCompactPsalmody: false,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )

        for printableSize in [
            CGSize(width: 540, height: 720),
            CGSize(width: 523, height: 770),
        ] {
            let summary = renderer.testLayout(printableSize: printableSize)
            XCTAssertGreaterThan(summary.pageCount, 1)
            XCTAssertGreaterThan(summary.textItemCount, 80)
            XCTAssertEqual(summary.scoreItemCount, 0)
            XCTAssertLessThanOrEqual(
                summary.maximumItemBottom,
                summary.logicalPageHeight - 30 + 0.5
            )
        }
    }

    func testLatinAndEnglishBodiesUseSameHorizontalColumnAsNotation() async throws {
        let renderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: makeOffice(
                    sections: [
                        OfficeSection(
                            id: "prayer",
                            kind: .prayer,
                            title: "Prayer",
                            latin: "Dómine, exáudi oratiónem meam.",
                            english: "O Lord, hear my prayer."
                        )
                    ]
                ),
                showsEnglish: true,
                usesCompactPsalmody: false,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )

        let summary = renderer.testLayout(
            printableSize: CGSize(width: 540, height: 720)
        )
        let expectedLeft = (
            OfficePrintPageRenderer.logicalPageWidth
                - OfficePrintPageRenderer.logicalScoreWidth
        ) / 2

        XCTAssertEqual(summary.scoreAlignedTextItemCount, 2)
        XCTAssertEqual(
            summary.minimumScoreAlignedTextLeft,
            expectedLeft,
            accuracy: 0.5
        )
        XCTAssertEqual(
            summary.maximumScoreAlignedTextRight,
            OfficePrintPageRenderer.logicalPageWidth - expectedLeft,
            accuracy: 0.5
        )
    }

    func testRedundantEnglishHeadingsAndBodiesAreNotPrinted() async throws {
        let office = OfficeDocument(
            id: "2026-08-30-compline",
            date: LocalDay(year: 2026, month: 8, day: 30),
            hour: .compline,
            titleLatin: "Completorium",
            contextLabel: "Dominica",
            format: .authoritativeOrdered,
            sections: [
                OfficeSection(
                    id: "citation",
                    kind: .reading,
                    title: "Amen",
                    titleEnglish: " amen ",
                    latin: "1 Pet 5:8-9",
                    english: " 1 PET 5:8-9 "
                )
            ]
        )
        let englishRenderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: office,
                showsEnglish: true,
                usesCompactPsalmody: false,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )
        let latinRenderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: office,
                showsEnglish: false,
                usesCompactPsalmody: false,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )

        let pageSize = CGSize(width: 540, height: 720)
        let englishSummary = englishRenderer.testLayout(printableSize: pageSize)
        let latinSummary = latinRenderer.testLayout(printableSize: pageSize)

        XCTAssertEqual(englishSummary.textItemCount, latinSummary.textItemCount)
        XCTAssertEqual(englishSummary.scoreAlignedTextItemCount, 1)
    }

    func testImportedScoredGreetingPrintsClericalTextWhenSelected() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let office = try await repository.office(on: LocalDay(year: 2026, month: 9, day: 7), hour: .vespers)
        let greeting = try XCTUnwrap(office.sections.first {
            $0.latin.contains("Dómine, exáudi oratiónem meam.") && $0.chant != nil
        })
        for clergy in [false, true] {
            let snapshot = OfficePrintSnapshot(office: makeOffice(sections: [greeting]),
                showsEnglish: true, usesCompactPsalmody: false,
                isPriestOrDeaconPresent: clergy, readerScale: 1)
            let renderer = try await OfficePrintPageRenderer.prepare(snapshot: snapshot)
            let summary = renderer.testLayout(printableSize: CGSize(width: 540, height: 720))
            if clergy {
                XCTAssertEqual(summary.scoreItemCount, 0)
                XCTAssertTrue(snapshot.adjustedPrayerText(greeting.latin).contains("Dóminus vobíscum"))
            } else {
                XCTAssertGreaterThan(summary.scoreItemCount, 0)
            }
        }
    }

    func testBundledComplinePrintLayoutIncludesChantSystems() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 26),
            hour: .compline
        )
        let renderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: office,
                showsEnglish: true,
                usesCompactPsalmody: false,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )

        let summary = renderer.testLayout(
            printableSize: CGSize(width: 540, height: 720)
        )

        XCTAssertGreaterThan(summary.pageCount, 0)
        XCTAssertGreaterThan(summary.textItemCount, 0)
        XCTAssertGreaterThan(summary.scoreItemCount, 0)
        XCTAssertGreaterThan(
            renderer.testPDFData(
                pageSize: CGSize(width: 540, height: 720)
            ).count,
            1_000
        )
        XCTAssertLessThanOrEqual(
            summary.maximumItemBottom,
            summary.logicalPageHeight - 30 + 0.5
        )
    }

    func testCoreTextStaysUprightAfterUIKitLeavesAFlippedTextMatrix() async throws {
        let renderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: makeOffice(
                    sections: [
                        OfficeSection(
                            id: "prayer",
                            kind: .prayer,
                            title: "Prayer",
                            latin: "Amen."
                        )
                    ]
                ),
                showsEnglish: false,
                usesCompactPsalmody: true,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )

        let ink = renderer.testTextInkBalanceWithFlippedInputMatrix()

        XCTAssertGreaterThan(ink.top + ink.bottom, 0)
        XCTAssertGreaterThan(
            ink.bottom,
            ink.top,
            "An upright L has its horizontal foot in the lower half."
        )
    }

    func testNonCompactComplineNotationStaysInsidePrintSystems() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 9, day: 1),
            hour: .compline
        )
        let sections = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format,
            usesCompactPsalmody: false
        )
        var seenScoreIDs: Set<String> = []
        let scores = sections.compactMap(\.chant).filter {
            seenScoreIDs.insert($0.id).inserted
        }
        let preparations = await GregorianScorePreparer.prepare(
            scores: scores,
            width: OfficePrintPageRenderer.logicalScoreWidth,
            metrics: GregorianLayoutMetrics()
        )
        var maximumRenderedLyricOverflow: CGFloat = 0

        for score in scores {
            guard case let .ready(prepared) = preparations[score.id] else {
                return XCTFail("Failed to prepare \(score.incipit)")
            }
            for tile in prepared.drawing.tiles {
                let strokeMaxX = tile.strokeBatches
                    .map(\.path.boundingRect.maxX).max() ?? 0
                let glyphMaxX = tile.glyphPaths
                    .map(\.boundingRect.maxX).max() ?? 0
                let lyricMaxX = tile.lyrics
                    .map { $0.origin.x + $0.width }.max() ?? 0
                let initialMaxX = tile.initials
                    .map { $0.origin.x + $0.width }.max() ?? 0
                let inkMaxX = [
                    strokeMaxX,
                    glyphMaxX,
                    lyricMaxX,
                    initialMaxX,
                ].max() ?? 0
                XCTAssertLessThanOrEqual(
                    inkMaxX,
                    tile.frame.maxX + 0.5,
                    "\(score.incipit) paints to \(inkMaxX) outside "
                        + "system boundary \(tile.frame.maxX)."
                )
                for lyric in tile.lyrics {
                    maximumRenderedLyricOverflow = max(
                        maximumRenderedLyricOverflow,
                        renderedWidth(of: lyric) - lyric.width
                    )
                }
            }
        }
        XCTAssertLessThanOrEqual(
            maximumRenderedLyricOverflow,
            0.5,
            "Print typography is wider than the chant layout measurement."
        )

        let renderer = try await OfficePrintPageRenderer.prepare(
            snapshot: OfficePrintSnapshot(
                office: office,
                showsEnglish: false,
                usesCompactPsalmody: false,
                isPriestOrDeaconPresent: false,
                readerScale: 1
            )
        )
        let summary = renderer.testLayout(
            printableSize: CGSize(width: 540, height: 720)
        )
        let expectedGutter = (
            OfficePrintPageRenderer.logicalPageWidth
                - OfficePrintPageRenderer.logicalScoreWidth
        ) / 2
        XCTAssertGreaterThanOrEqual(
            summary.minimumScoreLeft,
            expectedGutter - 0.5
        )
        XCTAssertLessThanOrEqual(
            summary.maximumScoreRight,
            OfficePrintPageRenderer.logicalPageWidth - expectedGutter + 0.5
        )
    }

    private func makeOffice(
        sections: [OfficeSection]
    ) -> OfficeDocument {
        OfficeDocument(
            id: "2026-08-30-compline",
            date: LocalDay(year: 2026, month: 8, day: 30),
            hour: .compline,
            titleLatin: "Completorium",
            titleEnglish: "Compline",
            contextLabel: "Dominica",
            format: .authoritativeOrdered,
            sections: sections
        )
    }

    private func renderedWidth(of lyric: GregorianPlacedLyric) -> CGFloat {
        let base = UIFont(name: "EBGaramond-Regular", size: lyric.fontSize)
            ?? UIFont.systemFont(ofSize: lyric.fontSize)
        let traits: UIFontDescriptor.SymbolicTraits = switch lyric.style {
        case .accented: [.traitBold]
        case .preparatory: [.traitItalic]
        case .regular, .rubric: []
        @unknown default: []
        }
        let font = traits.isEmpty
            ? base
            : base.fontDescriptor.withSymbolicTraits(traits).map {
                UIFont(descriptor: $0, size: lyric.fontSize)
            } ?? base
        return ceil(
            NSAttributedString(
                string: lyric.text,
                attributes: [.font: font]
            ).size().width
        )
    }

    private func bundledDatabaseURL() throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite"
            )
        )
    }
}
