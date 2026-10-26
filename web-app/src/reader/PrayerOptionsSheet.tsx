import { Printer, Type } from "lucide-react";
import {
  defaultNotationScale,
  notationScaleRange,
  readerLanguage,
  showsScores,
  type ReaderLanguage,
} from "@/app/appModel.ts";
import { useAppModel, useAppState } from "@/app/context.tsx";
import {
  CantorGuideSoundSelect,
  ChantRegisterSelect,
  ScholaPitchSelect,
} from "@/cantor/CantorBar.tsx";
import { SegmentedControl } from "@/components/SegmentedControl.tsx";
import { Sheet } from "@/components/Sheet.tsx";

export interface PrayerOptionsSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Whether the reader holds a Mass, which has neither the Office's
   * greetings for those present nor its psalmody. */
  isMass?: boolean;
}

const languages: ReadonlyArray<{ value: ReaderLanguage; title: string }> = [
  { value: "latin", title: "Latin" },
  { value: "both", title: "Both" },
  { value: "english", title: "English" },
];

/** How the open office is celebrated, shown, sung, and printed. */
export function PrayerOptionsSheet({
  open,
  onOpenChange,
  isMass = false,
}: PrayerOptionsSheetProps) {
  const model = useAppModel();
  const state = useAppState();
  const percent = Math.round(state.notationScale * 100);

  return (
    <Sheet
      open={open}
      onOpenChange={onOpenChange}
      title="Prayer options"
      closeLabel="Close Prayer Options"
    >
      <div className="form">
        {!isMass && (
          <section
            className="form__section"
            aria-labelledby="options-celebration"
          >
            <h3 id="options-celebration">Celebration</h3>
            <div className="form__group">
              <label className="form__row">
                <span>Priest or deacon present</span>
                <select
                  value={state.isPriestOrDeaconPresent ? "yes" : "no"}
                  onChange={(event) =>
                    model.setPriestOrDeaconPresent(event.target.value === "yes")
                  }
                >
                  <option value="no">No</option>
                  <option value="yes">Yes</option>
                </select>
              </label>
            </div>
          </section>
        )}

        <section className="form__section" aria-labelledby="options-display">
          <h3 id="options-display">Display</h3>
          <div className="form__group">
            <div className="form__row">
              <span aria-hidden="true">Text</span>
              <div className="form__segmented">
                <SegmentedControl
                  label="Text"
                  value={readerLanguage(state)}
                  options={languages}
                  onChange={(language) => model.setReaderLanguage(language)}
                />
              </div>
            </div>
            {/* The English alone has no chant to show. */}
            {state.showsLatin && (
              <label className="form__row">
                <span>Show chant</span>
                <input
                  type="checkbox"
                  role="switch"
                  className="switch"
                  checked={state.showsChant}
                  onChange={(event) =>
                    model.setShowsChant(event.target.checked)
                  }
                />
              </label>
            )}
            {isMass && (
              <>
                <label className="form__row">
                  <span>Show Ordinary</span>
                  <input
                    type="checkbox"
                    role="switch"
                    className="switch"
                    checked={state.showsMassOrdinary}
                    onChange={(event) =>
                      model.setShowsMassOrdinary(event.target.checked)
                    }
                  />
                </label>
                <p className="form__note">
                  Off, the Mass shows only its propers: the parts proper to the
                  day.
                </p>
              </>
            )}
            {!isMass && showsScores(state) && (
              <>
                <label className="form__row">
                  <span>Compact psalmody</span>
                  <input
                    type="checkbox"
                    role="switch"
                    className="switch"
                    checked={state.usesCompactPsalmody}
                    onChange={(event) =>
                      model.setUsesCompactPsalmody(event.target.checked)
                    }
                  />
                </label>
                <p className="form__note">
                  Show notation for the first verse, followed by pointed text
                  for the remaining verses.
                </p>
              </>
            )}
            <div className="form__row form__row--stacked">
              <div className="form__row-head">
                <span className="form__label-with-icon">
                  <Type aria-hidden="true" />
                  Reader size
                </span>
                <output>{percent}%</output>
              </div>
              <input
                type="range"
                aria-label="Reader size"
                min={notationScaleRange.minimum}
                max={notationScaleRange.maximum}
                step={notationScaleRange.step}
                value={state.notationScale}
                onChange={(event) =>
                  model.setNotationScale(Number(event.target.value))
                }
              />
            </div>
            <button
              type="button"
              className="form__button"
              disabled={state.notationScale === defaultNotationScale}
              onClick={() => model.setNotationScale(defaultNotationScale)}
            >
              Reset reader size
            </button>
          </div>
        </section>

        <section className="form__section" aria-labelledby="options-cantor">
          <h3 id="options-cantor">Cantor guide</h3>
          <div className="form__group">
            <label className="form__row">
              <span>Sound</span>
              <CantorGuideSoundSelect />
            </label>
            <label className="form__row">
              <span>Schola pitch</span>
              <ScholaPitchSelect />
            </label>
            <label className="form__row">
              <span>Register</span>
              <ChantRegisterSelect />
            </label>
          </div>
          <p className="form__footer">
            Choose the sampled harp, modeled organ, or simple pitch-pipe tone.
            The reciting tone is placed at the selected schola pitch and
            register.
          </p>
        </section>

        <section className="form__section" aria-labelledby="options-printing">
          <h3 id="options-printing">Printing</h3>
          <div className="form__group">
            <button
              type="button"
              className="form__button form__label-with-icon"
              onClick={() => {
                onOpenChange(false);
                window.setTimeout(() => window.print(), 300);
              }}
            >
              <Printer aria-hidden="true" />
              {isMass ? "Print this Mass" : "Print this hour"}
            </button>
          </div>
          <p className="form__footer">
            {isMass
              ? "Prints this Mass using the current display settings."
              : "Prints this hour using the current prayer and display settings."}
          </p>
        </section>
      </div>
    </Sheet>
  );
}
