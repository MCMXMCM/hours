// The parts of the Mass as search finds them, parallel to
// `HoursCore/MassPartSearch.swift`: every text of an edition's Missal,
// ordinary and proper, with the chant it is sung to and the Masses that say
// it, searched in memory as the native app searches it. A text the Missal
// keeps under several titles or rubrics is one result; each part of the
// Ordinary the Kyriale sets is one result whatever its lines' marks.

import type { OfficeSectionKind } from "@/core/models.ts";
import * as SwiftString from "@/core/swiftString.ts";
import {
  MassPartSearch,
  type LiturgicalSearchHit,
  type LiturgicalSearchLanguage,
  type MassPartFilter,
  type OrdinaryPart,
} from "./models.ts";
import {
  searchNormalized,
  searchPhraseRank,
  searchSnippet,
} from "./repository.ts";
import * as Strings from "./strings.ts";

/** A text of the Missal, as the search reads it (`MissalSearchText`). */
export interface MissalSearchText {
  readonly id: number;
  readonly kind: OfficeSectionKind;
  readonly title: string;
  readonly titleEnglish: string | null;
  readonly rubric: string | null;
  readonly rubricEnglish: string | null;
  readonly latin: string;
  readonly english: string | null;
  readonly ordinary: boolean;
}

/** One section of a Mass: its text and the score it is sung to. */
export interface MissalSection {
  readonly text: number;
  readonly score: number | null;
}

/** A part of the Mass that search finds (`MassPartEntry`). */
export interface MassPartEntry {
  readonly id: string;
  readonly kind: OfficeSectionKind;
  readonly ordinary: boolean;
  readonly part: OrdinaryPart | null;
  readonly title: string;
  readonly titleEnglish: string | null;
  readonly rubric: string | null;
  readonly rubricEnglish: string | null;
  readonly latin: string;
  readonly english: string | null;
  /** The words a sung part opens with; empty for a part that is not sung. */
  readonly incipit: string;
  readonly textIDs: readonly number[];
  /** The Missal's scores of its texts, by their identifiers in order. */
  readonly scoreIDs: readonly number[];
  readonly isSung: boolean;
  readonly latinWords: string;
  readonly englishWords: string;
  readonly length: number;
}

/** English names a part of the Ordinary is known by that its fields do not give. */
const englishAliases: Partial<Record<OrdinaryPart, readonly string[]>> = {
  credo: ["Nicene Creed"],
};

/** A letter or a digit, as `words` keeps them. */
const wordCharacters = /[\p{Alphabetic}\p{N}]+/gu;

/**
 * `MassPartIndex.words`: the words of the fields, normalized as the Office's
 * search normalizes them, each between spaces, so that a query's word with a
 * space before it is found at the beginning of a word.
 */
export function words(
  fields: readonly (string | null)[],
  latin: boolean,
): string {
  const normalized = Strings.canonical(
    searchNormalized(
      fields.filter((field): field is string => field !== null).join(" "),
      latin,
    ),
  );
  const found = normalized.match(wordCharacters) ?? [];
  return found.length === 0 ? "  " : ` ${found.join(" ")} `;
}

/**
 * `withoutMarks`: the words without the marks of a Mass's lines (℣., ℟.,
 * and the server's S., M. and P.), which tell its lines apart and not its
 * texts.
 */
export function withoutMarks(value: string): string {
  return value.replace(/ [smpvr](?= )/g, "");
}

