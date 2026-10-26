import {
  ChevronRight,
  ChevronsUpDown,
  CircleMinus,
  CirclePlus,
  Pause,
  Play,
} from "lucide-react";
import {
  useCallback,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { usePlayback, usePlaybackState } from "@/cantor/usePlayback.ts";
import type { ChantScore } from "@/core/models.ts";
import { ChantScoreView } from "@/notation/ChantScoreView.tsx";
import type { EngravedNeume } from "@/notation/engraver.ts";
import {
  ChantGuideAnnotations,
  type ChantGuideAnnotation,
  type ChantGuideExample,
  type ChantGuideVariant,
} from "./chantGuideDocument.ts";
import {
  ChantGuideAnnotationOverlay,
  ChantGuideExampleViews,
  ChantGuideSolfege,
} from "./chantGuideExample.ts";
import { ChantGuideFormulaView } from "./ChantGuideFormulaView.tsx";
import {
  annotationMarks,
  prepareGuideScore,
  type GuideScorePreparation,
} from "./guideEngraving.ts";
import "./guides.css";

/** The notation an example shows, which stays until the next is ready. */
interface DisplayedGuideStave {
  readonly score: ChantScore;
  readonly preparation: GuideScorePreparation;
}

export interface ChantGuideExampleViewProps {
  example: ChantGuideExample;
  /** The version of the example now chosen. */
  variant: ChantGuideVariant;
  /** The width its notation is engraved for. */
  width: number;
  /** Whether the notation's typeface has loaded, so that engraving may begin. */
  fontsReady: boolean;
  /** Whether the cantor guide attends to this example. */
  isSelected: boolean;
  onVariant: (variantID: string) => void;
  /** Sings the example from one of its notes, or from its beginning. */
  onPlay: (eventID: string | null) => void;
  /** Sounds a single note of the example. */
  onPlayNote: (eventID: string) => void;
}

interface VariantSelectorProps {
  example: ChantGuideExample;
  variant: ChantGuideVariant;
  onVariant: (variantID: string) => void;
}

/**
 * The versions of an example as a menu. What is seen is the version now
 * chosen; the choice is made in the browser's own list, which lies over it.
 */
function VariantMenu({ example, variant, onVariant }: VariantSelectorProps) {
  return (
    <span className="guide-variants__menu">
      <span aria-hidden="true">{variant.title}</span>
      <ChevronsUpDown aria-hidden="true" />
      <select
        id={`guide-variant-${example.id}`}
        aria-label="Example version"
        value={variant.id}
        onChange={(event) => onVariant(event.target.value)}
      >
        {ChantGuideExampleViews.variantChoices(example).map((choice) => (
          <option key={choice.id} value={choice.id}>
            {choice.title}
          </option>
        ))}
      </select>
    </span>
  );
}

/**
 * The choice among an example's versions. A short comparison is set side by
 * side, and gives way to a menu where the column is too narrow for it; a
 * longer one is always a menu.
 */
function VariantSelector({
  example,
  variant,
  onVariant,
}: VariantSelectorProps) {
  const offersTabs = ChantGuideExampleViews.offersVariantTabs(example);
  const container = useRef<HTMLDivElement>(null);
  const tabs = useRef<HTMLDivElement>(null);
  const [fits, setFits] = useState(true);

  useLayoutEffect(() => {
    const region = container.current;
    const row = tabs.current;
    if (!offersTabs || !region || !row) return;
    const measure = () => setFits(row.offsetWidth <= region.clientWidth + 0.5);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(region);
    observer.observe(row);
    return () => observer.disconnect();
  }, [offersTabs, example]);

  if (!offersTabs) {
    return (
      <div className="guide-variants">
        <VariantMenu
          example={example}
          variant={variant}
          onVariant={onVariant}
        />
      </div>
    );
  }

  return (
    <div
      ref={container}
      className="guide-variants"
      data-menu={fits ? undefined : ""}
    >
      {/* The row stays in place, unseen, while the menu stands for it, so that its width can still be told. */}
      <div
        ref={tabs}
        className="guide-variants__tabs"
        role="group"
        aria-label={ChantGuideExampleViews.variantSelectorLabel(example)}
        data-hidden={fits ? undefined : ""}
        aria-hidden={fits ? undefined : true}
        inert={!fits}
      >
        {ChantGuideExampleViews.variantChoices(example).map((choice) => (
          <button
            key={choice.id}
            type="button"
            id={`guide-variant-tab-${choice.id}`}
            aria-label={choice.title}
            aria-pressed={choice.id === variant.id}
            onClick={() => onVariant(choice.id)}
          >
            {ChantGuideExampleViews.tabTitle(example, choice)}
          </button>
        ))}
      </div>
      {!fits && (
        <VariantMenu
          example={example}
          variant={variant}
          onVariant={onVariant}
        />
      )}
    </div>
  );
}

/**
 * One example of a lesson: its notation, which can be sung from any neume,
 * the versions it compares, and the notes it is made of.
 */
export function ChantGuideExampleView({
  example,
  variant,
  width,
  fontsReady,
  isSelected,
  onVariant,
  onPlay,
  onPlayNote,
}: ChantGuideExampleViewProps) {
  const playback = usePlayback();
  const cantor = usePlaybackState();
  const titleID = useId();
  const stave = useRef<HTMLDivElement>(null);
  const [displayed, setDisplayed] = useState<DisplayedGuideStave | null>(null);
  const [explores, setExplores] = useState(false);
  const [selectedAnnotation, setSelectedAnnotation] =
    useState<ChantGuideAnnotation | null>(null);
  const [selectedEventID, setSelectedEventID] = useState<string | null>(null);

  // A new version, or a new width, is engraved before it is shown; what was
  // marked upon the old notation is forgotten with it.
  useLayoutEffect(() => {
    if (!fontsReady || width <= 0) return;
    setSelectedEventID(null);
    setSelectedAnnotation(null);
    setDisplayed({
      score: variant.score,
      preparation: prepareGuideScore(variant.score, width),
    });
  }, [fontsReady, variant, width]);

  const isPlaying = isSelected && cantor.isPlaying;
  const engraving =
    displayed && !("error" in displayed.preparation)
      ? displayed.preparation
      : null;

  const highlightedEventID =
    isSelected && displayed && cantor.preparedScoreID === displayed.score.id
      ? cantor.currentEventID
      : null;
  const selectNeume = useCallback(
    (neume: EngravedNeume) => {
      const eventID = neume.eventIDs[0];
      if (eventID !== undefined) onPlay(eventID);
    },
    [onPlay],
  );

  const selectedIDs = useMemo(
    () =>
      selectedAnnotation?.eventIDs ??
      (selectedEventID !== null ? [selectedEventID] : []),
    [selectedAnnotation, selectedEventID],
  );

  const marks = useMemo(
    () =>
      explores && engraving && selectedIDs.length > 0
        ? annotationMarks(engraving, selectedIDs)
        : null,
    [engraving, explores, selectedIDs],
  );

  const selectedAnnotationID = selectedAnnotation
    ? ChantGuideAnnotations.id(selectedAnnotation)
    : null;

  return (
    <article
      id={`guide-example-${example.id}`}
      className="guide-example"
      aria-labelledby={titleID}
    >
      <div className="guide-example__head">
        <h2 id={titleID} className="guide-example__title">
          {example.title}
        </h2>
        <button
          type="button"
          id={`guide-play-${example.id}`}
          className="guide-example__play"
          aria-label={`${isPlaying ? "Pause" : "Play"} ${example.title}`}
          onClick={() => {
            if (isPlaying) playback.stop();
            else onPlay(null);
          }}
        >
          <span>
            {isPlaying ? (
              <Pause aria-hidden="true" />
            ) : (
              <Play aria-hidden="true" />
            )}
          </span>
        </button>
      </div>
      {example.caption !== variant.explanation && (
        <p className="guide-example__caption">{example.caption}</p>
      )}

      {example.variants.length > 1 && (
        <>
          {example.id === "modal-formulas" && (
            <p className="guide-example__selector-label">Rest On</p>
          )}
          <VariantSelector
            example={example}
            variant={variant}
            onVariant={onVariant}
          />
        </>
      )}
      {variant.formula && (
        <ChantGuideFormulaView notes={variant.formula} width={width} />
      )}

      <div
        ref={stave}
        className="guide-stave"
        data-exploring={explores ? "" : undefined}
      >
        {displayed ? (
          <div key={displayed.score.id} className="guide-stave__layer">
            <ChantScoreView
              engraving={displayed.preparation}
              sungEventID={highlightedEventID}
              onSelectNeume={selectNeume}
            />
            {marks && engraving && (
              <svg
                className="guide-stave__overlay"
                width={engraving.width}
                height={engraving.height}
                aria-hidden="true"
              >
                {marks.outlines.map((outline, index) => (
                  <rect
                    key={index}
                    {...outline}
                    rx={ChantGuideAnnotationOverlay.outset}
                  />
                ))}
                {marks.brackets.map((bracket, index) => (
                  <path
                    key={index}
                    d={`M${bracket.left} ${bracket.y + ChantGuideAnnotationOverlay.bracketDrop}V${bracket.y}H${bracket.right}V${bracket.y + ChantGuideAnnotationOverlay.bracketDrop}`}
                  />
                ))}
              </svg>
            )}
          </div>
        ) : (
          <div className="guide-stave__preparing" role="status">
            <span className="spinner" />
            <p>Preparing example…</p>
          </div>
        )}
      </div>

      <p className="guide-example__explanation">{variant.explanation}</p>
      <details
        className="guide-disclosure"
        open={explores}
        onToggle={(event) => setExplores(event.currentTarget.open)}
      >
        <summary id={`guide-explore-${example.id}`}>
          <span className="guide-example__explore-label">Explore notation</span>
          <ChevronRight
            className="guide-disclosure__chevron"
            aria-hidden="true"
          />
        </summary>
        <div className="guide-explore">
          <p className="guide-explore__hint">
            Singing order · select a note to hear it and locate it on the staff
          </p>
          <div className="guide-explore__notes">
            {variant.score.timeline.events.map((event, index) => (
              <button
                key={event.id}
                type="button"
                className="guide-note"
                aria-label={ChantGuideExampleViews.noteAccessibilityLabel(
                  index,
                  event,
                  variant.score,
                )}
                aria-description="Plays this note and highlights it on the staff"
                aria-pressed={selectedEventID === event.id}
                onClick={() => {
                  setSelectedEventID(event.id);
                  setSelectedAnnotation(null);
                  onPlayNote(event.id);
                }}
              >
                <span className="guide-note__number">{index + 1}</span>
                <span className="guide-note__name">
                  {ChantGuideSolfege.name(event, variant.score)}
                </span>
              </button>
            ))}
          </div>
          {variant.annotations.map((annotation) => {
            const id = ChantGuideAnnotations.id(annotation);
            const isOpen = selectedAnnotationID === id;
            return (
              <div key={id}>
                <button
                  type="button"
                  className="guide-annotation"
                  aria-expanded={isOpen}
                  onClick={() => {
                    setSelectedAnnotation(isOpen ? null : annotation);
                    setSelectedEventID(null);
                  }}
                >
                  {isOpen ? (
                    <CircleMinus aria-hidden="true" />
                  ) : (
                    <CirclePlus aria-hidden="true" />
                  )}
                  {annotation.label}
                </button>
                {isOpen && (
                  <p className="guide-annotation__explanation">
                    {annotation.explanation}
                  </p>
                )}
              </div>
            );
          })}
        </div>
      </details>
      <p className="guide-example__source">{example.source}</p>
    </article>
  );
}
