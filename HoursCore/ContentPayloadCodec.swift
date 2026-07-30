import Foundation

enum ContentPayloadCodec {
    private static let magic = Data("NCP1".utf8)
    private static let headerByteCount = 8

    static func decode(_ payload: Data) throws -> Data {
        guard payload.count >= headerByteCount,
              payload.prefix(magic.count) == magic else {
            return payload
        }
        let expectedByteCount = payload[4..<8].reduce(0) {
            ($0 << 8) | Int($1)
        }
        do {
            let decoded = try (payload.dropFirst(headerByteCount) as NSData)
                .decompressed(using: .zlib) as Data
            guard decoded.count == expectedByteCount else {
                throw ContentRepositoryError.invalidContent(
                    "Compressed payload decoded to \(decoded.count) bytes; "
                        + "expected \(expectedByteCount)."
                )
            }
            return decoded
        } catch let error as ContentRepositoryError {
            throw error
        } catch {
            throw ContentRepositoryError.invalidContent(
                "A compressed content payload could not be decoded."
            )
        }
    }

    static func encodeForTesting(_ payload: Data) throws -> Data {
        let compressed = try (payload as NSData).compressed(using: .zlib) as Data
        var result = magic
        let count = UInt32(payload.count)
        result.append(UInt8((count >> 24) & 0xff))
        result.append(UInt8((count >> 16) & 0xff))
        result.append(UInt8((count >> 8) & 0xff))
        result.append(UInt8(count & 0xff))
        result.append(compressed)
        return result
    }
}
