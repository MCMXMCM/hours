import type { ChantGuideFormulaNote } from "./chantGuideDocument.ts";
import { ChantGuideFormulaViews } from "./chantGuideExample.ts";
import "./guides.css";

export interface ChantGuideFormulaViewProps {
  notes: readonly ChantGuideFormulaNote[];
  /** The width of the column the formula is drawn across. */
  width: number;
}

/**
 * The notes of a rule upon a staff of their own. A hollow note is one the
 * rule supplies only when the words have a syllable for it.
 */
export function ChantGuideFormulaView({
  notes,
  width,
}: ChantGuideFormulaViewProps) {
  const height = ChantGuideFormulaViews.height;
  return (
    <figure className="guide-formula">
      <figcaption>Formula · hollow notes are used only when needed</figcaption>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label={ChantGuideFormulaViews.accessibilityLabel(notes)}
      >
        {ChantGuideFormulaViews.staffLines(width).map((line) => (
          <line key={line.y1} className="guide-formula__line" {...line} />
        ))}
        {ChantGuideFormulaViews.marks(notes, width).map((mark, index) => (
          <g key={index}>
            <rect
              className={
                mark.note.optional
                  ? "guide-formula__note guide-formula__note--optional"
                  : "guide-formula__note"
              }
              {...mark.rect}
            />
            <text
              x={mark.x}
              y={ChantGuideFormulaViews.labelY}
              textAnchor="middle"
              dominantBaseline="central"
            >
              {mark.note.label}
            </text>
          </g>
        ))}
      </svg>
    </figure>
  );
}
