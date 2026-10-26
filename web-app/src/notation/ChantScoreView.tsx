import { useEffect, useLayoutEffect, useMemo, useRef } from "react";
import {
  neumeLabel,
  sungParts,
  type EngravedNeume,
  type Engraving,
} from "./engraver.ts";

export interface ChantScoreViewProps {
  /** The prepared drawing, or the reason there is none. */
  engraving: Engraving | { error: string };
  /** The timeline event being sung now, if this score is the one playing. */
  sungEventID?: string | null;
  /** Called with a neume when it is tapped or activated from the keyboard. */
  onSelectNeume?: (neume: EngravedNeume) => void;
  /**
   * Set for paper: each staff is then a drawing of its own, so that a page
   * may end between two staves and never through one.
   */
  paged?: boolean;
}

/** The drawing as one small drawing for each of its staves, in order. */
function pagedLines(drawing: Engraving): SVGSVGElement[] {
  const group = drawing.svg.querySelector(".gregorian-score");
  if (!group) return [];
  return drawing.lines.map((line, index) => {
    const slice = drawing.svg.cloneNode(false) as SVGSVGElement;
    const height = line.bottom - line.top;
    slice.setAttribute("height", String(height));
    slice.setAttribute("viewBox", `0 ${line.top} ${drawing.width} ${height}`);
    const content = group.cloneNode(false);
    const staff = group.querySelector(`:scope > [data-staff="${index}"]`);
    if (staff) content.appendChild(staff.cloneNode(true));
    slice.appendChild(content);
    return slice;
  });
}

/**
 * A chant score. The drawing is prepared before the reader appears, so its
 * height is known and the page never shifts as scores arrive.
 */
export function ChantScoreView({
  engraving,
  sungEventID,
  onSelectNeume,
  paged = false,
}: ChantScoreViewProps) {
  const host = useRef<HTMLDivElement>(null);
  const failed = "error" in engraving;
  const drawing = failed ? null : engraving;
  // One chant may stand in several places in an office, an antiphon before
  // and after its psalm for one; each place needs a drawing of its own.
  const svg = useMemo(
    () =>
      drawing && !paged ? (drawing.svg.cloneNode(true) as SVGSVGElement) : null,
    [drawing, paged],
  );
  const staves = useMemo(
    () => (drawing && paged ? pagedLines(drawing) : null),
    [drawing, paged],
  );

  useLayoutEffect(() => {
    const element = host.current;
    const drawn = svg ? [svg] : staves;
    if (!element || !drawn) return;
    element.prepend(...drawn);
    return () => {
      for (const piece of drawn) piece.remove();
    };
  }, [staves, svg]);

  // Mark the neume holding the sung note, and the words of its syllable.
  useEffect(() => {
    if (!svg || !drawing || !sungEventID) return;
    const parts = sungParts(drawing, sungEventID);
    if (!parts) return;
    const marked: Element[] = [];
    const neume = svg.querySelector(
      `.gregorian-neume[data-neume="${CSS.escape(parts.neume.id)}"]`,
    );
    if (neume) {
      neume.classList.add("is-sung");
      marked.push(neume);
    }
    for (const id of parts.syllableNeumeIDs) {
      for (const words of svg.querySelectorAll(
        `.gregorian-lyric[data-neume="${CSS.escape(id)}"]`,
      )) {
        words.classList.add("is-sung-syllable");
        marked.push(words);
      }
    }
    // Its button is where the reader looks to keep the sung neume in view.
    const button = host.current?.querySelector(
      `.chant-score__neume[data-neume="${parts.neume.index}"]`,
    );
    button?.setAttribute("data-sung", "");
    return () => {
      for (const element of marked) {
        element.classList.remove("is-sung", "is-sung-syllable");
      }
      button?.removeAttribute("data-sung");
    };
  }, [svg, drawing, sungEventID]);

  const buttons = useMemo(
    () =>
      drawing && onSelectNeume && !paged
        ? drawing.neumes.map((neume) => (
            <button
              key={neume.index}
              type="button"
              className="chant-score__neume"
              data-neume={neume.index}
              aria-label={neumeLabel(neume)}
              title="Starts the cantor guide here"
              style={{
                left: neume.hitFrame.x,
                top: neume.hitFrame.y,
                width: neume.hitFrame.width,
                height: neume.hitFrame.height,
              }}
              onClick={() => onSelectNeume(neume)}
            />
          ))
        : null,
    [drawing, onSelectNeume, paged],
  );

  if (!drawing) {
    return (
      <div className="chant-score chant-score--unavailable" role="note">
        <p>
          <strong>Notation unavailable</strong>
          <br />
          {(engraving as { error: string }).error}
        </p>
      </div>
    );
  }

  if (paged) {
    return (
      <div
        ref={host}
        className="chant-score chant-score--paged"
        style={{ width: drawing.width }}
      />
    );
  }

  return (
    <div
      ref={host}
      className="chant-score"
      style={{
        width: drawing.width,
        height: drawing.height,
        contentVisibility: "auto",
        containIntrinsicSize: `${drawing.width}px ${drawing.height}px`,
      }}
    >
      {buttons}
    </div>
  );
}
