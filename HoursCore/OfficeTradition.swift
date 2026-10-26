import Foundation

/// A corpus identity, independent of language, appearance, and civil date.
public enum OfficeTradition: String, Codable, CaseIterable, Identifiable, Sendable {
    case roman1954
    case roman1960

    public var id: Self { self }

    public var title: String {
        switch self {
        case .roman1954: "Roman 1954"
        case .roman1960: "Roman 1960"
        }
    }

    public var rubrics: String {
        switch self {
        case .roman1954: "Divino Afflatu - 1954"
        case .roman1960: "Rubrics 1960 - 1960"
        }
    }

    public init?(rubrics: String) {
        guard let value = Self.allCases.first(where: { $0.rubrics == rubrics }) else {
            return nil
        }
        self = value
    }

    public var bundledResourceName: String {
        switch self {
        case .roman1954: "roman-1954-office"
        case .roman1960: "base-office"
        }
    }

    public var description: String {
        switch self {
        case .roman1954:
            "The Roman Divine Office under the pre-1955 Divino Afflatu rubrics. This edition follows Divinum Officium’s 1954 calendar: the general calendar as amended through 1954, including the Queenship of Our Lady and St Pius X."
        case .roman1960:
            "The Roman Divine Office under the 1960 rubrics."
        }
    }

    public func databaseURL(in bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(
            forResource: bundledResourceName,
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: bundledResourceName, withExtension: "sqlite") else {
            throw ContentRepositoryError.databaseUnavailable(
                "The bundled \(title) corpus is missing."
            )
        }
        return url
    }
}
