import XCTest
@testable import HoursCore

final class ContentRepositoryIntegrityTests: XCTestCase {
    func testMetadataOnlyUnavailableOfficeIsReadableAndValid() async throws {
        let database = try ContentDatabaseTestFixture.makeDatabase(
            unavailableHours: [.lauds]
        )
        XCTAssertNoThrow(
            try ContentDatabaseValidator.validate(
                databaseURL: database,
                validatesNotation: false
            )
        )

        let repository = try SQLiteContentRepository(databaseURL: database)
        let office = try await repository.office(
            on: ContentDatabaseTestFixture.date,
            hour: .lauds
        )
        XCTAssertEqual(office.format, .contentUnavailable)
        XCTAssertNotNil(office.observance)
        XCTAssertNil(office.visibleContentDigest)
        XCTAssertTrue(office.sections.isEmpty)
        XCTAssertTrue(office.playableScores.isEmpty)
    }

    func testEveningContextIsAvailableThroughCompline() async throws {
        let database = try ContentDatabaseTestFixture.makeDatabase()
        let repository = try SQLiteContentRepository(databaseURL: database)

        let vespers = try await repository.office(
            on: ContentDatabaseTestFixture.date,
            hour: .vespers
        )
        let compline = try await repository.office(
            on: ContentDatabaseTestFixture.date,
            hour: .compline
        )

        XCTAssertEqual(vespers.observance?.eveningContext, .secondVespers)
        XCTAssertEqual(compline.observance?.eveningContext, .secondVespers)
    }

    func testValidatorRejectsUnresolvedVespersContext() throws {
        let database = try ContentDatabaseTestFixture.makeDatabase()
        try ContentDatabaseTestFixture.mutate(
            database,
            sql: """
            UPDATE documents
            SET payload = replace(
                CAST(payload AS TEXT),
                '"eveningContext":"secondVespers"',
                '"eveningContext":null'
            )
            WHERE id = 'doc-vespers';
            """
        )

        XCTAssertThrowsError(
            try ContentDatabaseValidator.validate(
                databaseURL: database,
                validatesNotation: false
            )
        )
    }

    func testMalformedScoreRowDoesNotReturnPartialOffice() async throws {
        let database = try ContentDatabaseTestFixture.makeDatabase()
        try ContentDatabaseTestFixture.mutate(
            database,
            sql: """
            INSERT INTO scores(id, payload) VALUES ('broken-score', x'7B');
            INSERT INTO section_scores(document_id, section_id, score_id)
            VALUES ('doc-vespers', 'section-vespers', 'broken-score');
            """
        )
        let repository = try SQLiteContentRepository(databaseURL: database)

        do {
            _ = try await repository.office(
                on: ContentDatabaseTestFixture.date,
                hour: .vespers
            )
            XCTFail("A malformed linked score must fail the complete office read.")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDigestMismatchDoesNotReturnTamperedAuthoritativeOffice() async throws {
        let database = try ContentDatabaseTestFixture.makeDatabase()
        try ContentDatabaseTestFixture.mutate(
            database,
            sql: """
            UPDATE documents
            SET payload = replace(
                CAST(payload AS TEXT),
                'Deus, qui per immaculátam Vírginis Conceptiónem.',
                'Textus corruptus.'
            )
            WHERE id = 'doc-lauds';
            """
        )
        let repository = try SQLiteContentRepository(databaseURL: database)

        do {
            _ = try await repository.office(
                on: ContentDatabaseTestFixture.date,
                hour: .lauds
            )
            XCTFail("A digest mismatch must fail the complete office read.")
        } catch let error as ContentRepositoryError {
            guard case .invalidContent = error else {
                return XCTFail("Expected invalidContent, got \(error)")
            }
        }
    }
}
