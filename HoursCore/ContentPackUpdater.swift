import Foundation

public enum ContentUpdateError: LocalizedError, Equatable {
    case invalidHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPStatus(let status):
            "The content server returned HTTP \(status)."
        }
    }
}

public actor ContentPackUpdater {
    private let session: URLSession
    private let installer: ContentPackInstaller

    public init(
        session: URLSession = .shared,
        installer: ContentPackInstaller = ContentPackInstaller()
    ) {
        self.session = session
        self.installer = installer
    }

    @discardableResult
    public func installLatest(
        manifestURL: URL,
        publicKey: Data,
        currentAppVersion: String,
        destination: URL
    ) async throws -> ContentManifest {
        let (manifestData, manifestResponse) = try await session.data(from: manifestURL)
        try validate(response: manifestResponse)
        let manifest = try JSONDecoder.hoursContentDecoder.decode(
            ContentManifest.self,
            from: manifestData
        )
        guard let packURL = manifest.packURL else {
            throw ContentPackError.missingPackURL
        }
        let (pack, packResponse) = try await session.data(from: packURL)
        try validate(response: packResponse)

        // Verification happens before any destination mutation. The installer stages
        // the pack beside the current corpus and replaces it atomically.
        try installer.install(
            pack: pack,
            manifest: manifest,
            publicKey: publicKey,
            currentAppVersion: currentAppVersion,
            destination: destination
        )
        return manifest
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(response.statusCode) else {
            throw ContentUpdateError.invalidHTTPStatus(response.statusCode)
        }
    }
}
