import Foundation

public struct HoursLiturgicalDaySummary: Codable, Equatable, Sendable {
    public let date: LocalDay
    public let titleLatin: String
    public let rank: LiturgicalRank?
    public let sourceRank: String?
    public var rankDisplayName: String? { sourceRank ?? rank?.displayName }
    /// The rank as shown to readers; see `LiturgicalDay.rankLabel`.
    public var rankLabel: String? { rank?.englishDisplayName ?? sourceRank }

    public init(
        date: LocalDay,
        titleLatin: String,
        rank: LiturgicalRank?,
        sourceRank: String? = nil
    ) {
        self.date = date
        self.titleLatin = titleLatin
        self.rank = rank
        self.sourceRank = sourceRank
    }
}

public struct HoursLiturgicalCalendarSnapshot: Codable, Equatable, Sendable {
    public let days: [HoursLiturgicalDaySummary]
    public let tradition: OfficeTradition

    public init(days: [LiturgicalDay], tradition: OfficeTradition = .roman1960) {
        self.tradition = tradition
        self.days = days.map {
            HoursLiturgicalDaySummary(
                date: $0.date,
                titleLatin: $0.titleLatin,
                rank: $0.rank,
                sourceRank: $0.sourceRank
            )
        }
    }

    private enum CodingKeys: String, CodingKey { case days, tradition }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decode([HoursLiturgicalDaySummary].self, forKey: .days)
        tradition = try container.decodeIfPresent(OfficeTradition.self, forKey: .tradition) ?? .roman1960
    }

    public func day(on date: LocalDay) -> HoursLiturgicalDaySummary? {
        days.first { $0.date == date }
    }
}

public enum HoursLiturgicalCalendarSnapshotStoreError: Error {
    case appGroupContainerUnavailable
}

public enum HoursLiturgicalCalendarRefreshSchedule {
    public static let unavailableRetryInterval: TimeInterval = 5 * 60

    public static func retryDate(
        for snapshot: HoursLiturgicalCalendarSnapshot?,
        officeDay: LocalDay,
        now: Date,
        retryInterval: TimeInterval = unavailableRetryInterval
    ) -> Date? {
        guard snapshot?.day(on: officeDay) == nil else {
            return nil
        }

        return now.addingTimeInterval(retryInterval)
    }
}

public struct HoursLiturgicalCalendarSnapshotStore: Sendable {
    public static var shared: Self {
        Self(
            fileURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    HoursSharedPreferences.appGroupIdentifier
            )?.appendingPathComponent("liturgical-calendar.json")
        )
    }

    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public func save(days: [LiturgicalDay], tradition: OfficeTradition = .roman1960) throws {
        _ = try saveIfChanged(days: days, tradition: tradition)
    }

    @discardableResult
    public func saveIfChanged(days: [LiturgicalDay], tradition: OfficeTradition = .roman1960) throws -> Bool {
        guard let fileURL else {
            throw HoursLiturgicalCalendarSnapshotStoreError
                .appGroupContainerUnavailable
        }
        let snapshot = HoursLiturgicalCalendarSnapshot(days: days, tradition: tradition)
        let data = try JSONEncoder().encode(snapshot)
        if let existing = try? Data(contentsOf: fileURL) {
            if existing == data {
                return false
            }
            if let existingSnapshot = try? JSONDecoder().decode(
                HoursLiturgicalCalendarSnapshot.self,
                from: existing
            ), existingSnapshot == snapshot {
                return false
            }
        }
        try data.write(to: fileURL, options: .atomic)
        return true
    }

    public func load(expectedTradition: OfficeTradition? = nil) throws -> HoursLiturgicalCalendarSnapshot {
        guard let fileURL else {
            throw HoursLiturgicalCalendarSnapshotStoreError
                .appGroupContainerUnavailable
        }

        let data = try Data(contentsOf: fileURL)
        let snapshot = try JSONDecoder().decode(
            HoursLiturgicalCalendarSnapshot.self,
            from: data
        )
        guard expectedTradition == nil || snapshot.tradition == expectedTradition else {
            throw ContentRepositoryError.invalidContent("The widget calendar belongs to another office tradition.")
        }
        return snapshot
    }
}
