import HoursCore

struct HomeHeaderPresentation: Equatable {
    let rank: LiturgicalRank?
    let titleLatin: String
    let commemorations: [Commemoration]
    let officeContext: String?

    init(day: LiturgicalDay, office: OfficeDocument?) {
        rank = day.rank
        titleLatin = day.titleLatin
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
        let namesAnotherObservance =
            observance.observanceID != day.observanceID
            || observance.titleLatin != day.titleLatin

        switch eveningContext {
        case .firstVespers:
            let label = "\(prefix)First Vespers"
            return namesAnotherObservance
                ? "\(label) · \(observance.titleLatin)"
                : label
        case .secondVespers:
            guard namesAnotherObservance else { return nil }
            return "\(prefix)Second Vespers · \(observance.titleLatin)"
        case .ferialVespers:
            guard namesAnotherObservance else { return nil }
            let label = followsEveningOffice ? "After Vespers" : "Vespers"
            return "\(label) · \(observance.titleLatin)"
        @unknown default:
            return nil
        }
    }
}
