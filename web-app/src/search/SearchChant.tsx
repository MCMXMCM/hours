import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { CantorBar } from "@/cantor/CantorBar.tsx";
import { usePlayback, usePlaybackState } from "@/cantor/usePlayback.ts";
import type { ChantScore } from "@/core/models.ts";
import { ChantScoreView } from "@/notation/ChantScoreView.tsx";
import {
  engrave,
  notationFontsReady,
  type EngravedNeume,
  type Engraving,
} from "@/notation/engraver.ts";

/** The narrowest column a chant is set in, and the space kept either side. */
const minimumWidth = 280;
const sidePadding = 16;

/** One chant setting of a search result, which can be sung from any neume. */
export default function SearchChant({
  score,
  opensPiece,
}: {
  score: ChantScore;
  /** Whether the chant is a piece the books open with an initial. */
  opensPiece: boolean;
}) {
  const playback = usePlayback();
  const cantor = usePlaybackState();
  const column = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [engraving, setEngraving] = useState<
    Engraving | { error: string } | null
  >(null);
  const [showsCantorGuide, setShowsCantorGuide] = useState(false);

  useLayoutEffect(() => {
    const element = column.current;
    if (!element) return;
    const measure = () =>
      setWidth(Math.round(element.getBoundingClientRect().width));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (width <= 0) return;
    let cancelled = false;
    void notationFontsReady().then(() => {
      if (cancelled) return;
      try {
        setEngraving(
          engrave(score, Math.max(minimumWidth, width - sidePadding * 2), {
            opensPiece,
          }),
        );
      } catch (error) {
        setEngraving({
          error: error instanceof Error ? error.message : String(error),
        });
      }
    });
    return () => {
      cancelled = true;
    };
  }, [opensPiece, score, width]);

  const selectNeume = useCallback(
    (neume: EngravedNeume) => {
      const eventID = neume.eventIDs[0];
      if (eventID === undefined) return;
      setShowsCantorGuide(true);
      playback.play(score, eventID);
    },
    [playback, score],
  );

  const closeCantorGuide = useCallback(() => {
    playback.stop();
    setShowsCantorGuide(false);
  }, [playback]);

  // Leaving the chant ends the guide.
  useEffect(() => () => playback.stop(), [playback]);

  const sungEventID = showsCantorGuide ? cantor.currentEventID : null;

  return (
    <div className="search-chant">
      <div ref={column} className="search-chant__score">
        {engraving ? (
          <ChantScoreView
            engraving={engraving}
            sungEventID={sungEventID}
            onSelectNeume={selectNeume}
          />
        ) : (
          <div className="search-empty" role="status" aria-label="Loading">
            <span className="spinner" />
          </div>
        )}
      </div>
      {showsCantorGuide && (
        <CantorBar score={score} onClose={closeCantorGuide} contained />
      )}
    </div>
  );
}
