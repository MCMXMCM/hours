import { useLayoutEffect, useRef, useState, type ReactNode } from "react";

/**
 * The words of a Mass set plainly, every line at the left edge and a space
 * between them: the mark of a line (S., M., ℣., ℟.) in red before its
 * words; the first prayer of a part opening with a red initial two lines
 * tall, the rest of its first word in small capitals; crosses and the
 * directions in parentheses in red. The English beneath the Latin is set in
 * the same way, its marks in red, without initials; the English shown alone
 * is set as the Latin is. The web counterpart of
 * `HoursApp/MissalTextView.swift`.
 */
export type MissalVoice = "latin" | "english" | "englishAlone";

/** The marks that say who speaks a line: the priest, the server, the
 * deacon, all; the versicle and the response. */
const marks: ReadonlySet<string> = new Set([
  "℣.",
  "℟.",
  "S.",
  "M.",
  "D.",
  "C.",
  "P.",
  "A.",
]);

/** The mark that opens a line, if it has one. */
function markOf(line: string): string | null {
  const space = line.indexOf(" ");
  if (space < 0) return null;
  const mark = line.slice(0, space);
  return marks.has(mark) ? mark : null;
}

function isUppercaseLetter(character: string | undefined): boolean {
  return (
    character !== undefined &&
    /\p{L}/u.test(character) &&
    character === character.toUpperCase() &&
    character !== character.toLowerCase()
  );
}

/** The words that announce a reading: a lesson or an epistle, the gospel or
 * the passion, in Latin or in English. */
const announcement =
  /^(?:L[eé]ctio|Sequ[eé]ntia|In[ií]tium|P[aá]ssio|Lesson|Reading|A reading|From the|Continuation|The beginning|Beginning|The Passion|Passion)(?!\p{L})/u;

/** The bidding before a prayer, which the prayer's initial follows. */
const bidding = /^(?:Or[eé]mus|Let us pray)[.:]?$/u;

/** The parts of the Mass that are read, each announced by its first line. */
export function isMassReading(kind: string): boolean {
  return (
    kind === "reading" ||
    kind === "epistle" ||
    kind === "gospel" ||
    kind === "lastGospel"
  );
}

/** The line that opens with the part's initial: its first prayer, the first
 * line neither marked nor a direction that begins with a capital. In a
 * reading the line that announces it is passed over, so that the initial
 * opens the reading itself, as a missal sets it. */
export function initialLine(
  lines: readonly string[],
  isReading = false,
): number {
  const candidates = lines.flatMap((line, index) =>
    markOf(line) === null &&
    isUppercaseLetter([...line][0]) &&
    [...line].length >= 12 &&
    !bidding.test(line.trim())
      ? [index]
      : [],
  );
  const [first = -1, second] = candidates;
  if (
    isReading &&
    second !== undefined &&
    announcement.test(lines[first].normalize("NFC"))
  ) {
    return second;
  }
  return first;
}

/** A response given within a line, as a litany's ("Saint Agatha. R. Pray
 * for us."), with its proper mark. */
export function withResponses(line: string): string {
  return line.replace(/(?<=[.!?]\s)R\.(?=\s)/gu, "℟.");
}

/** Crosses, the marks of a versicle or response within a line, and the
 * directions and verse numbers in parentheses, in red. */
function decorated(text: string, key: string): ReactNode[] {
  const pieces: ReactNode[] = [];
  const pattern = /\([^)]*\)?|✠|[℣℟]\./gu;
  let position = 0;
  for (const match of text.matchAll(pattern)) {
    const index = match.index ?? 0;
    if (index > position) pieces.push(text.slice(position, index));
    pieces.push(
      <span
        key={`${key}-${index}`}
        className={
          match[0] === "✠"
            ? "missal-text__cross"
            : match[0].startsWith("(")
              ? "missal-text__direction"
              : "missal-text__inline-mark"
        }
      >
        {match[0]}
      </span>,
    );
    position = index + match[0].length;
  }
  if (position < text.length) pieces.push(text.slice(position));
  return pieces;
}

export interface MissalTextProps {
  text: string;
  /** Point size at a reader scale of one. */
  fontSize: number;
  /** Extra space between lines at a reader scale of one. */
  lineSpacing?: number;
  voice?: MissalVoice;
  /** Whether the part's first prayer opens with a red initial two lines
   * tall. */
  opensWithInitial?: boolean;
  /** Whether the text is a reading, its first line announcing it: the
   * initial then opens the reading itself. */
  isReading?: boolean;
  className?: string;
}

export function MissalText({
  text,
  fontSize,
  lineSpacing = 0,
  voice = "latin",
  opensWithInitial = false,
  isReading = false,
  className,
}: MissalTextProps) {
  const isPrincipal = voice !== "english";
  const lines = text.split("\n");
  const initial =
    isPrincipal && opensWithInitial ? initialLine(lines, isReading) : -1;
  const paragraph = useRef<HTMLParagraphElement>(null);
  const [initialStandsBeside, setInitialStandsBeside] = useState(false);

  // An initial is two lines tall. Where its own line is a single line at
  // this width, the next line stands beside it too, as a drop cap's does.
  useLayoutEffect(() => {
    const element = paragraph.current;
    if (element === null || initial < 0) {
      setInitialStandsBeside(false);
      return;
    }
    const measure = () => {
      const line = element.querySelector<HTMLElement>(
        ".missal-text__line--initial",
      );
      if (line === null) return;
      const lineHeight = parseFloat(getComputedStyle(line).lineHeight);
      setInitialStandsBeside(
        line.getBoundingClientRect().height < lineHeight * 1.5,
      );
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [initial, text]);

  return (
    <p
      ref={paragraph}
      className={[
        "missal-text",
        isPrincipal ? "missal-text--principal" : "missal-text--translation",
        initialStandsBeside ? "missal-text--initial-beside" : "",
        className ?? "",
      ]
        .filter(Boolean)
        .join(" ")}
      style={{
        ["--text-size" as string]: `${fontSize}px`,
        ["--line-spacing" as string]: `${lineSpacing}px`,
      }}
    >
      {lines.map((sourceLine, index) => {
        const line = withResponses(sourceLine);
        const key = `l${index}`;
        if (line.trim().length === 0) {
          return (
            <span
              key={key}
              className="missal-text__line missal-text__line--blank"
            />
          );
        }
        const mark = markOf(line);
        if (mark !== null) {
          // The mark in red, and its words after it.
          return (
            <span
              key={key}
              className="missal-text__line missal-text__line--marked"
            >
              <span className="missal-text__mark">{`${mark} `}</span>
              {decorated(line.slice(mark.length + 1), key)}
            </span>
          );
        }
        const first = [...line][0];
        if (index === initial) {
          // The initial, drawn two lines tall from the line's first letter;
          // the rest of the first word in small capitals.
          const word = /^\p{L}[\p{L}\p{M}'’]*/u.exec(line)?.[0] ?? first;
          return (
            <span
              key={key}
              className="missal-text__line missal-text__line--initial"
            >
              <span className="missal-text__first-word">{word}</span>
              {decorated(line.slice(word.length), key)}
            </span>
          );
        }
        return (
          <span key={key} className="missal-text__line">
            {decorated(line, key)}
          </span>
        );
      })}
    </p>
  );
}
