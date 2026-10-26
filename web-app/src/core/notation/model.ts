// The engraving model of a GABC score, parallel to the declarations at the
// head of gabc-parser's `Sources/GABCParser/GregorianNotation.swift`. Types carry the Swift names
// and stored properties; a Swift computed property is a function in the
// namespace named for its type.

export interface GregorianSourceRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

export type GregorianClefKind = "c" | "f";

export interface GregorianClef {
  readonly kind: GregorianClefKind;
  readonly line: number;
  readonly flattensB: boolean;
}

export type GregorianAccidental = "flat" | "natural" | "sharp";

export type GregorianDivision = "minima" | "minor" | "major" | "final";

export type GregorianNoteShape =
  | "punctum"
  | "virga"
  | "quilisma"
  | "liquescent"
  | "inclinatum"
  | "oriscus"
  | "stropha"
  /**
   * A custos written in the score itself (`f+`): a guide to the pitch that
   * follows, usually before a change of clef. The compiled timeline holds an
   * event for it, as for every pitch letter, but it is drawn as a custos and
   * is never sung.
   */
  | "custos";

export type GregorianLiquescence =
  "none" | "small" | "ascending" | "descending";

export type GregorianEpisemaPosition = "above" | "below";

export interface GregorianAccidentalMark {
  readonly kind: GregorianAccidental;
  readonly pitch: number;
  readonly sourceRange: GregorianSourceRange;
}

/**
 * Semantic neume families. These deliberately mirror Exsurge's named-neume
 * layer rather than treating a neume as an arbitrary row of noteheads.
 */
export type GregorianNeumeForm =
  | "apostropha"
  | "bivirga"
  | "trivirga"
  | "climacus"
  | "clivis"
  | "ancus"
  | "distropha"
  | "oriscus"
  | "pesQuassus"
  | "pesSubpunctis"
  | "podatus"
  | "porrectus"
  | "porrectusFlexus"
  | "punctaInclinata"
  | "punctum"
  | "salicus"
  | "salicusFlexus"
  | "scandicus"
  | "scandicusFlexus"
  | "torculus"
  | "torculusResupinus"
  | "torculusResupinusFlexus"
  | "tristropha"
  | "virga";

export type GregorianLyricStyle =
  "regular" | "preparatory" | "accented" | "rubric";

export interface GregorianNote {
  readonly id: string;
  readonly pitch: number;
  readonly relativePitch: number;
  readonly shape: GregorianNoteShape;
  readonly accidental: GregorianAccidental | null;
  readonly hasMora: boolean;
  readonly hasEpisema: boolean;
  readonly moraCount: number;
  readonly episemaPosition: GregorianEpisemaPosition;
  readonly liquescence: GregorianLiquescence;
  readonly isCavum: boolean;
  readonly hasIctus: boolean;
  /**
   * How many notes the one pitch letter writes. GABC abbreviates two virgae
   * or three strophae on a pitch as `hvv` and `hsss`; the compiled timeline
   * holds a single event for the group, which is drawn and sung as that many
   * notes.
   */
  readonly repetitionCount: number;
  readonly sourceRange: GregorianSourceRange;
}

export interface GregorianNeume {
  readonly id: string;
  readonly syllableID: string;
  readonly lyric: string;
  readonly lyricStyle: GregorianLyricStyle;
  readonly startsWord: boolean;
  readonly notes: readonly GregorianNote[];
  readonly form: GregorianNeumeForm;
  readonly sourceRange: GregorianSourceRange;
}

export interface GregorianLyricMark {
  readonly text: string;
  readonly style: GregorianLyricStyle;
  readonly startsWord: boolean;
  readonly sourceRange: GregorianSourceRange;
}

/** One case of Swift's `GregorianNotationElement`, named by `type`. */
export type GregorianNotationElement =
  | { readonly type: "clef"; readonly clef: GregorianClef }
  | {
      readonly type: "accidental";
      readonly accidental: GregorianAccidentalMark;
    }
  | { readonly type: "neume"; readonly neume: GregorianNeume }
  | { readonly type: "lyricMark"; readonly lyricMark: GregorianLyricMark }
  | { readonly type: "division"; readonly division: GregorianDivision }
  | { readonly type: "forcedBreak" };

export interface GregorianScore {
  readonly elements: readonly GregorianNotationElement[];
}

export const GregorianNotes = {
  /** True for a custos, which guides the eye and is not sung. */
  isCustos(note: GregorianNote): boolean {
    return note.shape === "custos";
  },

  /**
   * The notes this one event draws and sings: as many as it is written, and
   * none for a custos.
   */
  writtenNoteCount(note: GregorianNote): number {
    return GregorianNotes.isCustos(note) ? 0 : note.repetitionCount;
  },

  /** A custos, or a note written more than once, is a neume in itself. */
  standsAlone(note: GregorianNote): boolean {
    return GregorianNotes.isCustos(note) || note.repetitionCount > 1;
  },
};

export const GregorianNeumes = {
  eventIDs(neume: GregorianNeume): string[] {
    return neume.notes.map((note) => note.id);
  },

  /**
   * The notes the neume draws and sings: one for each note, or as many as a
   * doubled note is written, and none for a custos.
   */
  writtenNoteCount(neume: GregorianNeume): number {
    return neume.notes.reduce(
      (count, note) => count + GregorianNotes.writtenNoteCount(note),
      0,
    );
  },
};

export const GregorianLyricMarks = {
  id(mark: GregorianLyricMark): string {
    return `lyric-mark-${mark.sourceRange.lowerBound}-${mark.sourceRange.upperBound}`;
  },
};

export const GregorianScores = {
  make(elements: readonly GregorianNotationElement[]): GregorianScore {
    return { elements };
  },

  neumes(score: GregorianScore): GregorianNeume[] {
    const result: GregorianNeume[] = [];
    for (const element of score.elements) {
      if (element.type === "neume") result.push(element.neume);
    }
    return result;
  },

  eventIDs(score: GregorianScore): string[] {
    return GregorianScores.neumes(score).flatMap(GregorianNeumes.eventIDs);
  },

  /** The words a score sings, as running text. */
  lyricText(score: GregorianScore): string {
    let result = "";
    let separatesFollowingLyric = false;

    const append = (
      text: string,
      startsWord: boolean,
      isLyricMark: boolean,
    ) => {
      if (text.length === 0) return;
      if (
        result.length > 0 &&
        (startsWord || separatesFollowingLyric) &&
        !/\s$/u.test(result)
      ) {
        result += " ";
      }
      result += text;
      separatesFollowingLyric = isLyricMark;
    };

    for (const element of score.elements) {
      if (element.type === "neume") {
        append(element.neume.lyric, element.neume.startsWord, false);
      } else if (element.type === "lyricMark") {
        append(element.lyricMark.text, element.lyricMark.startsWord, true);
      }
    }

    return result.replace(/\s+([,.;:!?])/gu, "$1");
  },
};
