import { Popover } from "@base-ui/react/popover";
import {
  Pause,
  Play,
  Repeat,
  SlidersHorizontal,
  Timer,
  TriangleAlert,
  X,
} from "lucide-react";
import { forwardRef, useEffect, useMemo } from "react";
import type { ChantScore } from "@/core/models.ts";
import { ChantPlaybackController } from "./controller.ts";
import {
  CantorGuideSounds,
  ChantRegisters,
  ScholaPitches,
  type CantorGuideSound,
  type ChantRegister,
  type ScholaPitch,
} from "./options.ts";
import { CantorGuideTitle } from "./title.ts";
import { usePlayback, usePlaybackState } from "./usePlayback.ts";

export interface CantorBarProps {
  score: ChantScore;
  onClose: () => void;
  /**
   * Set where the bar stands at the foot of a sheet rather than of the
   * window: it then takes its place in the sheet's own layout.
   */
  contained?: boolean;
}

// The three choices of voice, each a menu as in the native bar. They are
// offered again, with their names beside them, in Prayer options.

export function ScholaPitchSelect() {
  const playback = usePlayback();
  const state = usePlaybackState();
  return (
    <select
      aria-label="Schola pitch"
      value={state.scholaPitch}
      onChange={(event) => {
        playback.scholaPitch = Number(event.target.value) as ScholaPitch;
      }}
    >
      {ScholaPitches.allCases.map((pitch) => (
        <option key={pitch} value={pitch}>
          {ScholaPitches.displayName(pitch)}
        </option>
      ))}
    </select>
  );
}

export function ChantRegisterSelect() {
  const playback = usePlayback();
  const state = usePlaybackState();
  return (
    <select
      aria-label="Register"
      value={state.chantRegister}
      onChange={(event) => {
        playback.chantRegister = Number(event.target.value) as ChantRegister;
      }}
    >
      {ChantRegisters.allCases.map((register) => (
        <option key={register} value={register}>
          {ChantRegisters.displayName(register)}
        </option>
      ))}
    </select>
  );
}

export function CantorGuideSoundSelect() {
  const playback = usePlayback();
  const state = usePlaybackState();
  return (
    <select
      aria-label="Sound"
      value={state.guideSound}
      onChange={(event) => {
        playback.guideSound = event.target.value as CantorGuideSound;
      }}
    >
      {CantorGuideSounds.allCases.map((sound) => (
        <option key={sound} value={sound}>
          {CantorGuideSounds.displayName(sound)}
        </option>
      ))}
    </select>
  );
}

/**
 * How the cantor guide sings, behind the bar's options button: the tempo,
 * the voice, and in the reader the phrase sung again. It is a popover above
 * the button, as a web player's settings are, and goes away with Escape or a
 * press outside it.
 */
export function CantorOptions({
  score,
  offersLoop,
}: {
  score: ChantScore;
  offersLoop: boolean;
}) {
  const playback = usePlayback();
  const state = usePlaybackState();
  const range = ChantPlaybackController.tempoRange;
  return (
    <Popover.Root>
      <Popover.Trigger
        className="cantor-bar__button"
        aria-label="Cantor guide options"
      >
        <SlidersHorizontal aria-hidden="true" />
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Positioner
          className="cantor-options__positioner"
          side="top"
          align="end"
          sideOffset={10}
          collisionPadding={12}
        >
          <Popover.Popup className="cantor-options">
            <Popover.Title className="cantor-options__title">
              Cantor guide options
            </Popover.Title>
            <label className="cantor-options__tempo">
              <span className="cantor-options__label">
                <Timer aria-hidden="true" />
                Tempo
                <output>{Math.round(state.tempo * 100)}%</output>
              </span>
              <input
                type="range"
                aria-label="Tempo"
                min={range.lowerBound}
                max={range.upperBound}
                step={range.step}
                value={state.tempo}
                onChange={(event) => {
                  playback.tempo = Number(event.target.value);
                  playback.restartIfPlaying(score);
                }}
              />
            </label>
            <fieldset className="cantor-options__voice">
              <legend>Voice</legend>
              <label>
                <span>Schola pitch</span>
                <ScholaPitchSelect />
              </label>
              <label>
                <span>Register</span>
                <ChantRegisterSelect />
              </label>
              <label>
                <span>Sound</span>
                <CantorGuideSoundSelect />
              </label>
            </fieldset>
            {offersLoop && (
              <label className="cantor-options__loop">
                <input
                  type="checkbox"
                  checked={state.loopsPhrase}
                  onChange={(event) => {
                    playback.loopsPhrase = event.target.checked;
                    playback.restartIfPlaying(score);
                  }}
                />
                <Repeat aria-hidden="true" />
                Loop phrase
              </label>
            )}
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** Play or pause, the bar's one filled button. */
export function CantorPlayButton({ score }: { score: ChantScore }) {
  const playback = usePlayback();
  const state = usePlaybackState();
  return (
    <button
      type="button"
      className="cantor-bar__button cantor-bar__play"
      aria-label={state.isPlaying ? "Pause cantor guide" : "Play cantor guide"}
      onClick={() => playback.toggle(score)}
    >
      {state.isPlaying ? (
        <Pause aria-hidden="true" />
      ) : (
        <Play aria-hidden="true" />
      )}
    </button>
  );
}

/** Escape puts the guide away, unless a sheet or the options take it. */
export function useEscapeCloses(onClose: () => void) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented) return;
      if (document.querySelector('[role="dialog"]')) return;
      onClose();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [onClose]);
}

/**
 * The cantor guide at the foot of the reader while a chant is its subject:
 * one slim row with what is being sung, its options, play, and close.
 */
export const CantorBar = forwardRef<HTMLElement, CantorBarProps>(
  function CantorBar({ score, onClose, contained = false }, ref) {
    const state = usePlaybackState();
    const title = useMemo(() => CantorGuideTitle.text(score), [score]);
    useEscapeCloses(onClose);

    return (
      <aside
        ref={ref}
        className={
          contained ? "cantor-bar cantor-bar--contained" : "cantor-bar"
        }
        aria-label="Cantor guide"
      >
        <div className="cantor-bar__inner">
          <div className="cantor-bar__row">
            <p className="cantor-bar__score" lang="la">
              {title}
            </p>
            <CantorOptions score={score} offersLoop />
            <CantorPlayButton score={score} />
            <button
              type="button"
              className="cantor-bar__button"
              aria-label="Close cantor guide"
              onClick={onClose}
            >
              <X aria-hidden="true" />
            </button>
          </div>

          {state.errorMessage !== null && (
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
