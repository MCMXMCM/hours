import Foundation
@testable import Hours
@testable import HoursCore
import XCTest

@MainActor
final class OfficeTraditionTests: XCTestCase {
    func testReleaseOffersOnlyRomanEditionsAndRetiredPreferenceCannotRestoreItsReader() throws {
        XCTAssertEqual(OfficeTradition.allCases, [.roman1954, .roman1960])
        XCTAssertNil(OfficeTradition(rubrics: "Monastic - 1963"))
        let suite = "OfficeTraditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("benedictine1963", forKey: AppModel.officeTraditionKey)
        defaults.set("benedictine1963", forKey: AppModel.readerTraditionKey)
        defaults.set(true, forKey: AppModel.readerIsPresentedKey)
        defaults.set("2026-09-10", forKey: AppModel.readerDayKey)
        defaults.set("compline", forKey: AppModel.readerHourKey)
        let model = AppModel(userDefaults: defaults)
        XCTAssertEqual(model.officeTradition, .roman1960)
        XCTAssertFalse(model.isReaderSessionActive)
    }

    func testBothRomanCorporaRemainIsolatedWhileSwitchingAndRestoring() async throws {
        var urls: [OfficeTradition: URL] = [:]
        for tradition in OfficeTradition.allCases {
            urls[tradition] = try ContentDatabaseTestFixture.makeDatabase(
                tradition: tradition, sourceOrdered: tradition != .roman1960)
        }
        defer { for url in urls.values { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
        let suite = "OfficeTraditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let romanURL = try XCTUnwrap(urls[.roman1960])
        let store = HoursLiturgicalCalendarSnapshotStore(fileURL: romanURL.deletingLastPathComponent().appendingPathComponent("widget.json"))
        let corpusURLs = urls
        let model = AppModel(repository: try SQLiteContentRepository(databaseURL: romanURL), userDefaults: defaults,
            calendarSnapshotStore: store, repositoryLoader: { tradition in
                try SQLiteContentRepository(databaseURL: corpusURLs[tradition]!, expectedTradition: tradition)
            })
        await model.selectOffice(on: ContentDatabaseTestFixture.date, hour: .vespers)
        for tradition in [OfficeTradition.roman1954, .roman1960, .roman1954] {
            let changed = await model.changeOfficeTradition(to: tradition)
            XCTAssertTrue(changed)
            XCTAssertEqual(model.officeTradition, tradition)
            XCTAssertEqual(model.office?.date, ContentDatabaseTestFixture.date)
            XCTAssertEqual(model.office?.hour, .vespers)
            XCTAssertEqual(AppModel(userDefaults: defaults).officeTradition, tradition)
            XCTAssertEqual(try store.load(expectedTradition: tradition).tradition, tradition)
            for other in OfficeTradition.allCases where other != tradition {
                XCTAssertThrowsError(try SQLiteContentRepository(databaseURL: corpusURLs[tradition]!, expectedTradition: other))
                XCTAssertThrowsError(try ContentDatabaseValidator.validate(databaseURL: corpusURLs[tradition]!, expectedTradition: other))
                XCTAssertThrowsError(try store.load(expectedTradition: other))
            }
        }
    }

    func testHistoricalRankSurvivesWidgetSnapshotAndHeaderWithoutModernReclassification() throws {
        let day = LiturgicalDay(date: ContentDatabaseTestFixture.date, observanceID: "octave",
            titleLatin: "In Octava Epiphaniæ", sourceRank: "Duplex majus", season: "")
        XCTAssertNil(day.rank)
        XCTAssertEqual(HomeHeaderPresentation(day: day, office: nil).rankDisplayName, "Duplex majus")
        let snapshot = HoursLiturgicalCalendarSnapshot(days: [day], tradition: .roman1954)
        let decoded = try JSONDecoder().decode(HoursLiturgicalCalendarSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.days.first?.rankDisplayName, "Duplex majus")
        XCTAssertNil(decoded.days.first?.rank)
    }

    func testRoman1954SourceDatabaseValidatesAndRejectsRomanExpectation() async throws {
        let url = try ContentDatabaseTestFixture.makeDatabase(tradition: .roman1954, sourceOrdered: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNoThrow(try ContentDatabaseValidator.validate(databaseURL: url, expectedTradition: .roman1954))
        XCTAssertThrowsError(try ContentDatabaseValidator.validate(databaseURL: url, expectedTradition: .roman1960))
        XCTAssertThrowsError(try SQLiteContentRepository(databaseURL: url, expectedTradition: .roman1960))
        let repository = try SQLiteContentRepository(databaseURL: url, expectedTradition: .roman1954)
        let office = try await repository.office(on: ContentDatabaseTestFixture.date, hour: .compline)
        XCTAssertEqual(office.format, .sourceOrdered)
        XCTAssertTrue(office.id.hasPrefix("roman1954:"))
    }

    func testSourceOrderedReaderRetainsRepeatedAntiphonsAndExactText() {
        let sections = [
            OfficeSection(id: "a", kind: .antiphon, title: "Psalmi", latin: "Ant. Allelúia.", english: "Ant. Alleluia."),
            OfficeSection(id: "p", kind: .psalm, title: "", latin: "Psalmus 4\nCum invocárem.", english: "Psalm 4\nWhen I called."),
            OfficeSection(id: "b", kind: .antiphon, title: "", latin: "Ant. Allelúia.", english: "Ant. Alleluia."),
            OfficeSection(id: "c", kind: .conclusion, title: "Conclusio", latin: "Benedícat et custódiat nos.")
        ]
        let rendered = OfficeReaderSectionBuilder.displaySections(from: sections, format: .sourceOrdered)
        XCTAssertEqual(rendered.map(\.latin), sections.map(\.latin))
        XCTAssertEqual(rendered.map(\.english), sections.map(\.english))
        XCTAssertEqual(rendered.map(\.chant), sections.map(\.chant))
        XCTAssertEqual(rendered.map(\.title), ["", "", "", "Conclusio"])
        XCTAssertEqual(sections[0].title, "Psalmi", "Stored source remains intact")
        XCTAssertEqual(rendered.map(\.id), ["a", "p", "b", "c"])
    }

    func testWidgetTraditionIsPartOfSnapshotIdentityAndLegacyDefaultsToRoman() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HoursLiturgicalCalendarSnapshotStore(fileURL: url)
        let day = LiturgicalDay(date: ContentDatabaseTestFixture.date, observanceID: "test", titleLatin: "Feria", season: "Test")
        XCTAssertTrue(try store.saveIfChanged(days: [day]))
        XCTAssertTrue(try store.saveIfChanged(days: [day], tradition: .roman1954))
        XCTAssertFalse(try store.saveIfChanged(days: [day], tradition: .roman1954))
        XCTAssertThrowsError(try store.load(expectedTradition: .roman1960))
        XCTAssertEqual(try store.load(expectedTradition: .roman1954).tradition, .roman1954)
        let legacy = try JSONDecoder().decode(HoursLiturgicalCalendarSnapshot.self, from: Data("{\"days\":[]}".utf8))
        XCTAssertEqual(legacy.tradition, .roman1960)
    }

    func testSwitchCommitsCorpusPreferenceReaderAndWidgetTogether() async throws {
        let romanURL = try ContentDatabaseTestFixture.makeDatabase()
        let sourceURL = try ContentDatabaseTestFixture.makeDatabase(tradition: .roman1954, sourceOrdered: true)
        defer {
            try? FileManager.default.removeItem(at: romanURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }
        let suite = "OfficeTraditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HoursLiturgicalCalendarSnapshotStore(fileURL: romanURL.deletingLastPathComponent().appendingPathComponent("widget.json"))
        let model = AppModel(repository: try SQLiteContentRepository(databaseURL: romanURL), userDefaults: defaults,
            calendarSnapshotStore: store, repositoryLoader: { tradition in
                try SQLiteContentRepository(databaseURL: tradition == .roman1960 ? romanURL : sourceURL, expectedTradition: tradition)
            })
        await model.selectOffice(on: ContentDatabaseTestFixture.date, hour: .compline)
        model.beginReaderSession(for: try XCTUnwrap(model.office))
        defaults.set("stale-corpus-hit", forKey: AppTourPersistence.recentHitsKey)

        let changed = await model.changeOfficeTradition(to: .roman1954)
        XCTAssertTrue(changed)
        XCTAssertEqual(model.officeTradition, .roman1954)
        XCTAssertEqual(model.office?.format, .sourceOrdered)
        XCTAssertEqual(model.selectedHour, .compline)
        XCTAssertFalse(model.isReaderSessionActive)
        XCTAssertNil(defaults.object(forKey: AppTourPersistence.recentHitsKey))
        XCTAssertEqual(try store.load().tradition, .roman1954)
        XCTAssertEqual(AppModel(userDefaults: defaults).officeTradition, .roman1954)

        let restored = await model.changeOfficeTradition(to: .roman1960)
        XCTAssertTrue(restored)
        XCTAssertEqual(model.office?.format, .authoritativeOrdered)
        XCTAssertFalse(try XCTUnwrap(model.office).id.hasPrefix("roman1954:"))
        XCTAssertEqual(try store.load().tradition, .roman1960)
    }

    func testFailedSwitchLeavesOfficeReaderAndPreferenceIntact() async throws {
        let url = try ContentDatabaseTestFixture.makeDatabase()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let suite = "OfficeTraditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(repository: try SQLiteContentRepository(databaseURL: url), userDefaults: defaults,
            repositoryLoader: { _ in throw ContentRepositoryError.databaseUnavailable("Missing Roman 1954 pack") })
        await model.selectOffice(on: ContentDatabaseTestFixture.date, hour: .compline)
        let prior = try XCTUnwrap(model.office)
        model.beginReaderSession(for: prior)
        let changed = await model.changeOfficeTradition(to: .roman1954)
        XCTAssertFalse(changed)
        XCTAssertEqual(model.office, prior)
        XCTAssertEqual(model.officeTradition, .roman1960)
        XCTAssertTrue(model.isReaderSessionActive)
        XCTAssertNotNil(model.traditionErrorMessage)
        XCTAssertNil(defaults.object(forKey: AppModel.officeTraditionKey))
        XCTAssertFalse(model.isChangingTradition)
    }

    func testSupersedingSelectionCannotCommitAStaleTraditionChange() async throws {
        let romanURL = try ContentDatabaseTestFixture.makeDatabase()
        let sourceURL = try ContentDatabaseTestFixture.makeDatabase(tradition: .roman1954, sourceOrdered: true)
        defer {
            try? FileManager.default.removeItem(at: romanURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }
        let suite = "OfficeTraditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = SuspendedTraditionRepository(underlying: try SQLiteContentRepository(databaseURL: sourceURL))
        let model = AppModel(repository: try SQLiteContentRepository(databaseURL: romanURL), userDefaults: defaults,
            repositoryLoader: { _ in pending })
        await model.selectOffice(on: ContentDatabaseTestFixture.date, hour: .compline)
        let change = Task { await model.changeOfficeTradition(to: .roman1954) }
        await pending.waitUntilRequested()
        await model.select(hour: .prime)
        await pending.resume()
        let changed = await change.value
        XCTAssertFalse(changed)
        XCTAssertEqual(model.officeTradition, .roman1960)
        XCTAssertEqual(model.office?.hour, .prime)
        XCTAssertEqual(model.office?.format, .authoritativeOrdered)
        XCTAssertNil(defaults.object(forKey: AppModel.officeTraditionKey))
    }

    func testReaderRestorationIsBoundToItsTradition() throws {
        let suite = "OfficeTraditionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(OfficeTradition.roman1954.rawValue, forKey: AppModel.officeTraditionKey)
        let model = AppModel(userDefaults: defaults)
        let office = OfficeDocument(id: "roman1954:test", date: ContentDatabaseTestFixture.date,
            hour: .matins, titleLatin: "Ad Matutinum", contextLabel: "Test", sections: [])
        model.beginReaderSession(for: office)
        XCTAssertTrue(AppModel(userDefaults: defaults).shouldRestoreReader(for: office))
        defaults.set(OfficeTradition.roman1960.rawValue, forKey: AppModel.officeTraditionKey)
        XCTAssertFalse(AppModel(userDefaults: defaults).isReaderSessionActive)
    }
}

private actor SuspendedTraditionRepository: ContentRepository {
    let underlying: any ContentRepository
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    init(underlying: any ContentRepository) { self.underlying = underlying }
    func availableDays() async throws -> [LiturgicalDay] { try await underlying.availableDays() }
    func day(on date: LocalDay) async throws -> LiturgicalDay { try await underlying.day(on: date) }
    func office(on date: LocalDay, hour: OfficeHour) async throws -> OfficeDocument {
        await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
        return try await underlying.office(on: date, hour: hour)
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { pending?.resume(); pending = nil }
}
