import { Fragment, type ReactNode } from "react";

export interface TextRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

export interface OfficeTextProps {
  text: string;
  /** Point size at a reader scale of one. */
  fontSize: number;
  /** Extra space between lines at a reader scale of one, as the native reader sets it. */
  lineSpacing?: number;
  italic?: boolean;
  secondary?: boolean;
  /** Ranges of `text`, in UTF-16 units, set in the semibold weight. */
  emphasizedRanges?: readonly TextRange[];
  label?: string;
  className?: string;
}

/** The marks that open a line: a versicle's and a response's, a short
 * responsory's, an antiphon's, and the Paschal addition's. */
const lineMark = /^(℟\.br\.|℣\.br\.|℣\.|℟\.|Ant\.|T\.P\.) /u;
/** The signs coloured wherever they stand. */
const rubricSigns = /[✠✙†*]/u;

/** Text with its rubric signs coloured. */
function withSigns(text: string, key: string): ReactNode {
  const pieces: ReactNode[] = [];
  let plain = "";
  let index = 0;
  for (const character of text) {
    if (rubricSigns.test(character)) {
      if (plain.length > 0) pieces.push(plain);
      plain = "";
      pieces.push(
        <span key={`${key}-${index}`} className="office-text__sign">
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

/** A stretch of the text, from `start` to `end` (UTF-16 offsets), with its
 * emphasized syllables in semibold and its signs coloured. */
function decorated(
  text: string,
  start: number,
  end: number,
  ranges: readonly TextRange[],
): ReactNode[] {
  const pieces: ReactNode[] = [];
  let position = start;
  const plain = (from: number, to: number, key: string) =>
    withSigns(text.slice(from, to), key);
  ranges.forEach((range, index) => {
    const lower = Math.max(position, range.lowerBound);
    const upper = Math.min(end, range.upperBound);
    if (upper <= lower) return;
    if (lower > position) {
      pieces.push(
        <Fragment key={`p${start}-${index}`}>
          {plain(position, lower, `p${start}-${index}`)}
        </Fragment>,
      );
    }
    pieces.push(
      <strong key={`e${start}-${index}`} className="office-text__emphasis">
        {plain(lower, upper, `e${start}-${index}`)}
      </strong>,
    );
    position = upper;
  });
  if (position < end) {
    pieces.push(
      <Fragment key={`r${start}`}>
        {plain(position, end, `r${start}`)}
      </Fragment>,
    );
  }
  return pieces;
}

/**
 * A passage of the Office, selectable as ordinary text, a line to a block,
 * every line at the left edge. The type scales with the reader size. The
 * marks a breviary prints in red are red: a versicle's and a response's, an
 * antiphon's, the cross and the signs of the chant's pauses, each before
 * its words.
 */
export function OfficeText({
  text,
  fontSize,
  lineSpacing = 0,
  italic = false,
  secondary = false,
  emphasizedRanges = [],
  label,
  className,
}: OfficeTextProps) {
  const ranges = [...emphasizedRanges]
    .filter((range) => range.upperBound > range.lowerBound)
    .sort((a, b) => a.lowerBound - b.lowerBound);

  const lines: ReactNode[] = [];
  let start = 0;
  for (const line of text.split("\n")) {
    const end = start + line.length;
    if (line.trim().length === 0) {
      lines.push(
        <span
          key={`l${start}`}
          className="office-text__line office-text__line--blank"
        />,
      );
    } else {
      const mark = lineMark.exec(line)?.[1] ?? null;
      const markEnd = mark === null ? start : start + mark.length;
      lines.push(
        <span key={`l${start}`} className="office-text__line">
          {mark !== null && <span className="office-text__mark">{mark}</span>}
          {decorated(text, markEnd, end, ranges)}
        </span>,
      );
    }
    start = end + 1;
  }

  return (
    <p
      className={[
        "office-text",
        italic ? "office-text--italic" : "",
        secondary ? "office-text--secondary" : "",
        "office-text--lines",
        className ?? "",
      ]
        .filter(Boolean)
        .join(" ")}
      aria-label={label}
      style={{
        ["--text-size" as string]: `${fontSize}px`,
        ["--line-spacing" as string]: `${lineSpacing}px`,
      }}
    >
      {lines}
    </p>
  );
}
