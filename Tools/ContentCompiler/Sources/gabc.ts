import type {
  ChantClef,
  ChantEvent,
  ChantNotationModifier,
  ChantTimeline
} from "./types.ts";

const noteLetters = new Set("abcdefghijklmABCDEFGHIJKLM");
type ActiveAccidental = {
  pitch: number;
  modifier: "flat" | "natural" | "sharp";
};

export function gabcBody(gabc: string): string {
  const body = gabc.includes("%%")
    ? gabc.split("%%").slice(1).join("%%")
    : gabc;
  // A single percent sign begins a GABC line comment. Keep the line ending
  // so comments cannot accidentally join the lyric fragments around them.
  return body.replace(/%[^\r\n]*(?=\r\n|\r|\n|$)/g, "");
}

function cleanLyric(source: string): string {
  return source
    .replace(/<[^>]+>/g, "")
    .replace(/[{}]/g, "")
    // Psalm-tone sources wrap preparatory syllables in underscores and
    // accented syllables in asterisks. They are pointing/style delimiters,
    // not lyric characters. A standalone liturgical asterisk is unaffected.
    .replace(/_([^_]+)_/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .trim()
    .replace(/\s+/g, " ");
}

function durationWeight(token: string, phraseBoundary: boolean): number {
  let weight = 1;
  if (token.includes(".")) weight += 0.5;
  if (token.includes("_")) weight += 0.25;
  if (phraseBoundary) weight += 0.4;
  return weight;
}

function modifiers(
  token: string,
  phraseBoundary: boolean,
  activeAccidental: ActiveAccidental | null,
  pitch: number
): ChantNotationModifier[] {
  const values: ChantNotationModifier[] = [];
  if (token.includes(".")) values.push("mora");
  if (token.includes("_")) values.push("episema");
  if (token.includes("w") || token.includes("W")) values.push("quilisma");
  if (token.includes("<") || token.includes(">") || token.includes("~")) values.push("liquescent");
  if (token.includes("x")) values.push("flat");
  if (token.includes("y")) values.push("natural");
  if (token.includes("#")) values.push("sharp");
  if (activeAccidental?.pitch === pitch) values.push(activeAccidental.modifier);
  if (phraseBoundary) values.push("phraseBoundary");
  return [...new Set(values)];
}

export function parseGABC(gabc: string, scoreID: string): ChantTimeline {
  const body = gabcBody(gabc);
  const groupPattern = /([^()]*)\(([^)]*)\)/g;
  const events: ChantEvent[] = [];
  let phraseIndex = 0;
  let syllableIndex = 0;
  let activeClef: ChantClef = { kind: "c", line: 3, flattensB: false };
  let activeAccidental: ActiveAccidental | null = null;
  let match: RegExpExecArray | null;

  while ((match = groupPattern.exec(body)) !== null) {
    const syllable = cleanLyric(match[1]);
    const notation = match[2];
    const phraseBoundary = /::|:|;/.test(notation);
    const parsedNotes: Array<{
      pitch: number;
      suffix: string;
      clef: ChantClef;
      accidental: ActiveAccidental | null;
    }> = [];
    for (let index = 0; index < notation.length;) {
      const note = notation[index];
      if (note === "[") {
        const annotationEnd = notation.indexOf("]", index + 1);
        index = annotationEnd >= 0 ? annotationEnd + 1 : notation.length;
        continue;
      }
      const clefToken = notation.slice(index).match(/^(cb?([1-4])|f([1-4]))/);
      if (clefToken) {
        activeClef = {
          kind: clefToken[0].startsWith("f") ? "f" : "c",
          line: Number(clefToken[2] ?? clefToken[3]) as ChantClef["line"],
          flattensB: clefToken[0].startsWith("cb")
        };
        activeAccidental = null;
        index += clefToken[0].length;
        continue;
      }
      if (!noteLetters.has(note)) {
        // Exsurge resets an explicitly declared accidental at every divider
        // except the virgula (`). The flat carried by a cb clef is represented
        // by the clef itself and therefore remains in force.
        if (note === "," || note === ";" || note === ":") {
          activeAccidental = null;
        }
        index += 1;
        continue;
      }

      const pitch =
        note.toLowerCase().charCodeAt(0) - "h".charCodeAt(0);
      const accidentalCode = notation[index + 1];
      if (accidentalCode === "x" || accidentalCode === "y" || accidentalCode === "#") {
        // In GABC, `ix`, `iy`, and `i#` are standalone accidental
        // declarations at pitch i. The pitch letter positions the accidental;
        // it does not create a sung note or consume a timeline event.
        activeAccidental = {
          pitch,
          modifier: accidentalCode === "x"
            ? "flat"
            : accidentalCode === "y"
              ? "natural"
              : "sharp"
        };
        index += 2;
        continue;
      }
      index += 1;
      let suffix = "";
      while (index < notation.length) {
        const next = notation[index];
        if (next === "[") {
          const annotationEnd = notation.indexOf("]", index + 1);
          index = annotationEnd >= 0 ? annotationEnd + 1 : notation.length;
          continue;
        }
        const startsClef = /^(cb?[1-4]|f[1-4])/.test(notation.slice(index));
        if (
          startsClef ||
          noteLetters.has(next) ||
          /\s|\/|:|;|,|`|z|Z/.test(next)
        ) {
          break;
        }
        suffix += next;
        index += 1;
      }
      parsedNotes.push({
        pitch,
        suffix,
        clef: activeClef,
        accidental: activeAccidental
      });
    }

    if (parsedNotes.length === 0) {
      if (phraseBoundary) phraseIndex += 1;
      continue;
    }
    const syllableID = `${scoreID}-syllable-${syllableIndex}`;
    for (const [noteIndex, note] of parsedNotes.entries()) {
      const phraseID = `${scoreID}-phrase-${phraseIndex}`;
      const isBoundaryNote = phraseBoundary && noteIndex === parsedNotes.length - 1;
      events.push({
        id: `${scoreID}-note-${events.length}`,
        syllableID,
        phraseID,
        syllable,
        relativePitch: note.pitch,
        durationWeight: durationWeight(note.suffix, isBoundaryNote),
        modifiers: modifiers(
          note.suffix,
          isBoundaryNote,
          note.accidental,
          note.pitch
        ),
        clef: note.clef
      });
    }

    if (phraseBoundary) phraseIndex += 1;
    syllableIndex += 1;
  }

  if (events.length === 0) {
    throw new Error(`Score ${scoreID} produced no note events`);
  }
  return { events };
}
