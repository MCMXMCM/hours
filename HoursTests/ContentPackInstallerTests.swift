import CryptoKit
import XCTest
@testable import HoursCore

final class ContentPackInstallerTests: XCTestCase {
    func testValidSignedSQLiteCorpusInstalls() throws {
        let source = try ContentDatabaseTestFixture.makeDatabase()
        let pack = try Data(contentsOf: source)
        let privateKey = Curve25519.Signing.PrivateKey()
        let hash = SHA256.hash(data: pack).map { String(format: "%02x", $0) }.joined()
        let unsigned = manifest(hash: hash, signature: "")
        let signature = try privateKey.signature(for: unsigned.signingPayload).base64EncodedString()
        let manifest = self.manifest(hash: hash, signature: signature)
        let destination = source.deletingLastPathComponent().appending(path: "installed.sqlite")

        try ContentPackInstaller().install(
            pack: pack,
            manifest: manifest,
            publicKey: privateKey.publicKey.rawRepresentation,
            currentAppVersion: "0.1.0",
            destination: destination
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNoThrow(
            try ContentDatabaseValidator.validate(
                databaseURL: destination,
                expectedManifest: manifest
            )
        )
    }

    func testMalformedDocumentRowFailsClosedBeforeInstallation() throws {
        let source = try ContentDatabaseTestFixture.makeDatabase()
        try ContentDatabaseTestFixture.mutate(
            source,
            sql: "UPDATE documents SET payload = x'7B' WHERE id = 'doc-vespers'"
        )
        let pack = try Data(contentsOf: source)
        let privateKey = Curve25519.Signing.PrivateKey()
        let hash = SHA256.hash(data: pack).map { String(format: "%02x", $0) }.joined()
        let unsigned = manifest(hash: hash, signature: "")
        let signature = try privateKey.signature(for: unsigned.signingPayload).base64EncodedString()
        let manifest = self.manifest(hash: hash, signature: signature)
        let destination = source.deletingLastPathComponent().appending(path: "installed.sqlite")

        XCTAssertThrowsError(
            try ContentPackInstaller().install(
                pack: pack,
                manifest: manifest,
                publicKey: privateKey.publicKey.rawRepresentation,
                currentAppVersion: "0.1.0",
                destination: destination
            )
        ) { error in
            guard case .invalidDatabase = error as? ContentPackError else {
                return XCTFail("Expected invalidDatabase, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testValidSignatureVerifiesButMalformedSQLiteNeverInstalls() throws {
        let pack = Data("read-only sqlite bytes".utf8)
        let privateKey = Curve25519.Signing.PrivateKey()
        let hash = SHA256.hash(data: pack).map { String(format: "%02x", $0) }.joined()
        let unsigned = manifest(hash: hash, signature: "")
        let signature = try privateKey.signature(for: unsigned.signingPayload).base64EncodedString()
        let manifest = self.manifest(hash: hash, signature: signature)
        let installer = ContentPackInstaller()

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "hours-pack-\(UUID().uuidString)", directoryHint: .isDirectory)
        let destination = directory.appending(path: "office.sqlite")
        XCTAssertNoThrow(
            try installer.verify(
                pack: pack,
                manifest: manifest,
                publicKey: privateKey.publicKey.rawRepresentation,
                currentAppVersion: "0.1.0"
            )
        )
        XCTAssertThrowsError(
            try installer.install(
                pack: pack,
                manifest: manifest,
                publicKey: privateKey.publicKey.rawRepresentation,
                currentAppVersion: "0.1.0",
                destination: destination
            )
        ) { error in
            guard let packError = error as? ContentPackError,
                  case .invalidDatabase = packError else {
                return XCTFail("Expected invalidDatabase, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        XCTAssertThrowsError(
            try installer.verify(
                pack: Data("tampered".utf8),
                manifest: manifest,
                publicKey: privateKey.publicKey.rawRepresentation,
                currentAppVersion: "0.1.0"
            )
        ) { error in
            XCTAssertEqual(error as? ContentPackError, .invalidHash)
        }
    }

    func testIncompatibleSchemaFailsBeforeInstallation() {
        let manifest = ContentManifest(
            schemaVersion: 99,
            corpusVersion: "future",
            minimumAppVersion: "0.1.0",
            createdAt: Date(),
            rubrics: "Rubrics 1960 - 1960",
            packSHA256: "",
            signature: "",
            sources: [],
            coverage: sampleCoverage
        )
        XCTAssertThrowsError(
            try ContentPackInstaller().verify(
                pack: Data(),
                manifest: manifest,
                publicKey: Data(),
                currentAppVersion: "0.1.0"
            )
        ) { error in
            XCTAssertEqual(error as? ContentPackError, .unsupportedSchema(99))
        }
    }

    func testFailedVerificationRetainsLastKnownGoodPack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "hours-rollback-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "office.sqlite")
        let knownGood = Data("known good".utf8)
        try knownGood.write(to: destination)

        let invalidManifest = manifest(hash: String(repeating: "0", count: 64), signature: "")
        XCTAssertThrowsError(
            try ContentPackInstaller().install(
                pack: Data("corrupt update".utf8),
                manifest: invalidManifest,
                publicKey: Data(),
                currentAppVersion: "0.1.0",
                destination: destination
            )
        )
        XCTAssertEqual(try Data(contentsOf: destination), knownGood)
    }

    private func manifest(hash: String, signature: String) -> ContentManifest {
        ContentManifest(
            schemaVersion: 1,
            corpusVersion: "test",
            minimumAppVersion: "0.1.0",
            createdAt: Date(timeIntervalSince1970: 0),
            rubrics: "Rubrics 1960 - 1960",
            packSHA256: hash,
            signature: signature,
            sources: [],
            coverage: sampleCoverage
        )
    }

    private var sampleCoverage: ContentCoverage {
        ContentCoverage(
            startDate: ContentDatabaseTestFixture.date,
            endDate: ContentDatabaseTestFixture.date,
            expectedOfficeCount: 8,
            generatedOfficeCount: 8,
            unresolvedScoreCount: 0,
            ambiguousScoreCount: 0,
            isSample: true
        )
    }
}
