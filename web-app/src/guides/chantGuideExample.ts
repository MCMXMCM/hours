// What an example of the Guide to Chant shows, apart from its drawing:
// the logic of `HoursApp/ChantGuideExampleView.swift`. `ChantGuideSolfege`
// is Swift's enum of that name; a private member of the Swift view is a
// function of the same name in the namespace of the view it belongs to.

import { GABCClefs } from "@/cantor/performance.ts";
import type { ChantEvent, ChantScore } from "@/core/models.ts";
import * as SwiftString from "@/core/swiftString.ts";
import type {
  ChantGuideExample,
  ChantGuideFormulaNote,
  ChantGuideRect,
  ChantGuideVariant,
} from "./chantGuideDocument.ts";

const solfegeNames = ["Do", "Re", "Mi", "Fa", "Sol", "La", "Ti"] as const;

export const ChantGuideSolfege = {
  name(event: ChantEvent, score: ChantScore): string {
    const clef =
      event.clef != null
        ? GABCClefs.fromChantClef(event.clef)
        : GABCClefs.fromGABC(score.gabc);
    const step =
      event.relativePitch +
      1 -
      (2 * clef.line - 5) +
      (clef.kind === "f" ? 3 : 0);
    const index = ((step % 7) + 7) % 7;
    const flat =
      event.modifiers.includes("flat") ||
      (clef.flattensB && index === 6 && !event.modifiers.includes("natural"));
    return solfegeNames[index] + (flat ? "♭" : "");
  },
};

const restOnPrefix = "Rest on ";

export const ChantGuideExampleViews = {
  // Display staff positions from top to bottom without changing the score's
  // first variant, which also supplies the comparison's pitch reference.
  variantChoices(example: ChantGuideExample): readonly ChantGuideVariant[] {
    return example.id === "clef-staff-positions"
      ? [...example.variants].reverse()
      : example.variants;
  },

  /**
   * Whether the versions of an example are offered side by side. They are
   * while they fit; a longer comparison is chosen from a menu.
   */
  offersVariantTabs(example: ChantGuideExample): boolean {
    return example.variants.length <= 3 || example.id === "modal-formulas";
  },

  /** How the choice among an example's versions is named. */
  variantSelectorLabel(example: ChantGuideExample): string {
    return example.id === "modal-formulas" ? "Rest On" : "Example version";
  },

  tabTitle(example: ChantGuideExample, choice: ChantGuideVariant): string {
    if (
      example.id === "modal-formulas" &&
      SwiftString.hasPrefix(choice.title, restOnPrefix)
    ) {
      return SwiftString.dropFirst(
        choice.title,
        SwiftString.characterCount(restOnPrefix),
      );
    }
    if (example.id === "clef-staff-positions") {
      switch (choice.score.timeline.events[0]?.clef?.line) {
        case 4:
          return "Fourth line";
        case 3:
          return "Third line";
        case 2:
          return "Second line";
        default:
          break;
      }
    }
    return choice.title;
  },

  /** How a note of the singing order is named to assistive technology. */
  noteAccessibilityLabel(
    index: number,
    event: ChantEvent,
    score: ChantScore,
  ): string {
    return `Note ${index + 1}, ${ChantGuideSolfege.name(event, score)}, ${event.syllable}`;
  },
};

// MARK: Formula

/** Where one symbol of a formula is drawn, in the formula's own coordinates. */
export interface ChantGuideFormulaMark {
  readonly note: ChantGuideFormulaNote;
  /** The middle of the symbol and of its label. */
  readonly x: number;
  /** The symbol's square. */
  readonly rect: ChantGuideRect;
}

export const ChantGuideFormulaViews = {
  /** The height of the drawing. */
  height: 96,
  /** Where the label of a symbol is centred. */
  labelY: 78,

  /** The four lines of the staff, from the top, across a drawing of the given width. */
  staffLines(
    width: number,
  ): { x1: number; y1: number; x2: number; y2: number }[] {
    return [0, 1, 2, 3].map((line) => ({
      x1: 8,
      y1: 18 + line * 12,
      x2: width - 8,
      y2: 18 + line * 12,
    }));
  },

  marks(
    notes: readonly ChantGuideFormulaNote[],
    width: number,
  ): ChantGuideFormulaMark[] {
    return notes.map((note, index) => {
      const x = 20 + (index * (width - 40)) / Math.max(1, notes.length - 1);
      return {
        note,
        x,
        rect: { x: x - 4, y: 50 - note.step * 6, width: 8, height: 8 },
      };
    });
  },

  accessibilityLabel(notes: readonly ChantGuideFormulaNote[]): string {
    return notes
      .map((note) => `${note.label}${note.optional ? ", additional note" : ""}`)
      .join("; ");
  },
};

// MARK: Annotation

/** A note marked on the staff: where it is drawn, and on which line. */
export interface ChantGuideNotePlacement {
  readonly frame: ChantGuideRect;
  readonly lineIndex: number;
}

/** One staff of a drawing: its place among the lines, and its top line. */
export interface ChantGuideStaff {
  readonly index: number;
  readonly minY: number;
}

/** A bracket over the marked notes of one staff. */
export interface ChantGuideBracket {
  readonly left: number;
  readonly right: number;
  /** The bracket's bar; its ends hang four points below. */
  readonly y: number;
}

export interface ChantGuideAnnotationMarks {
  /** A frame about each marked note. */
  readonly outlines: readonly ChantGuideRect[];
  readonly brackets: readonly ChantGuideBracket[];
}

export const ChantGuideAnnotationOverlay = {
  /** How far a note's outline stands from the note. */
  outset: 3,
  /** How far the ends of a bracket hang below its bar. */
  bracketDrop: 4,

  marks(
    placements: readonly ChantGuideNotePlacement[],
    staffs: readonly ChantGuideStaff[],
  ): ChantGuideAnnotationMarks {
    const outset = ChantGuideAnnotationOverlay.outset;
    const outlines = placements.map(({ frame }) => ({
      x: frame.x - outset,
      y: frame.y - outset,
      width: frame.width + 2 * outset,
      height: frame.height + 2 * outset,
    }));

    // Split brackets at actual system breaks; annotation geometry never enters the timeline.
    const brackets: ChantGuideBracket[] = [];
    for (const staff of staffs) {
      const onLine = placements.filter(
        (placement) => placement.lineIndex === staff.index,
      );
      if (!(onLine.length > 1)) continue;
      const left = Math.min(...onLine.map(({ frame }) => frame.x));
      const right = Math.max(
        ...onLine.map(({ frame }) => frame.x + frame.width),
      );
      const y = Math.min(
        staff.minY - 9,
        Math.min(...onLine.map(({ frame }) => frame.y)) - 9,
      );
      brackets.push({ left, right, y });
    }
    return { outlines, brackets };
  },
};
