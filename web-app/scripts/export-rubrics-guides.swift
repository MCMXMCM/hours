// Writes the Rubrics guides as JSON, one file for each edition, for the web
// app to show.
//
// The guides are written in the iOS app as Swift values, in
// `HoursApp/RubricsGuideContent.swift` (Roman 1960) and
// `HoursApp/Rubrics1954GuideContent.swift` (Roman 1954). This file is
// compiled together with those two, unmodified, by
// `export-rubrics-guides.mjs`; they declare the guides' own types, and it
// reads the values they hold. No sentence is copied by hand: what is written
// here is what the compiler made of the app's own source.
//
//   export-rubrics-guides <output directory> <signature>
//
// A report of what was written is printed on standard output.

import Foundation

/// The format of a guide file, raised when its shape changes.
private let schema = 1

private struct ExportedCitation: Encodable {
    let label: String
    let url: String
}

private struct ExportedRule: Encodable {
    let id: String
    let title: String
    let text: String
    let citations: [ExportedCitation]
}

private struct ExportedTopic: Encodable {
    let id: String
    let title: String
    let summary: String
    let rules: [ExportedRule]
}

private struct ExportedEdition: Encodable {
    let id: String
    let year: String
    let subtitle: String
    let introduction: String
    let topics: [ExportedTopic]
}

private struct ExportedGuide: Encodable {
    let schema: Int
    /// Names the sources this file was made from; see the script.
    let signature: String
    /// The edition's place among `RubricsEdition.allCases`.
    let order: Int
    let edition: ExportedEdition
}

private struct ExportedGuideReport: Encodable {
    let id: String
    let file: String
    let topics: Int
    let rules: Int
    let paragraphs: Int
    let citations: Int
    let characters: Int
}

private struct ExportReport: Encodable {
    let schema: Int
    let guides: [ExportedGuideReport]
}

private func exported(_ edition: RubricsEdition) -> ExportedEdition {
    ExportedEdition(
        id: edition.rawValue,
        year: edition.year,
        subtitle: edition.subtitle,
        introduction: edition.introduction,
        topics: edition.topics.map { topic in
            ExportedTopic(
                id: topic.id,
                title: topic.title,
                summary: topic.summary,
                rules: topic.rules.map { rule in
                    ExportedRule(
                        id: rule.id,
                        title: rule.title,
                        text: rule.text,
                        citations: rule.citations.map { citation in
                            ExportedCitation(label: citation.label, url: citation.url.absoluteString)
                        }
                    )
                }
            )
        }
    )
}

private func report(_ edition: ExportedEdition, file: String) -> ExportedGuideReport {
    let rules = edition.topics.flatMap(\.rules)
    // The reader divides a rule into paragraphs exactly so.
    let paragraphs = rules.flatMap { $0.text.components(separatedBy: "\n\n") }
    let prose = [edition.subtitle, edition.introduction]
        + edition.topics.flatMap { [$0.title, $0.summary] }
        + rules.flatMap { [$0.title, $0.text] + $0.citations.map(\.label) }
    return ExportedGuideReport(
        id: edition.id,
        file: file,
        topics: edition.topics.count,
        rules: rules.count,
        paragraphs: paragraphs.count,
        citations: rules.reduce(0) { $0 + $1.citations.count },
        characters: prose.reduce(0) { $0 + $1.count }
    )
}

@main
private enum ExportRubricsGuides {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            FileHandle.standardError.write(Data("usage: export-rubrics-guides <output directory> <signature>\n".utf8))
            exit(2)
        }
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let signature = arguments[2]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            var guides: [ExportedGuideReport] = []
            for (order, edition) in RubricsEdition.allCases.enumerated() {
                let guide = ExportedGuide(schema: schema, signature: signature, order: order, edition: exported(edition))
                let file = "rubrics-\(edition.rawValue).json"
                var data = try encoder.encode(guide)
                data.append(contentsOf: "\n".utf8)
                try data.write(to: directory.appendingPathComponent(file), options: .atomic)
                guides.append(report(guide.edition, file: file))
            }
            var output = try encoder.encode(ExportReport(schema: schema, guides: guides))
            output.append(contentsOf: "\n".utf8)
            FileHandle.standardOutput.write(output)
        } catch {
            FileHandle.standardError.write(Data("export-rubrics-guides: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
