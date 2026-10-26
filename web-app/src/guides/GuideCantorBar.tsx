import { TriangleAlert, X } from "lucide-react";
import { forwardRef, useMemo } from "react";
import {
  CantorOptions,
  CantorPlayButton,
  useEscapeCloses,
} from "@/cantor/CantorBar.tsx";
import { CantorGuideTitle } from "@/cantor/title.ts";
import { usePlaybackState } from "@/cantor/usePlayback.ts";
import type { ChantScore } from "@/core/models.ts";
import "./guides.css";

export interface GuideCantorBarProps {
  /** The example the guide attends to, or null while none is in view. */
  score: ChantScore | null;
  onClose: () => void;
}

/**
 * The cantor guide beneath a lesson of the Guide to Chant: the reader's slim
 * bar, naming the example in view, with its options, play and close. The
 * lessons have no phrase to sing again. While no example is in view it says
 * how to find one.
 */
export const GuideCantorBar = forwardRef<HTMLElement, GuideCantorBarProps>(
  function GuideCantorBar({ score, onClose }, ref) {
    const state = usePlaybackState();
    const title = useMemo(
      () => (score ? CantorGuideTitle.text(score) : ""),
      [score],
    );
    useEscapeCloses(onClose);

    return (
      <aside
        ref={ref}
        className="cantor-bar guide-cantor-bar"
        aria-label="Cantor guide"
      >
        <div className="cantor-bar__inner">
          <div className="cantor-bar__row">
            {score ? (
              <>
                <p className="cantor-bar__score">{title}</p>
                <CantorOptions score={score} offersLoop={false} />
                <CantorPlayButton score={score} />
              </>
            ) : (
              <p className="guide-cantor-bar__prompt">
                Scroll to a musical example to listen.
              </p>
            )}
            <button
              type="button"
              className="cantor-bar__button"
              aria-label="Close cantor guide"
              onClick={onClose}
            >
              <X aria-hidden="true" />
            </button>
          </div>

          {score && state.errorMessage !== null && (
            <p className="cantor-bar__error" role="alert">
              <TriangleAlert aria-hidden="true" />
              {state.errorMessage}
            </p>
          )}
        </div>
      </aside>
    );
  },
);
