import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import {
  OfficeRubrics,
  type RubricRange,
} from "@/reader/presentation/officeRubrics.ts";

/**
 * A verse of a psalm or canticle read without its chant, set plainly: a
 * paragraph of its own, every line at the left edge and ragged at the
 * right, a red asterisk at its pause, kept to the word before it. A verse
 * of two lines breaks at its pause where its halves fit, a half-verse to a
 * line. A hymn's stanza is set a line to a block, its turns at the left
 * edge too. The web counterpart of `HoursApp/PsalterVerseView.swift`.
 */
export interface PsalterVerseProps {
  text: string;
  /** Point size at a reader scale of one. */
  fontSize: number;
  /** Extra space between lines at a reader scale of one. */
  lineSpacing?: number;
  form?: "verse" | "stanza";
  /** Whether it is the reader's text rather than the English beneath it,
   * as paper sets both. */
  principal?: boolean;
  italic?: boolean;
  lang?: string;
}

/** The marks that open a verse: a versicle's and a response's. */
const openingMark = /^(℣\.|℟\.) /u;

/** Words with their asterisks and crosses in red, an asterisk kept to the
 * word before it. */
function withSigns(text: string, key: string): ReactNode[] {
  const pieces: ReactNode[] = [];
  let plain = "";
  let index = 0;
  for (const character of text.replace(/ \*/gu, " *")) {
    if (character === "*" || character === "✠") {
      if (plain.length > 0) pieces.push(plain);
      plain = "";
      pieces.push(
        <span key={`${key}-${index}`} className="psalter-verse__sign">
          {character}
        </span>,
      );
    } else {
      plain += character;
    }
    index += 1;
  }
  if (plain.length > 0) pieces.push(plain);
  return pieces;
}

/** The words of the text from `from` to `to`, with their signs, and their
 * rubrics in red italic. */
function rubricated(
  text: string,
  from: number,
  to: number,
  rubrics: readonly RubricRange[],
  key: string,
): ReactNode[] {
  const pieces: ReactNode[] = [];
  let position = from;
  for (const rubric of rubrics) {
    const lower = Math.max(position, rubric.lowerBound);
    const upper = Math.min(to, rubric.upperBound);
    if (upper <= lower) continue;
    if (lower > position) {
      pieces.push(
        ...withSigns(text.slice(position, lower), `${key}${position}`),
      );
    }
    pieces.push(
      <span key={`${key}u${lower}`} className="psalter-verse__rubric">
        {withSigns(text.slice(lower, upper), `${key}${lower}`)}
      </span>,
    );
    position = upper;
  }
  if (position < to) {
    pieces.push(...withSigns(text.slice(position, to), `${key}${position}`));
  }
  return pieces;
}

/** The opening of a verse: its mark in red, if it has one, and where the
 * words after it begin. */
function opening(text: string): { lead: ReactNode[]; start: number } {
  const lead: ReactNode[] = [];
  const mark = openingMark.exec(text)?.[1];
  if (mark !== undefined) {
    lead.push(
      <span key="mark" className="psalter-verse__sign">
        {mark}
      </span>,
      " ",
    );
    return { lead, start: mark.length + 1 };
  }
  return { lead, start: 0 };
}

export function PsalterVerse({
  text,
  fontSize,
  lineSpacing = 0,
  form = "verse",
  principal = true,
  italic = false,
  lang,
}: PsalterVerseProps) {
  const paragraph = useRef<HTMLParagraphElement>(null);
  const first = useRef<HTMLSpanElement>(null);
  const second = useRef<HTMLSpanElement>(null);
  const [breaks, setBreaks] = useState(false);

  // The pause: the space after the first asterisk.
  const asterisk = form === "verse" ? text.indexOf("*") : -1;
  const pause = asterisk >= 0 && text[asterisk + 1] === " " ? asterisk + 1 : -1;

  useLayoutEffect(() => {
    const element = paragraph.current;
    if (pause < 0 || element === null) return;
    const measure = () => {
      const halves = [first.current, second.current];
      if (halves.some((half) => half === null)) return;
      const width = element.clientWidth;
      // Each half's width on a line of its own, wherever it now stands.
      const [one, two] = halves.map((half) =>
        [...half!.getClientRects()].reduce((sum, rect) => sum + rect.width, 0),
      );
      const space = parseFloat(getComputedStyle(element).fontSize) * 0.25;
      // On one line, or with a half too long for a line, the verse runs on.
      setBreaks(one + space + two > width && one <= width && two <= width);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [pause, text, fontSize]);

  const className = [
    "psalter-verse",
    form === "stanza" ? "psalter-verse--stanza" : "",
    principal ? "" : "psalter-verse--translation",
    italic ? "psalter-verse--italic" : "",
  ]
    .filter(Boolean)
    .join(" ");
  const style = {
    ["--text-size" as string]: `${fontSize}px`,
    ["--line-spacing" as string]: `${lineSpacing}px`,
  };

  const rubrics = OfficeRubrics.ranges(text);
  if (form === "stanza") {
    let lineStart = 0;
    return (
      <p className={className} style={style} lang={lang}>
        {text.split("\n").map((line, index) => {
          const start = lineStart;
          lineStart += line.length + 1;
          return (
            <span key={index} className="psalter-verse__line">
              {rubricated(
                text,
                start,
                start + line.length,
                rubrics,
                `l${index}-`,
              )}
            </span>
          );
        })}
      </p>
    );
  }

  const { lead, start } = opening(text);
  return (
    <p ref={paragraph} className={className} style={style} lang={lang}>
      {pause < 0 ? (
        <>
          {lead}
          {rubricated(text, start, text.length, rubrics, "v")}
        </>
      ) : (
        <>
          <span ref={first}>
            {lead}
            {rubricated(text, start, pause, rubrics, "a")}
          </span>
          {breaks ? <br /> : " "}
          <span ref={second}>
            {rubricated(text, pause + 1, text.length, rubrics, "b")}
          </span>
        </>
      )}
    </p>
  );
}
