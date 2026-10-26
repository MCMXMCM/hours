import type { WebEdition } from "@compiler/webCorpusFormat.ts";

/** A corpus identity, independent of language, appearance, and civil date. */
export type OfficeTradition = WebEdition;

/** In the order the Rubrics setting offers them. */
export const officeTraditions: readonly OfficeTradition[] = [
  "roman1954",
  "roman1960",
];

export const defaultOfficeTradition: OfficeTradition = "roman1960";

export const OfficeTraditions = {
  isOfficeTradition(value: unknown): value is OfficeTradition {
    return value === "roman1954" || value === "roman1960";
  },

  title(tradition: OfficeTradition): string {
    return tradition === "roman1954" ? "Roman 1954" : "Roman 1960";
  },

  rubrics(tradition: OfficeTradition): string {
    return tradition === "roman1954"
      ? "Divino Afflatu - 1954"
      : "Rubrics 1960 - 1960";
  },

  description(tradition: OfficeTradition): string {
    return tradition === "roman1954"
      ? "The Roman Divine Office under the pre-1955 Divino Afflatu rubrics. This edition follows Divinum Officium’s 1954 calendar: the general calendar as amended through 1954, including the Queenship of Our Lady and St Pius X."
      : "The Roman Divine Office under the 1960 rubrics.";
  },
};
