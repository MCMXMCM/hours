// Fetches the two guides from beside the app and reads them.
//
// The Guide to Chant is the file the iOS app bundles, copied as it stands.
// The Rubrics guides are written from the Swift that holds them (see
// `scripts/export-rubrics-guides.mjs`). Neither is altered here, save that
// every string is brought to NFC as it is loaded, as the Office is: the
// cantor guide and the search compare text literally, which agrees with
// Swift's comparison for text in that form.

import { normalized } from "@/core/swiftString.ts";
import { retryingFetch, type Fetcher } from "@/data/retryingFetch.ts";
import {
  ChantGuideDocuments,
  type ChantGuideDocument,
} from "./chantGuideDocument.ts";
import { GuideDecodingError } from "./decoding.ts";
import {
  RubricsEditions,
  RubricsGuideFiles,
  rubricsGuideSchema,
  type RubricsEditionGuide,
} from "./rubricsGuide.ts";

export type GuideFailure =
  /** The guide could not be reached. */
  | "offline"
  /** The guide is not where the app looks for it. */
  | "unavailable"
  /** The guide is newer than this copy of the app understands. */
  | "outdated"
  /** The guide was fetched, and is not in the form the app reads. */
  | "unreadable";

export class GuideError extends Error {
  readonly failure: GuideFailure;

  constructor(failure: GuideFailure, message: string) {
    super(message);
    this.name = "GuideError";
    this.failure = failure;
  }
}

export type { Fetcher } from "@/data/retryingFetch.ts";

/** Where the guides are served, beside the app. */
export const guidesBaseURL = `${import.meta.env.BASE_URL}guides/`;

/** The Guide to Chant, under the name the iOS app bundles it by. */
export const chantGuideFile = "chant-guide.json";

/** Every string a parsed document holds, in the corpus's canonical form. */
export function normalizedStrings<Value>(value: Value): Value {
  if (typeof value === "string") return normalized(value) as Value;
  if (Array.isArray(value)) return value.map(normalizedStrings) as Value;
  if (typeof value === "object" && value !== null) {
    const result: Record<string, unknown> = {};
    for (const [key, member] of Object.entries(value)) {
      result[key] = normalizedStrings(member);
    }
    return result as Value;
  }
  return value;
}

/** What a reader is told when a guide cannot be shown. */
export function describeGuideError(error: unknown): string {
  if (error instanceof GuideError) {
    switch (error.failure) {
      case "offline":
        return "The guide could not be loaded. Check the connection and try again.";
      case "unavailable":
        return "This guide is not available.";
      case "outdated":
        return "This copy of Hours is out of date. Reload the page to update it.";
      case "unreadable":
        return `The guide could not be read. ${error.message}`;
    }
  }
  return error instanceof Error ? error.message : String(error);
}

export class GuideLibrary {
  private readonly base: string;
  private readonly fetcher: Fetcher;
  private chantGuideRequest: Promise<ChantGuideDocument> | null = null;
  private rubricsGuidesRequest: Promise<RubricsEditionGuide[]> | null = null;
  private chantGuideLoaded: ChantGuideDocument | null = null;
  private rubricsGuidesLoaded: RubricsEditionGuide[] | null = null;

  constructor(base = guidesBaseURL, fetcher: Fetcher = retryingFetch) {
    this.base = base.endsWith("/") ? base : `${base}/`;
    this.fetcher = fetcher;
  }

  /** A file of the guides, parsed, with its strings in NFC. */
  private async read(file: string): Promise<unknown> {
    let response: Response;
    try {
      response = await this.fetcher(this.base + file);
    } catch {
      throw new GuideError("offline", `${file} could not be reached.`);
    }
    if (response.status === 404 || response.status === 403) {
      throw new GuideError("unavailable", `There is no ${file}.`);
    }
    if (!response.ok) {
      throw new GuideError(
        "offline",
        `The server answered ${response.status} for ${file}.`,
      );
    }
    let text: string;
    try {
      text = await response.text();
    } catch {
      throw new GuideError("offline", `${file} did not arrive whole.`);
    }
    try {
      return normalizedStrings(JSON.parse(text) as unknown);
    } catch {
      // A server that answers every unknown path with the app itself has no
      // such file; anything else that is not JSON is a damaged one.
      const type = response.headers.get("content-type") ?? "";
      if (type.includes("text/html")) {
        throw new GuideError("unavailable", `There is no ${file}.`);
      }
      throw new GuideError("unreadable", `${file} is not JSON.`);
    }
  }

  private static decoding<Value>(decode: () => Value): Value {
    try {
      return decode();
    } catch (error) {
      if (error instanceof GuideDecodingError) {
        throw new GuideError("unreadable", error.message);
      }
      throw error;
    }
  }

  /** The Guide to Chant, if it has already been read. */
  get loadedChantGuide(): ChantGuideDocument | null {
    return this.chantGuideLoaded;
  }

  /** The Rubrics guides, if they have already been read. */
  get loadedRubricsGuides(): RubricsEditionGuide[] | null {
    return this.rubricsGuidesLoaded;
  }

  /** The Guide to Chant. A failure is not remembered; the next reader tries again. */
  chantGuide(): Promise<ChantGuideDocument> {
    this.chantGuideRequest ??= this.read(chantGuideFile)
      .then((json) => {
        const document = GuideLibrary.decoding(() =>
          ChantGuideDocuments.decode(json),
        );
        this.chantGuideLoaded = document;
        return document;
      })
      .catch((error: unknown) => {
        this.chantGuideRequest = null;
        throw error;
      });
    return this.chantGuideRequest;
  }

  /**
   * The Rubrics guide of every edition, in the order the reference lists
   * them. A failure is not remembered; the next reader tries again.
   */
  rubricsGuides(): Promise<RubricsEditionGuide[]> {
    this.rubricsGuidesRequest ??= Promise.all(
      RubricsEditions.allCases.map(async (edition) => {
        const name = RubricsGuideFiles.name(edition);
        const json = await this.read(name);
        const schema = (json as { schema?: unknown } | null)?.schema;
        if (typeof schema === "number" && schema > rubricsGuideSchema) {
          throw new GuideError(
            "outdated",
            `${name} is newer than this copy of Hours.`,
          );
        }
        const file = GuideLibrary.decoding(() =>
          RubricsGuideFiles.decode(json),
        );
        if (file.edition.id !== edition) {
          throw new GuideError(
            "unreadable",
            `${name} holds the guide of another edition.`,
          );
        }
        return file;
      }),
    )
      .then((files) => {
        const editions = GuideLibrary.decoding(() =>
          RubricsGuideFiles.editions(files),
        );
        this.rubricsGuidesLoaded = editions;
        return editions;
      })
      .catch((error: unknown) => {
        this.rubricsGuidesRequest = null;
        throw error;
      });
    return this.rubricsGuidesRequest;
  }
}

/** The guides as the app's screens reach them. */
export const guideLibrary = new GuideLibrary();
