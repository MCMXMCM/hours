// The Rubrics guides as the app holds them, parallel to the declarations at
// the head of `HoursApp/RubricsGuideContent.swift`.
//
// On iOS a guide is written as Swift values. Here it is read from the file
// `scripts/export-rubrics-guides.mjs` writes from those values, so the prose
// is never written a second time: `RubricsEdition` is the enum's raw values,
// and what the enum computes for an edition (its year, subtitle,
// introduction, and topics) is that edition's `RubricsEditionGuide`. A method
// of a Swift struct stands in the namespace named for its plural:
// `topic.matches(_:)` is `RubricsTopics.matches`.

import { componentsSeparatedBy } from "@/reader/presentation/strings.ts";
import {
  folding,
  isWhitespace,
  splitOmittingEmpty,
} from "@/core/swiftString.ts";
import {
  GuideDecodingError,
  array,
  container,
  decode,
  int,
  rawValue,
  string,
  type Read,
} from "./decoding.ts";

export type RubricsEdition = "roman1960" | "roman1954";

// The reference order is independent of the edition selected for prayer.
const rubricsEditionAllCases: readonly RubricsEdition[] = [
  "roman1960",
  "roman1954",
];

export const RubricsEditions = {
  allCases: rubricsEditionAllCases,

  /** `RubricsEdition(rawValue:)`. */
  fromRawValue(rawValue: string): RubricsEdition | null {
    return (
      rubricsEditionAllCases.find((edition) => edition === rawValue) ?? null
    );
  },

  id(edition: RubricsEdition): RubricsEdition {
    return edition;
  },
};

/** What `RubricsEdition` computes for one edition. */
export interface RubricsEditionGuide {
  readonly id: RubricsEdition;
  readonly year: string;
  readonly subtitle: string;
  readonly introduction: string;
  readonly topics: readonly RubricsTopic[];
}

export interface RubricsTopic {
  readonly id: string;
  readonly title: string;
  readonly summary: string;
  readonly rules: readonly RubricsRule[];
}

export interface RubricsRule {
  readonly id: string;
  readonly title: string;
  readonly text: string;
  readonly citations: readonly RubricsCitation[];
}

export interface RubricsCitation {
  readonly label: string;
  readonly url: string;
}

const searchFolding = { caseInsensitive: true, diacriticInsensitive: true };

/**
 * `localizedStandardContains(_:)`, the search Foundation provides for what a
 * reader types: it disregards case and diacritics, and nothing else. A
 * ligature is not its letters ("sæculorum" does not contain "sae"), nor a
 * typographic mark its plain counterpart (an en dash is not a hyphen, nor a
 * curly apostrophe a straight one).
 *
 * Both strings are folded as Foundation folds them and then compared. While
 * this was ported, `RubricsTopic.matches` was compiled from the Swift as it
 * stands and asked 11,714 queries of each edition (every word of the guides
 * in several cases and without its accents, pieces of their text, words in
 * other orders and with other spaces between them, and characters of other
 * scripts); it and this answered alike every time. The two can part only
 * over characters the guides do not contain, such as a circled digit, which
 * Foundation finds to contain its digit.
 */
function localizedStandardContains(value: string, other: string): boolean {
  if (other.length === 0) return false;
  return folding(value, searchFolding).includes(folding(other, searchFolding));
}

export const RubricsTopics = {
  matches(topic: RubricsTopic, query: string): boolean {
    const words = splitOmittingEmpty(query, isWhitespace);
    const content = [
      topic.title,
      topic.summary,
      ...topic.rules.flatMap((rule) => [
        rule.title,
        rule.text,
        ...rule.citations.map((citation) => citation.label),
      ]),
    ].join(" ");
    return words.every((word) => localizedStandardContains(content, word));
  },
};

export const RubricsRules = {
  /** A rule's paragraphs, as the reader sets them one beneath another. */
  paragraphs(rule: RubricsRule): string[] {
    // Preserve paragraph boundaries for reading and VoiceOver.
    return componentsSeparatedBy(rule.text, "\n\n");
  },
};

export const RubricsCitations = {
  id(citation: RubricsCitation): string {
    return citation.label;
  },
};

// MARK: Decoding

/** The format `scripts/export-rubrics-guides.swift` writes. */
export const rubricsGuideSchema = 1;

/** One edition's guide, as it is exported. */
export interface RubricsGuideFile {
  readonly schema: number;
  /** Names the Swift sources the file was made from. */
  readonly signature: string;
  /** The edition's place among `RubricsEdition.allCases`. */
  readonly order: number;
  readonly edition: RubricsEditionGuide;
}

const citation: Read<RubricsCitation> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    label: decode(from, "label", codingPath, string),
    url: decode(from, "url", codingPath, string),
  };
};

const rule: Read<RubricsRule> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(from, "id", codingPath, string),
    title: decode(from, "title", codingPath, string),
    text: decode(from, "text", codingPath, string),
    citations: decode(from, "citations", codingPath, array(citation)),
  };
};

const topic: Read<RubricsTopic> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(from, "id", codingPath, string),
    title: decode(from, "title", codingPath, string),
    summary: decode(from, "summary", codingPath, string),
    rules: decode(from, "rules", codingPath, array(rule)),
  };
};

const editionGuide: Read<RubricsEditionGuide> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(
      from,
      "id",
      codingPath,
      rawValue(rubricsEditionAllCases, "an edition of the Rubrics guide"),
    ),
    year: decode(from, "year", codingPath, string),
    subtitle: decode(from, "subtitle", codingPath, string),
    introduction: decode(from, "introduction", codingPath, string),
    topics: decode(from, "topics", codingPath, array(topic)),
  };
};

export const RubricsGuideFiles = {
  /** The file that holds an edition's guide, beside the others. */
  name(edition: RubricsEdition): string {
    return `rubrics-${edition}.json`;
  },

  /**
   * Reads an exported guide out of parsed JSON. Throws a `GuideDecodingError`
   * naming what could not be read.
   */
  decode(json: unknown): RubricsGuideFile {
    const from = container(json, "");
    return {
      schema: decode(from, "schema", "", int),
      signature: decode(from, "signature", "", string),
      order: decode(from, "order", "", int),
      edition: decode(from, "edition", "", editionGuide),
    };
  },

  /**
   * The guides in the order of `RubricsEdition.allCases`, which each file
   * records. Throws if the files are not one for each edition.
   */
  editions(files: readonly RubricsGuideFile[]): RubricsEditionGuide[] {
    const ordered = [...files].sort((lhs, rhs) => lhs.order - rhs.order);
    ordered.forEach((file, index) => {
      if (file.order !== index) {
        throw new GuideDecodingError(
          `${RubricsGuideFiles.name(file.edition.id)}.order`,
          "is not its place among the editions",
        );
      }
    });
    return ordered.map((file) => file.edition);
  },
};
