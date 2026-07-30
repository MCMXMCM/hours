import { deflateRawSync, inflateRawSync } from "node:zlib";

const magic = Buffer.from("NCP1", "ascii");
const headerBytes = 8;

export function encodeContentPayload(text: string): Uint8Array {
  const raw = Buffer.from(text, "utf8");
  // Foundation's NSData.CompressionAlgorithm.zlib interoperates with a bare
  // RFC 1951 DEFLATE stream (despite the API's zlib name).
  const compressed = deflateRawSync(raw, { level: 9 });
  if (compressed.length + headerBytes >= raw.length) return raw;
  const header = Buffer.allocUnsafe(headerBytes);
  magic.copy(header, 0);
  header.writeUInt32BE(raw.length, 4);
  return Buffer.concat([header, compressed]);
}

export function decodeContentPayload(value: string | Uint8Array): string {
  if (typeof value === "string") return value;
  const payload = Buffer.from(value);
  if (
    payload.length < headerBytes
    || !payload.subarray(0, magic.length).equals(magic)
  ) {
    return payload.toString("utf8");
  }
  const expectedBytes = payload.readUInt32BE(4);
  const decoded = inflateRawSync(payload.subarray(headerBytes));
  if (decoded.length !== expectedBytes) {
    throw new Error(
      `Compressed content payload decoded to ${decoded.length} bytes; `
      + `expected ${expectedBytes}`
    );
  }
  return decoded.toString("utf8");
}
