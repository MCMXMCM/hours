import Foundation
import HoursCore

struct HomeHeaderPresentation: Equatable {
    let rank: LiturgicalRank?
    let rankDisplayName: String?
    let titleLatin: String
    let commemorations: [Commemoration]
    let officeContext: String?

    init(day: LiturgicalDay, office: OfficeDocument?) {
        rank = day.rank
        rankDisplayName = day.rankLabel
        titleLatin = ObservanceTitle.latin(day.titleLatin)
        commemorations = day.commemorations
        officeContext = Self.officeContext(day: day, office: office)
    }

    private static func officeContext(
        day: LiturgicalDay,
        office: OfficeDocument?
    ) -> String? {
        guard let office,
              let observance = office.observance,
              let eveningContext = observance.eveningContext else {
            return nil
        }

        let followsEveningOffice = office.hour == .compline
        let prefix = followsEveningOffice ? "After " : ""
        let namesAnotherObservance = !sameObservance(
            day: day,
            officeObservance: observance
        )

        switch eveningContext {
        case .firstVespers:
            let label = "\(prefix)First Vespers"
            return namesAnotherObservance
                ? "\(label) · \(ObservanceTitle.latin(observance.titleLatin))"
                : label
        case .secondVespers:
            guard namesAnotherObservance else { return nil }
            return "\(prefix)Second Vespers · \(ObservanceTitle.latin(observance.titleLatin))"
        case .ferialVespers:
            guard namesAnotherObservance else { return nil }
            let label = followsEveningOffice ? "After Vespers" : "Vespers"
            return "\(label) · \(ObservanceTitle.latin(observance.titleLatin))"
        @unknown default:
            return nil
        }
    }

    private static func sameObservance(
        day: LiturgicalDay,
        officeObservance: OfficeObservance
    ) -> Bool {
        if officeObservance.observanceID == day.observanceID {
            return true
        }
        return normalizedObservanceTitle(officeObservance.titleLatin)
            == normalizedObservanceTitle(day.titleLatin)
    }

    private static func normalizedObservanceTitle(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\bHebd\b"#,
                with: "Hebdomadam",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"\bQuadr\b"#,
                with: "Quadragesima",
                options: [.regularExpression, .caseInsensitive]
            )
    }
}
