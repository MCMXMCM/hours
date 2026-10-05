import Foundation
import CoreGraphics
import HoursCore

nonisolated struct ChantGuideDocument: Codable, Sendable {
    let version: Int
    let title: String
    let introduction: String
    let sections: [ChantGuideSection]
    let examples: [ChantGuideExample]
    let glossary: [ChantGuideTerm]

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "chant-guide", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func example(_ id: String) -> ChantGuideExample? {
        examples.first { $0.id == id }
    }
}

nonisolated struct ChantGuideSection: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let source: String
    let blocks: [ChantGuideBlock]
}

nonisolated struct ChantGuideBlock: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case prose, example, pronunciation }
    let id: String
    let kind: Kind
    let title: String?
    let text: String?
    let detail: String?
    let exampleID: String?
}

nonisolated struct ChantGuideExample: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let caption: String
    let source: String
    let variants: [ChantGuideVariant]
    var pitchReference: ChantScore { variants[0].score }
}

nonisolated struct ChantGuideVariant: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let explanation: String
    let score: ChantScore
    let annotations: [ChantGuideAnnotation]
    let formula: [ChantGuideFormulaNote]?
}

nonisolated struct ChantGuideAnnotation: Codable, Identifiable, Sendable {
    var id: String { eventIDs.joined(separator: ",") + label }
    let label: String
    let explanation: String
    let eventIDs: [String]
}

/// Formula symbols illustrate a rule; they are deliberately not ChantEvents.
nonisolated struct ChantGuideFormulaNote: Codable, Sendable {
    let step: Int
    let optional: Bool
    let label: String
}

nonisolated struct ChantGuideTerm: Codable, Identifiable, Sendable {
    var id: String { term }
    let term: String
    let definition: String
    let sectionID: String
}

nonisolated enum ChantGuideViewport {
    static func target(frames: [String: CGRect], viewport: CGRect, playingID: String?) -> String? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let visible = frames.filter { $0.value.intersection(viewport).height > 1 }
        if let playingID, visible[playingID] != nil { return playingID }
        return visible.min {
            let left = abs($0.value.midY - viewport.midY)
            let right = abs($1.value.midY - viewport.midY)
            return left == right ? $0.key < $1.key : left < right
        }?.key
    }
}
