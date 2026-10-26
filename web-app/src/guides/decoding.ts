// Reading a guide out of parsed JSON as `JSONDecoder` reads one into the
// `Decodable` types Swift synthesizes: a property that is not optional must
// be present and of its type, an optional one may be absent or null, and a
// key the type does not declare is passed over.

/** Why a guide could not be decoded, and where in it. */
export class GuideDecodingError extends Error {
  /** The place in the document, as `sections[2].blocks[0].kind`. */
  readonly codingPath: string;

  constructor(codingPath: string, reason: string) {
    super(`${codingPath.length > 0 ? codingPath : "The document"} ${reason}.`);
    this.name = "GuideDecodingError";
    this.codingPath = codingPath;
  }
}

export type Container = Readonly<Record<string, unknown>>;

/** Reads a value found at a place in the document, or throws. */
export type Read<Value> = (value: unknown, codingPath: string) => Value;

export function container(value: unknown, codingPath: string): Container {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new GuideDecodingError(codingPath, "is not an object");
  }
  return value as Container;
}

export function keyed(codingPath: string, key: string): string {
  return codingPath.length > 0 ? `${codingPath}.${key}` : key;
}

/** `decode(_:forKey:)`: the key must be present and its value not null. */
export function decode<Value>(
  from: Container,
  key: string,
  codingPath: string,
  read: Read<Value>,
): Value {
  const value = from[key];
  if (value === undefined || value === null) {
    throw new GuideDecodingError(keyed(codingPath, key), "is missing");
  }
  return read(value, keyed(codingPath, key));
}

/** `decodeIfPresent(_:forKey:)`: an absent key and a null are both `nil`. */
export function decodeIfPresent<Value>(
  from: Container,
  key: string,
  codingPath: string,
  read: Read<Value>,
): Value | null {
  const value = from[key];
  if (value === undefined || value === null) return null;
  return read(value, keyed(codingPath, key));
}

export const string: Read<string> = (value, codingPath) => {
  if (typeof value !== "string") {
    throw new GuideDecodingError(codingPath, "is not a string");
  }
  return value;
};

export const bool: Read<boolean> = (value, codingPath) => {
  if (typeof value !== "boolean") {
    throw new GuideDecodingError(codingPath, "is not true or false");
  }
  return value;
};

export const double: Read<number> = (value, codingPath) => {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new GuideDecodingError(codingPath, "is not a number");
  }
  return value;
};

export const int: Read<number> = (value, codingPath) => {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new GuideDecodingError(codingPath, "is not a whole number");
  }
  return value;
};

export function array<Element>(element: Read<Element>): Read<Element[]> {
  return (value, codingPath) => {
    if (!Array.isArray(value)) {
      throw new GuideDecodingError(codingPath, "is not a list");
    }
    return value.map((item, index) => element(item, `${codingPath}[${index}]`));
  };
}

/** A `String`-backed enum: a raw value that names no case cannot be decoded. */
export function rawValue<Case extends string>(
  cases: readonly Case[],
  name: string,
): Read<Case> {
  return (value, codingPath) => {
    const found = cases.find((candidate) => candidate === value);
    if (found === undefined) {
      throw new GuideDecodingError(codingPath, `is not ${name}`);
    }
    return found;
  };
}
