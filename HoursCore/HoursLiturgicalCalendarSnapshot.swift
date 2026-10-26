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
    /// The days the corpus stores, under their stored civil dates.
    public let days: [HoursLiturgicalDaySummary]
    public let tradition: OfficeTradition
    /// The first and last civil years a perennial corpus serves, and the
    /// years it stores: with them the widget finds the day of any served
    /// date among the stored days, however long the app stays unopened.
    /// Nil where `days` holds every date served.
    public let servedFromYear: Int?
    public let servedThroughYear: Int?
    public let storedYears: [Int]?

    public init(
        days: [LiturgicalDay],
        tradition: OfficeTradition = .roman1960,
        plan: PerennialYearPlan? = nil
    ) {
        self.tradition = tradition
        self.days = days.map {
            HoursLiturgicalDaySummary(
                date: $0.date,
                titleLatin: $0.titleLatin,
                rank: $0.rank,
                sourceRank: $0.sourceRank
            )
        }
        servedFromYear = plan?.servedYears.lowerBound
        servedThroughYear = plan?.servedYears.upperBound
        storedYears = plan?.storedYears
    }

    private enum CodingKeys: String, CodingKey {
        case days, tradition, servedFromYear, servedThroughYear, storedYears
        case observances, dates, observanceIndices
    }

    /// A title and rank, written once for all the days that keep it. The
    /// widget decodes the file within the 30 MB iOS allows it, and a
    /// perennial corpus's 21,562 days, each written in full, took some 14 MB
    /// of that, though a few hundred titles serve them all.
    private struct Observance: Codable, Hashable {
        let titleLatin: String
        let rank: LiturgicalRank?
        let sourceRank: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.observances) {
            let observances = try container.decode([Observance].self, forKey: .observances)
            let dates = try container.decode([String].self, forKey: .dates)
            let indices = try container.decode([Int].self, forKey: .observanceIndices)
            guard dates.count == indices.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .observanceIndices,
                    in: container,
                    debugDescription: "Each stored date needs the index of its observance."
                )
            }
            days = try zip(dates, indices).map { date, index in
                guard let day = LocalDay(iso8601: date), observances.indices.contains(index) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .dates,
                        in: container,
                        debugDescription: "\(date) is not a stored date with an observance."
                    )
                }
                let observance = observances[index]
                return HoursLiturgicalDaySummary(
                    date: day,
                    titleLatin: observance.titleLatin,
                    rank: observance.rank,
                    sourceRank: observance.sourceRank
                )
            }
        } else {
            // Each day in full, as earlier builds wrote it.
            days = try container.decode([HoursLiturgicalDaySummary].self, forKey: .days)
        }
        tradition = try container.decodeIfPresent(OfficeTradition.self, forKey: .tradition) ?? .roman1960
        servedFromYear = try container.decodeIfPresent(Int.self, forKey: .servedFromYear)
        servedThroughYear = try container.decodeIfPresent(Int.self, forKey: .servedThroughYear)
        storedYears = try container.decodeIfPresent([Int].self, forKey: .storedYears)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var observances: [Observance] = []
        var indexOfObservance: [Observance: Int] = [:]
        let indices = days.map { day in
            let observance = Observance(
                titleLatin: day.titleLatin,
                rank: day.rank,
                sourceRank: day.sourceRank
            )
            if let index = indexOfObservance[observance] {
                return index
            }
            indexOfObservance[observance] = observances.count
            observances.append(observance)
            return observances.count - 1
        }
        try container.encode(observances, forKey: .observances)
        try container.encode(days.map(\.date.description), forKey: .dates)
        try container.encode(indices, forKey: .observanceIndices)
        try container.encode(tradition, forKey: .tradition)
        try container.encodeIfPresent(servedFromYear, forKey: .servedFromYear)
        try container.encodeIfPresent(servedThroughYear, forKey: .servedThroughYear)
        try container.encodeIfPresent(storedYears, forKey: .storedYears)
    }

    public func day(on date: LocalDay) -> HoursLiturgicalDaySummary? {
        guard let servedFromYear, let servedThroughYear, let storedYears else {
            return days.first { $0.date == date }
        }
        // A served date is read from the stored year of its type and shown
        // under its own date.
        guard servedFromYear <= servedThroughYear,
              let plan = try? PerennialYearPlan(
                servedYears: servedFromYear...servedThroughYear,
                storedYears: storedYears
              ),
              let stored = plan.storedDay(for: date),
              let day = days.first(where: { $0.date == stored }) else {
            return nil
        }
        return HoursLiturgicalDaySummary(
            date: date,
            titleLatin: day.titleLatin,
            rank: day.rank,
            sourceRank: day.sourceRank
        )
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
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                HoursSharedPreferences.appGroupIdentifier
        )
        // Earlier builds wrote each day in full to liturgical-calendar.json.
        // The widget no longer reads that file, which could cost it more
        // memory than it has; the app removes it when it saves.
        return Self(
            fileURL: container?.appendingPathComponent("liturgical-calendar-v2.json"),
            supersededFileURL: container?.appendingPathComponent("liturgical-calendar.json")
        )
    }

    private let fileURL: URL?
    private let supersededFileURL: URL?

    public init(fileURL: URL?, supersededFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.supersededFileURL = supersededFileURL
    }

    public func save(
        days: [LiturgicalDay],
        tradition: OfficeTradition = .roman1960,
        plan: PerennialYearPlan? = nil
    ) throws {
        _ = try saveIfChanged(days: days, tradition: tradition, plan: plan)
    }

    /// Saves the days the corpus stores, with the plan by which a perennial
    /// corpus serves other years from them.
    @discardableResult
    public func saveIfChanged(
        days: [LiturgicalDay],
        tradition: OfficeTradition = .roman1960,
        plan: PerennialYearPlan? = nil
    ) throws -> Bool {
        guard let fileURL else {
            throw HoursLiturgicalCalendarSnapshotStoreError
                .appGroupContainerUnavailable
        }
        if let supersededFileURL {
            try? FileManager.default.removeItem(at: supersededFileURL)
        }
        let snapshot = HoursLiturgicalCalendarSnapshot(days: days, tradition: tradition, plan: plan)
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
