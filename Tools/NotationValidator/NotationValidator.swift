import Foundation
import Darwin

@main
struct NotationValidator {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let allowIncomplete = arguments.contains("--allow-incomplete")
        guard let databasePath = arguments.first, !databasePath.hasPrefix("--") else {
            fail(usage)
        }

        if let reportIndex = arguments.firstIndex(of: "--reader-layout-report") {
            let values = arguments.dropFirst(reportIndex + 1).prefix(3)
            guard values.count == 3,
                  let width = Double(values[values.index(values.startIndex, offsetBy: 2)]),
                  width >= 240 else {
                fail(usage)
            }
            await reportReaderLayouts(
                databasePath: databasePath,
                date: values[values.startIndex],
                hour: values[values.index(after: values.startIndex)],
                width: width
            )
            return
        }

        let positional = arguments.filter { !$0.hasPrefix("--") }
        guard positional.count == 1 else {
            fail(usage)
        }

        do {
            let databaseURL = URL(fileURLWithPath: databasePath)
            let repository = try SQLiteContentRepository(databaseURL: databaseURL)
            let days: [LiturgicalDay]
            do {
                days = try await repository.availableDays()
            } catch {
                throw ValidationError(
                    "Could not decode the day index: \(error.localizedDescription)"
                )
            }
            var offices: [OfficeDocument] = []
            offices.reserveCapacity(days.count * OfficeHour.allCases.count)
            var missingOfficeCount = 0
            for day in days {
                for hour in OfficeHour.allCases {
                    do {
                        offices.append(try await repository.office(on: day.date, hour: hour))
                    } catch ContentRepositoryError.contentUnavailable where allowIncomplete {
                        missingOfficeCount += 1
                    } catch {
                        throw ValidationError(
                            "Could not decode \(day.date):\(hour.rawValue): "
                                + error.localizedDescription
                        )
                    }
                }
            }
            let unavailableOfficeCount = offices.filter {
                $0.format == .contentUnavailable
            }.count
            try GregorianCorpusValidator.validate(offices: offices)
            try validateSemanticFixtures()
            let layoutCount = try validateEngraving(offices: offices)
            print(
                "Validated \(offices.flatMap(\.playableScores).count) native scores "
                    + "across \(offices.count) offices and \(layoutCount) responsive layouts"
                    + (unavailableOfficeCount == 0 && missingOfficeCount == 0
                        ? "."
                        : "; \(unavailableOfficeCount) metadata-only placeholders and "
                            + "\(missingOfficeCount) omitted offices.")
            )
        } catch let error as GregorianCorpusValidationError {
            fail(
                error.failures.map {
                    "\($0.scoreID): \($0.message)"
                }.joined(separator: "\n")
            )
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static let usage = """
        usage: NotationValidator /path/to/content.sqlite [--allow-incomplete]
               NotationValidator /path/to/content.sqlite \
        --reader-layout-report YYYY-MM-DD HOUR WIDTH
        """

    private static func reportReaderLayouts(
        databasePath: String,
        date: String,
        hour: String,
        width: Double
    ) async {
        let dateParts = date.split(separator: "-").compactMap { Int($0) }
        guard dateParts.count == 3,
              let officeHour = OfficeHour(rawValue: hour) else {
            fail(usage)
        }

        do {
            let repository = try SQLiteContentRepository(
                databaseURL: URL(fileURLWithPath: databasePath)
            )
            let office = try await repository.office(
                on: LocalDay(
                    year: dateParts[0],
                    month: dateParts[1],
                    day: dateParts[2]
                ),
                hour: officeHour
            )
            var seenScoreIDs: Set<String> = []
            let scores = office.sections.compactMap { section in
                section.chant.map { (section.id, $0) }
            }.filter {
                seenScoreIDs.insert($0.1.id).inserted
            }
            var totalHeight = 0.0
            var totalSeconds = 0.0

            print("Reader layout report: \(date) \(hour), width \(Int(width))")
            print(
                "layout\tneumes\tevents\tmilliseconds\tsection"
                    + "\tfirst-event\tincipit"
            )
            for (sectionID, score) in scores {
                let start = ContinuousClock.now
                let parsed = try GregorianScoreParser.parse(
                    gabc: score.gabc,
                    timeline: score.timeline
                )
                let layout = GregorianEngravingLayoutEngine().layout(
                    score: parsed,
                    width: width,
                    openingLabel: GregorianEngravingLayoutEngine.openingLabel(
                        forMode: score.mode
                    )
                )
                let seconds = start.duration(to: .now).seconds
                totalHeight += layout.size.height
                totalSeconds += seconds
                print(
                    "\(Int(layout.size.height.rounded()))"
                        + "\t\(layout.neumes.count)"
                        + "\t\(score.timeline.events.count)"
                        + "\t\(String(format: "%.2f", seconds * 1_000))"
                        + "\t\(sectionID)"
                        + "\t\(score.timeline.events.first?.id ?? "—")"
                        + "\t\(score.incipit)"
                )
            }
            print(
                "Totals: \(scores.count) scores; "
                    + "\(Int(totalHeight.rounded())) pt of exact reader geometry; "
                    + "\(String(format: "%.2f", totalSeconds * 1_000)) ms"
            )
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("NotationValidator: \(message)\n".utf8))
        exit(EXIT_FAILURE)
    }

    private static func validateEngraving(offices: [OfficeDocument]) throws -> Int {
        guard GregorianGlyphName.allCases.count == 49 else {
            throw ValidationError("generated glyph catalog should contain 49 names")
        }
        for name in GregorianGlyphName.allCases where name != .none {
            let definition = GregorianGlyphCatalog.definition(for: name)
            guard !definition.paths.flatMap({ $0 }).isEmpty else {
                throw ValidationError("\(name.rawValue) has no vector commands")
            }
        }

        let widths: [CGFloat] = [320, 390, 768]
        var count = 0
        var seenScoreIDs: Set<String> = []
        let scores = offices
            .flatMap(\.playableScores)
            .filter { seenScoreIDs.insert($0.id).inserted }
        for score in scores {
            let notation = try GregorianScoreParser.parse(
                gabc: score.gabc,
                timeline: score.timeline
            )
            for width in widths {
                let layout = GregorianEngravingLayoutEngine().layout(
                    score: notation,
                    width: width
                )
                guard layout.events.map(\.eventID) == notation.eventIDs else {
                    throw ValidationError("\(score.id) lost event identity at width \(width)")
                }
                guard layout.size.width.isFinite, layout.size.height.isFinite,
                      layout.glyphs.allSatisfy({
                          $0.frame.minX.isFinite && $0.frame.minY.isFinite
                              && $0.frame.width.isFinite && $0.frame.height.isFinite
                      }) else {
                    throw ValidationError("\(score.id) produced non-finite engraving geometry")
                }
                for line in Dictionary(grouping: layout.neumes, by: \.lineIndex).values {
                    let ordered = line.sorted { $0.hitFrame.minX < $1.hitFrame.minX }
                    for pair in zip(ordered, ordered.dropFirst())
                    where pair.0.hitFrame.maxX > pair.1.hitFrame.minX + 0.01 {
                        throw ValidationError("\(score.id) produced overlapping neume targets")
                    }
                }
                count += 1
            }
        }
        return count
    }

    private static func validateSemanticFixtures() throws {
        let syllables = ["po", "po", "cli", "cli", "scan", "scan", "scan", "tor", "tor", "tor"]
        let events = syllables.enumerated().map { index, syllable in
            ChantEvent(
                id: "semantic-\(index)",
                phraseID: "semantic",
                syllableID: "semantic-\(syllable)",
                syllable: syllable,
                relativePitch: index
            )
        }
        let score = try GregorianScoreParser.parse(
            gabc: "name: semantic; %% (c4) po(fg) cli(gf) scan(fgh) tor(fhg) (::)",
            timeline: ChantTimeline(events: events)
        )
        guard score.neumes.map(\.form) == [.podatus, .clivis, .scandicus, .torculus] else {
            throw ValidationError("named-neume classification regression")
        }
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        let names = Set(layout.glyphs.map(\.kind.catalogName))
        guard names.contains(.podatusLower), names.contains(.podatusUpper) else {
            throw ValidationError("podatus did not select canonical composite glyphs")
        }

        let boundaryEvents = (0..<4).map { index in
            ChantEvent(
                id: "boundary-\(index)",
                phraseID: "boundary",
                syllableID: "boundary",
                syllable: "Ky",
                relativePitch: index
            )
        }
        let boundary = try GregorianScoreParser.parse(
            gabc: "name: boundary; %% (c4) Ky(fg!hi) (::)",
            timeline: ChantTimeline(events: boundaryEvents)
        )
        guard boundary.neumes.map(\.form) == [.podatus, .podatus],
              boundary.neumes.map(\.lyric) == ["Ky", ""] else {
            throw ValidationError("zero-space neume boundary regression")
        }

        let markedEvent = ChantEvent(
            id: "marked",
            phraseID: "marked",
            syllableID: "marked",
            syllable: "Ky",
            relativePitch: 0
        )
        let marked = try GregorianScoreParser.parse(
            gabc: "name: marked; %% (c4) Ky(f.._0#') (::)",
            timeline: ChantTimeline(events: [markedEvent])
        )
        guard let note = marked.neumes.first?.notes.first,
              note.moraCount == 2,
              note.episemaPosition == .below,
              note.accidental == .sharp,
              note.hasIctus else {
            throw ValidationError("detailed note modifier regression")
        }
    }

    private struct ValidationError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
