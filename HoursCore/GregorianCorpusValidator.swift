import Foundation

public struct GregorianCorpusValidationFailure: Hashable, Sendable {
    public let officeID: String
    public let scoreID: String
    public let message: String

    public init(officeID: String, scoreID: String, message: String) {
        self.officeID = officeID
        self.scoreID = scoreID
        self.message = message
    }
}

public struct GregorianCorpusValidationError: Error, LocalizedError, Sendable {
    public let failures: [GregorianCorpusValidationFailure]

    public init(failures: [GregorianCorpusValidationFailure]) {
        self.failures = failures
    }

    public var errorDescription: String? {
        guard let first = failures.first else {
            return "The chant corpus failed native notation validation."
        }
        let suffix = failures.count == 1 ? "" : " and \(failures.count - 1) more"
        return "Native notation validation failed for \(first.scoreID): \(first.message)\(suffix)."
    }
}

public enum GregorianCorpusValidator {
    public static func validate(office: OfficeDocument) throws {
        try validate(offices: [office])
    }

    public static func validate(offices: [OfficeDocument]) throws {
        var failures: [GregorianCorpusValidationFailure] = []
        var validatedScoreIDs: Set<String> = []
        for office in offices {
            for score in office.sections.compactMap(\.chant) {
                guard validatedScoreIDs.insert(score.id).inserted else { continue }
                do {
                    _ = try GregorianScoreParser.parse(
                        gabc: score.gabc,
                        timeline: score.timeline
                    )
                } catch {
                    failures.append(
                        GregorianCorpusValidationFailure(
                            officeID: office.id,
                            scoreID: score.id,
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }
        if !failures.isEmpty {
            throw GregorianCorpusValidationError(failures: failures)
        }
    }
}
