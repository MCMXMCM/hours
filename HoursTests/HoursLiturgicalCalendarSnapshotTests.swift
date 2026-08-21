import Foundation
import HoursCore
@testable import Hours
import XCTest

final class HoursLiturgicalCalendarSnapshotTests: XCTestCase {
    func testRoundTripKeepsWidgetCalendarFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("calendar.json")
        let store = HoursLiturgicalCalendarSnapshotStore(
            fileURL: fileURL
        )
        let date = LocalDay(year: 2026, month: 8, day: 6)
        let day = LiturgicalDay(
            date: date,
            observanceID: "08-06-transfiguration",
            titleLatin:
                "In Transfiguratione Domini Nostri Jesu Christi",
            rank: .secondClass,
            season: "Post Pentecosten"
        )

        try store.save(days: [day])

        let savedDay = try XCTUnwrap(store.load().day(on: date))
        XCTAssertEqual(savedDay.titleLatin, day.titleLatin)
        XCTAssertEqual(savedDay.rank, .secondClass)
    }

    func testSaveIfChangedSkipsIdenticalSnapshotAndWritesChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("calendar.json")
        let store = HoursLiturgicalCalendarSnapshotStore(fileURL: fileURL)
        let firstDay = LiturgicalDay(
            date: LocalDay(year: 2026, month: 8, day: 6),
            observanceID: "transfiguration",
            titleLatin: "In Transfiguratione Domini",
            rank: .secondClass,
            season: "Post Pentecosten"
        )
        let changedDay = LiturgicalDay(
            date: firstDay.date,
            observanceID: firstDay.observanceID,
            titleLatin: "In Transfiguratione Domini Nostri Jesu Christi",
            rank: firstDay.rank,
            season: firstDay.season
        )

        XCTAssertTrue(try store.saveIfChanged(days: [firstDay]))
        let originalData = try Data(contentsOf: fileURL)
        let originalModificationDate = try XCTUnwrap(
            fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        )

        XCTAssertFalse(try store.saveIfChanged(days: [firstDay]))
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertEqual(
            try fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate,
            originalModificationDate
        )

        XCTAssertTrue(try store.saveIfChanged(days: [changedDay]))
        XCTAssertNotEqual(try Data(contentsOf: fileURL), originalData)
    }

    func testWidgetReloadPolicyRequiresChangedSharedState() {
        XCTAssertFalse(
            HoursWidgetReloadPolicy.shouldReload(
                calendarSnapshotChanged: false,
                appearancePreferenceMigrated: false
            )
        )
        XCTAssertTrue(
            HoursWidgetReloadPolicy.shouldReload(
                calendarSnapshotChanged: true,
                appearancePreferenceMigrated: false
            )
        )
        XCTAssertTrue(
            HoursWidgetReloadPolicy.shouldReload(
                calendarSnapshotChanged: false,
                appearancePreferenceMigrated: true
            )
        )
    }

    func testMissingSnapshotThrows() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = HoursLiturgicalCalendarSnapshotStore(
            fileURL: fileURL
        )

        XCTAssertThrowsError(try store.load())
    }

    func testUnavailableContainerThrows() {
        let store = HoursLiturgicalCalendarSnapshotStore(fileURL: nil)

        XCTAssertThrowsError(try store.load()) { error in
            guard case HoursLiturgicalCalendarSnapshotStoreError
                .appGroupContainerUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingSnapshotSchedulesRetry() {
        let now = Date(timeIntervalSince1970: 1_787_130_000)
        let retryDate = HoursLiturgicalCalendarRefreshSchedule.retryDate(
            for: nil,
            officeDay: LocalDay(year: 2026, month: 8, day: 19),
            now: now
        )

        XCTAssertEqual(
            retryDate,
            now.addingTimeInterval(
                HoursLiturgicalCalendarRefreshSchedule
                    .unavailableRetryInterval
            )
        )
    }

    func testSnapshotMissingOfficeDaySchedulesRetry() {
        let now = Date(timeIntervalSince1970: 1_787_130_000)
        let snapshot = makeSnapshot(
            on: LocalDay(year: 2026, month: 8, day: 18)
        )

        XCTAssertNotNil(
            HoursLiturgicalCalendarRefreshSchedule.retryDate(
                for: snapshot,
                officeDay: LocalDay(year: 2026, month: 8, day: 19),
                now: now
            )
        )
    }

    func testSnapshotWithOfficeDayDoesNotScheduleRetry() {
        let officeDay = LocalDay(year: 2026, month: 8, day: 19)
        let snapshot = makeSnapshot(on: officeDay)

        XCTAssertNil(
            HoursLiturgicalCalendarRefreshSchedule.retryDate(
                for: snapshot,
                officeDay: officeDay,
                now: Date(timeIntervalSince1970: 1_787_130_000)
            )
        )
    }

    private func makeSnapshot(
        on date: LocalDay
    ) -> HoursLiturgicalCalendarSnapshot {
        HoursLiturgicalCalendarSnapshot(
            days: [
                LiturgicalDay(
                    date: date,
                    observanceID: "test-day",
                    titleLatin: "Feria",
                    rank: .thirdClass,
                    season: "Post Pentecosten"
                )
            ]
        )
    }
}
