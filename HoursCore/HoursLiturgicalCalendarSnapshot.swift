import Foundation

public struct HoursLiturgicalDaySummary: Codable, Equatable, Sendable {
    public let date: LocalDay
    public let titleLatin: String
    public let rank: LiturgicalRank?

    public init(
        date: LocalDay,
        titleLatin: String,
        rank: LiturgicalRank?
    ) {
        self.date = date
        self.titleLatin = titleLatin
        self.rank = rank
    }
}

public struct HoursLiturgicalCalendarSnapshot: Codable, Equatable, Sendable {
    public let days: [HoursLiturgicalDaySummary]

    public init(days: [LiturgicalDay]) {
        self.days = days.map {
            HoursLiturgicalDaySummary(
                date: $0.date,
                titleLatin: $0.titleLatin,
                rank: $0.rank
            )
        }
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

    public func save(days: [LiturgicalDay]) throws {
        _ = try saveIfChanged(days: days)
    }

    @discardableResult
    public func saveIfChanged(days: [LiturgicalDay]) throws -> Bool {
        guard let fileURL else {
            throw HoursLiturgicalCalendarSnapshotStoreError
                .appGroupContainerUnavailable
        }
        let snapshot = HoursLiturgicalCalendarSnapshot(days: days)
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

    public func load() throws -> HoursLiturgicalCalendarSnapshot {
        guard let fileURL else {
            throw HoursLiturgicalCalendarSnapshotStoreError
                .appGroupContainerUnavailable
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(
            HoursLiturgicalCalendarSnapshot.self,
            from: data
        )
    }
}
