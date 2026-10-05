import CryptoKit
import Foundation

public enum VisibleContentDigest {
    public static func calculate(for sections: [OfficeSection]) throws -> String {
        let payload = sections.map(VisibleSection.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func validate(_ office: OfficeDocument) throws {
        guard office.format?.preservesSourceOrder == true else { return }
        guard let expected = office.visibleContentDigest,
              !expected.isEmpty else {
            throw ContentRepositoryError.invalidContent(
                "\(office.date):\(office.hour.rawValue) has no visible-content digest."
            )
        }
        let actual = try calculate(for: office.sections)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw ContentRepositoryError.invalidContent(
                "\(office.date):\(office.hour.rawValue) does not match its pinned visible-content digest."
            )
        }
    }
}

private struct VisibleSection: Encodable {
    let kind: OfficeSectionKind
    let title: String
    let latin: String
    let english: String?
    let rubric: String?
    let chant: VisibleChant?

    init(_ section: OfficeSection) {
        kind = section.kind
        title = section.title
        latin = section.latin
        english = section.english
        rubric = section.rubric
        chant = section.chant.map(VisibleChant.init)
    }

    private enum CodingKeys: String, CodingKey {
        case chant
        case english
        case kind
        case latin
        case rubric
        case title
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(latin, forKey: .latin)
        if let english {
            try container.encode(english, forKey: .english)
        } else {
            try container.encodeNil(forKey: .english)
        }
        if let rubric {
            try container.encode(rubric, forKey: .rubric)
        } else {
            try container.encodeNil(forKey: .rubric)
        }
        if let chant {
            try container.encode(chant, forKey: .chant)
        } else {
            try container.encodeNil(forKey: .chant)
        }
    }
}

private struct VisibleChant: Encodable {
    let gabc: String
    let reviewStatus: ChantReviewStatus

    init(_ chant: ChantScore) {
        gabc = chant.gabc
        reviewStatus = chant.reviewStatus
    }
}
