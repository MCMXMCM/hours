import XCTest
@testable import HoursCore

final class ContentPayloadCodecTests: XCTestCase {
    func testCompressedPayloadRoundTripsAndLegacyJSONPassesThrough() throws {
        let payload = Data(
            String(repeating: #"{"latin":"Kyrie eléison"}"#, count: 200).utf8
        )
        let compressed = try ContentPayloadCodec.encodeForTesting(payload)

        XCTAssertEqual(try ContentPayloadCodec.decode(compressed), payload)
        XCTAssertEqual(try ContentPayloadCodec.decode(payload), payload)
    }

    func testDecodesNodeDeflateWireFormat() throws {
        // NCP1 + big-endian decoded length 7 + Node deflateRawSync('{"x":1}').
        let payload = Data([
            0x4e, 0x43, 0x50, 0x31, 0x00, 0x00, 0x00, 0x07,
            0xab, 0x56, 0xaa, 0x50, 0xb2, 0x32, 0xac, 0x05, 0x00
        ])

        XCTAssertEqual(
            try ContentPayloadCodec.decode(payload),
            Data(#"{"x":1}"#.utf8)
        )
    }

    func testCompressedPayloadRejectsIncorrectDecodedLength() throws {
        var compressed = try ContentPayloadCodec.encodeForTesting(
            Data(String(repeating: "Alleluia", count: 100).utf8)
        )
        compressed[7] ^= 1

        XCTAssertThrowsError(try ContentPayloadCodec.decode(compressed))
    }
}
