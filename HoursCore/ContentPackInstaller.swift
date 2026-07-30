import CryptoKit
import Foundation

public enum ContentPackError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case incompatibleApp(required: String, current: String)
    case invalidHash
    case invalidPublicKey
    case invalidSignature
    case invalidDatabase(String)
    case missingPackURL

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            "Content schema \(schema) is not supported."
        case .incompatibleApp(let required, let current):
            "This content pack requires Hours \(required) or later; this app is \(current)."
        case .invalidHash:
            "The downloaded content pack did not match its manifest."
        case .invalidPublicKey:
            "The content signing key is invalid."
        case .invalidSignature:
            "The content pack signature is invalid."
        case .invalidDatabase(let detail):
            "The downloaded content pack is not a valid office corpus. \(detail)"
        case .missingPackURL:
            "The content manifest does not contain a pack URL."
        }
    }
}

public struct ContentPackInstaller: Sendable {
    public static let supportedSchemaVersion = 1

    public init() {}

    public func verify(
        pack: Data,
        manifest: ContentManifest,
        publicKey: Data,
        currentAppVersion: String
    ) throws {
        guard manifest.schemaVersion == Self.supportedSchemaVersion else {
            throw ContentPackError.unsupportedSchema(manifest.schemaVersion)
        }
        guard SemanticVersion(currentAppVersion) >= SemanticVersion(manifest.minimumAppVersion) else {
            throw ContentPackError.incompatibleApp(
                required: manifest.minimumAppVersion,
                current: currentAppVersion
            )
        }

        let digest = SHA256.hash(data: pack).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(manifest.packSHA256) == .orderedSame else {
            throw ContentPackError.invalidHash
        }

        guard let signature = Data(base64Encoded: manifest.signature) else {
            throw ContentPackError.invalidSignature
        }
        let key: Curve25519.Signing.PublicKey
        do {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw ContentPackError.invalidPublicKey
        }
        guard key.isValidSignature(signature, for: manifest.signingPayload) else {
            throw ContentPackError.invalidSignature
        }
    }

    public func install(
        pack: Data,
        manifest: ContentManifest,
        publicKey: Data,
        currentAppVersion: String,
        destination: URL,
        fileManager: FileManager = .default
    ) throws {
        try verify(
            pack: pack,
            manifest: manifest,
            publicKey: publicKey,
            currentAppVersion: currentAppVersion
        )

        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appending(
            path: ".\(destination.lastPathComponent).\(UUID().uuidString).staged"
        )
        try pack.write(to: staged, options: [.atomic, .completeFileProtection])
        do {
            do {
                try ContentDatabaseValidator.validate(
                    databaseURL: staged,
                    expectedManifest: manifest
                )
            } catch {
                throw ContentPackError.invalidDatabase(error.localizedDescription)
            }
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }
}

private struct SemanticVersion: Comparable {
    private let components: [Int]

    init(_ value: String) {
        components = value
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
