import type { OfficeSection } from "@/core/models.ts";

/** A rubric's place in a text, in UTF-16 units. */
export interface RubricRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

/** The marks that open a line said or sung: a versicle's, a response's, an
 * antiphon's. A line they open is said, though it stand in a rubric's part. */
const spokenMark = /^(?:℣|℟|Ant\.|V\/|R\/)/u;

/**
 * The directions the editions print as lines of their own among the words
 * to be said, in Latin and in English. Each is the whole line, in lower case,
 * its last stop aside.
 */
const directionLines: readonly RegExp[] = [
  // Latin
  "secreto",
  "flexis genibus",
  "(?:sequens|prima) stropha(?: sequentis hymni)?(?:, si coram sanctissimo exposito officium persolvatur,)? dicitur flexis genibus",
  "et recto tono dicitur benedictio",
  "deinde dicitur secreto",
  "deinde dicitur tantum pater noster secreto, nisi sequatur alia hora",
  "et si tunc terminetur officium, dicitur tantum pater noster secreto",
  "si matutinum a laudibus separatur, tunc dicitur secreto",
  "«? ?pater noster ?»? dicitur (?:totum secreto|secreto usque ad .+)",
  "credo dicitur secreto usque ad .+",
  "examen conscientiæ vel «? ?pater noster ?»? totum secreto",
  "deinde, clara voce, dicitur versus",
  "et sub silentio concluditur",
  "gloria (?:omittitur|adduntur)",
  "secunda ['‘’]?domine, exaudi['‘’]? omittitur",
  "quæ non repetitur in psalmo",
  "reliqua omittuntur, nisi laudes separandæ sint",
  "extra chorum, quando ab uno tantum recitatur officium dicitur: .+",
  "in anno bissextili omittitur: .+",
  "post vesperas diei dicuntur vesper(?:æ|ae) defunctorum",
  "vesperæ ab iis qui .+ intersunt, hodie non dicuntur",
  // English
  "in secret",
  "silently",
  "kneel",
  "finish silently",
  "omit glory be",
  "the glory be is (?:omitted|added)",
  "skip (?:the )?second ['‘’]?o lord, hear my prayer['‘’]?",
  "the second ['‘’]?o lord, hear my prayer['‘’]? is omitted",
  "skip the rest, unless praying lauds separately",
  "it is not repeated in the psalm",
  "our father is said (?:silently until .+|completely in silence)",
  "credo is said silently until .+",
  "thereafter, with hearable voice, the versicle is said",
  "if matins and lauds are separated, then is said silently",
  "thereafter, only pater noster is said silently, unless another hour follows immediately",
  "and if thus the office is ended, only pater noster is said silently",
  "thereafter is said silently",
  "after vespers of the day, vespers of the dead are said",
  "if the office is celebrated before the exposed blessed sacrament, the following verses are said on bended knee",
  "the following verse is said on bended knee",
  "there follows an examination of conscience, or the our father said silently",
  "today, vespers are not said by those who assist at .+",
  "what follows is read in the usual lesson tone, and all stand",
].map((source) => new RegExp(`^(?:${source})[.:;,]?$`, "u"));

/**
 * The directions printed within a line, between parentheses: the bow, the
 * genuflexion, the striking of the breast. The words between the
 * parentheses are the whole direction, in lower case, its last stop aside;
 * a Father's aside in parentheses ("ut refert beátus Gregórius Papa") is
 * his own words.
 */
const bracketedDirections: readonly RegExp[] = [
  // Latin
  "genuflectitur",
  "fit reverentia(?:, secundum consuetudinem)?",
  "percutit sibi pectus",
  "secreto",
  "flexis genibus",
  "sequens versus dicitur flexis genibus",
  "prima stropha (?:hymni )?sequentis(?: hymni)? dicitur flex(?:is|ibus) genibus",
  "quod sequitur, legitur in tono lectionis consueto; et surgunt omnes",
  // English
  "genuflect",
  "bow head",
  "strikes his breast",
  "kneel for the following verse",
  "during the following verse,? (?:by local custom,? )?all make a profound bow",
  "the first verse of the following hymn is said genuflecting",
  "all kneel down",
  "what follows is read in the usual lesson tone, and all stand",
].map((source) => new RegExp(`^(?:${source})[.:;,]?$`, "u"));

const bracketed = /\(([^()]*)\)/gu;

function matchesAny(patterns: readonly RegExp[], words: string): boolean {
  const lowered = words.trim().toLowerCase();
  return patterns.some((pattern) => pattern.test(lowered));
}

/**
 * What a breviary prints in red among the words of the Office, beside the
 * signs and the marks of a line: the directions to the one who prays, and
 * the parts that are a rubric in their whole, a citation, a lesson's title,
 * a note that the Glory be is omitted.
 */
export const OfficeRubrics = {
  /** Whether a part is a rubric in its whole, printed as a part of its own
   * and not sung. */
  isRubric(section: Pick<OfficeSection, "kind" | "chant">): boolean {
    return section.kind === "rubric" && section.chant == null;
  },

  /**
   * The rubrics in a part's text, in order: each line of a rubric's own part
   * but those said, a line that is a direction, and a direction in
   * parentheses.
   */
  ranges(text: string, isRubric = false): RubricRange[] {
    const result: RubricRange[] = [];
    let start = 0;
    for (const line of text.split("\n")) {
      const words = line.trim();
      const lower = start + line.length - line.trimStart().length;
      if (
        words.length > 0 &&
        (isRubric ? !spokenMark.test(words) : matchesAny(directionLines, words))
      ) {
        result.push({ lowerBound: lower, upperBound: lower + words.length });
      } else {
        for (const match of words.matchAll(bracketed)) {
          if (!matchesAny(bracketedDirections, match[1] ?? "")) continue;
          const at = lower + (match.index ?? 0);
          result.push({ lowerBound: at, upperBound: at + match[0].length });
        }
      }
      start += line.length + 1;
    }
    return result;
  },
};