/** `stableHash`: FNV-1a over the UTF-8 of the words, in hexadecimal. */
export function stableHash(value: string): string {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(value)) {
    hash ^= BigInt(byte);
    hash = (hash * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return hash.toString(16).padStart(16, "0");
}

/** `ordinaryPart(of:)`: the part of the Ordinary a text is, if it is one the Kyriale sets. */
export function ordinaryPart(
  text: MissalSearchText,
  latinWords: string,
): OrdinaryPart | null {
  switch (text.kind) {
    case "kyrie":
      return "kyrie";
    case "gloria":
      return "gloria";
    case "credo":
      return "credo";
    case "sanctus":
      return "sanctus";
    case "agnusDei":
      return latinWords.includes(" requiem ")
        ? "agnusDeiDefunctorum"
        : "agnusDei";
    case "dismissal": {
      const plain = withoutMarks(latinWords);
      if (plain.startsWith(" ite ")) return "ite";
      if (plain.startsWith(" benedicamus ")) return "benedicamus";
      if (plain.startsWith(" requiescant ")) return "requiescant";
      return null;
    }
    default:
      return null;
  }
}

/** `opening(of:)`: the words a sung part opens with, to the first mark of punctuation. */
export function opening(latin: string): string {
  const text = latin.replace(/^\s*(?:[℣℟]\.?|[SMPVR]\.)\s*/u, "");
  const end = text.search(/[,.:;!?\n]/);
  return SwiftString.trimmingWhitespaceAndNewlines(
    end < 0 ? text : text.slice(0, end),
  );
}

/** Every part of the Mass of an edition's Missal (`MassPartIndex`). */
export class MassPartIndex {
  readonly entries: readonly MassPartEntry[];
  private readonly entryIndices = new Map<string, number>();
  /** Each text's sections: the Mass that says it and the chant it is sung to there. */
  readonly uses = new Map<number, { mass: number; score: number | null }[]>();

  constructor(
    texts: readonly MissalSearchText[],
    sections: ReadonlyMap<number, readonly MissalSection[]>,
    kyrialeParts: ReadonlySet<OrdinaryPart>,
  ) {
    for (const mass of [...sections.keys()].sort(
      (left, right) => left - right,
    )) {
      for (const section of sections.get(mass) ?? []) {
        const list = this.uses.get(section.text);
        const use = { mass, score: section.score };
        if (list === undefined) this.uses.set(section.text, [use]);
        else list.push(use);
      }
    }
    const groups = new Map<
      string,
      { text: MissalSearchText; latinWords: string }[]
    >();
    for (const text of [...texts].sort((left, right) => left.id - right.id)) {
      if (
        SwiftString.trimmingWhitespaceAndNewlines(text.latin).length === 0 &&
        SwiftString.trimmingWhitespaceAndNewlines(text.english ?? "").length ===
          0
      ) {
        continue;
      }
      const latinWords = words([text.latin], true);
      const part = ordinaryPart(text, latinWords);
      const key =
        part !== null
          ? `ordinary:${part}`
          : `${text.kind}:${stableHash(withoutMarks(latinWords))}`;
      const group = groups.get(key);
      if (group === undefined) groups.set(key, [{ text, latinWords }]);
      else group.push({ text, latinWords });
    }
    const entries: MassPartEntry[] = [];
    for (const [key, group] of groups) {
      // The text said most often stands for the rest.
      let shown = group[0];
      for (const candidate of group) {
        const shownUses = this.uses.get(shown.text.id)?.length ?? 0;
        const candidateUses = this.uses.get(candidate.text.id)?.length ?? 0;
        if (
          candidateUses > shownUses ||
          (candidateUses === shownUses && candidate.text.id < shown.text.id)
        ) {
          shown = candidate;
        }
      }
      const text = shown.text;
      const part = ordinaryPart(text, shown.latinWords);
      const scoreIDs = [
        ...new Set(
          group.flatMap(({ text: member }) =>
            (this.uses.get(member.id) ?? [])
              .map((use) => use.score)
              .filter((score): score is number => score !== null),
          ),
        ),
      ].sort((left, right) => left - right);
      let title = text.title;
      let titleEnglish = text.titleEnglish;
      if (part === "ite")
        [title, titleEnglish] = ["Ite, missa est", "Dismissal"];
      if (part === "benedicamus") {
        [title, titleEnglish] = ["Benedicamus Domino", "Dismissal"];
      }
      if (part === "requiescant") {
        [title, titleEnglish] = ["Requiescant in pace", "Dismissal"];
      }
      const isSung =
        scoreIDs.length > 0 || (part !== null && kyrialeParts.has(part));
      const incipit = part !== null ? title : isSung ? opening(text.latin) : "";
      entries.push({
        id: `${MassPartSearch.idPrefix}${key}`,
        kind: text.kind,
        ordinary: part !== null || text.ordinary,
        part,
        title,
        titleEnglish,
        rubric: text.rubric,
        rubricEnglish: text.rubricEnglish,
        latin: text.latin,
        english: text.english,
        incipit,
        textIDs: group.map(({ text: member }) => member.id),
        scoreIDs,
        isSung,
        latinWords:
          words([title, text.rubric, incipit], true) + shown.latinWords,
        englishWords: words(
          [
            titleEnglish,
            text.rubricEnglish,
            text.english,
            ...(part === null ? [] : (englishAliases[part] ?? [])),
          ],
          false,
        ),
        length:
          Strings.characterCount(text.latin) +
          Strings.characterCount(text.english ?? ""),
      });
    }
    this.entries = entries;
    entries.forEach((entry, index) => {
      if (!this.entryIndices.has(entry.id))
        this.entryIndices.set(entry.id, index);
    });
  }

  entry(id: string): MassPartEntry | null {
    const index = this.entryIndices.get(id);
    return index === undefined ? null : this.entries[index];
  }

  /**
   * `search(query:language:filter:limit:)`: the parts whose fields hold every
   * word of the query, each at the beginning of a word, by how nearly each
   * answers it as a phrase, then the shorter first.
   */
  search(
    query: string,
    language: LiturgicalSearchLanguage,
    filter: MassPartFilter,
    limit: number,
  ): LiturgicalSearchHit[] {
    const tokens = SwiftString.splitOmittingEmpty(
      query,
      (character) =>
        !SwiftString.isLetter(character) && !SwiftString.isNumber(character),
    );
    if (tokens.length === 0) return [];
    const latinTokens = tokens.map(
      (token) => ` ${Strings.canonical(searchNormalized(token, true))}`,
    );
    const englishTokens = tokens.map(
      (token) => ` ${Strings.canonical(searchNormalized(token, false))}`,
    );
    const found: {
      rank: number;
      entry: MassPartEntry;
      hit: LiturgicalSearchHit;
    }[] = [];
    for (const entry of this.entries) {
      if (filter.kinds !== null && !filter.kinds.includes(entry.kind)) continue;
      if (filter.ordinary !== null && filter.ordinary !== entry.ordinary) {
        continue;
      }
      if (filter.requiresScore && !entry.isSung) continue;
      const inLatin =
        language !== "english" &&
        latinTokens.every((token) => entry.latinWords.includes(token));
      const inEnglish =
        language !== "latin" &&
        !inLatin &&
        englishTokens.every((token) => entry.englishWords.includes(token));
      if (!inLatin && !inEnglish) continue;
      const shownIn: LiturgicalSearchLanguage =
        language === "all" ? (inLatin ? "latin" : "english") : language;
      const rank = searchPhraseRank(entry, entry.incipit, query, shownIn);
      found.push({
        rank,
        entry,
        hit: {
          id: entry.id,
          kind: entry.kind,
          titleLatin: entry.title,
          titleEnglish: entry.titleEnglish,
          snippet: searchSnippet(entry, entry.incipit, query, shownIn),
          snippetLanguage: shownIn,
          hasScoredRealizations: entry.isSung,
          rank,
        },
      });
    }
    return found
      .sort((left, right) => {
        if (left.rank !== right.rank) return left.rank - right.rank;
        if (left.entry.length !== right.entry.length) {
          return left.entry.length - right.entry.length;
        }
        return Strings.compare(left.entry.id, right.entry.id);
      })
      .slice(0, Math.max(1, Math.min(limit, 50)))
      .map((item) => item.hit);
  }
}
