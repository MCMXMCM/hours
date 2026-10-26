import { ArrowUpToLine, ChevronRight } from "lucide-react";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { usePlayback } from "@/cantor/usePlayback.ts";
import {
  ChantGuideDocuments,
  ChantGuideExamples,
  ChantGuideViewport,
  type ChantGuideViewportReason,
  type ChantGuideBlock,
  type ChantGuideDocument,
  type ChantGuideExample,
  type ChantGuideRect,
  type ChantGuideSection,
  type ChantGuideVariant,
} from "./chantGuideDocument.ts";
import { ChantGuideExampleView } from "./ChantGuideExampleView.tsx";
import { GuideBar } from "./GuideBar.tsx";
import { GuideCantorBar } from "./GuideCantorBar.tsx";
import { useOpensAtTop } from "./guideNavigation.ts";
import { useNotationFonts } from "./useGuide.ts";
import "./guides.css";

/** How long the page must lie still before the example in view is chosen. */
const scrollIdleDelay = 120;
/** Geometry also changes after engraving or text reflow; it is given this long to settle. */
const settleDelay = 180;
/** How long after a change of layout the page's movement is still its doing. */
const layoutScrollWindow = 1000;
/** A resize re-engraves every example; it is given this long to stop. */
const resizeDelay = 120;

/** The element that holds a block of the lesson, by which its place is told. */
function blockElementID(blockID: string): string {
  return `guide-block-${blockID}`;
}

function frame(element: Element): ChantGuideRect {
  const bounds = element.getBoundingClientRect();
  return {
    x: bounds.x,
    y: bounds.y,
    width: bounds.width,
    height: bounds.height,
  };
}

export interface ChantGuideLessonProps {
  document: ChantGuideDocument;
  section: ChantGuideSection;
  /** Returns to the guide's contents. */
  onBack: () => void;
}

/**
 * One lesson of the Guide to Chant: its prose and its examples, with the
 * cantor guide attending to whichever example is in view.
 */
export function ChantGuideLesson({
  document: guide,
  section,
  onBack,
}: ChantGuideLessonProps) {
  const playback = usePlayback();
  const fontsReady = useNotationFonts();
  const [selectedID, setSelectedID] = useState<string | null>(null);
  const [variants, setVariants] = useState<Record<string, string>>({
    "clef-staff-positions": "guide-clef-staff-positions-c4",
  });
  const [suppressed, setSuppressed] = useState(false);
  const [hasPresentedControls, setHasPresentedControls] = useState(false);
  const [width, setWidth] = useState(0);
  const bar = useRef<HTMLElement>(null);
  const reader = useRef<HTMLDivElement>(null);
  const controls = useRef<HTMLElement>(null);
  const isScrolling = useRef(false);
  // What the page's own events must read as it now is, not as it was when
  // they began to listen.
  const selected = useRef<string | null>(null);
  const chosen = useRef(variants);
  chosen.current = variants;

  useOpensAtTop();

  const variant = useCallback(
    (example: ChantGuideExample): ChantGuideVariant =>
      example.variants.find(
        (candidate) => candidate.id === chosen.current[example.id],
      ) ?? example.variants[0],
    [],
  );

  const select = useCallback(
    (example: ChantGuideExample, version = variant(example)) => {
      setHasPresentedControls(true);
      selected.current = example.id;
      setSelectedID(example.id);
      playback.prepare(
        version.score,
        ChantGuideExamples.pitchReference(example),
      );
    },
    [playback, variant],
  );

  /** The part of the window a lesson is read in: beneath its bar, above the guide's. */
  const readingViewport = useCallback((): ChantGuideRect => {
    const top = bar.current?.getBoundingClientRect().bottom ?? 0;
    const viewport = {
      x: 0,
      y: top,
      width: window.innerWidth,
      height: Math.max(0, window.innerHeight - top),
    };
    const controlsFrame = controls.current?.getBoundingClientRect();
    if (!controlsFrame || !(controlsFrame.height > 0)) return viewport;
    return {
      ...viewport,
      height: Math.max(
        0,
        Math.min(viewport.y + viewport.height, controlsFrame.top) - viewport.y,
      ),
    };
  }, []);

  const updateTarget = useCallback(
    (reason: ChantGuideViewportReason) => {
      if (window.document.hidden) return;
      const exampleFrames = new Map<string, ChantGuideRect>();
      for (const block of section.blocks) {
        if (block.exampleID === null) continue;
        const element = window.document.getElementById(
          blockElementID(block.id),
        );
        if (element) exampleFrames.set(block.exampleID, frame(element));
      }
      const target = ChantGuideViewport.target(
        exampleFrames,
        readingViewport(),
        ChantGuideViewport.retainedID(
          selected.current,
          playback.isPlaying,
          reason,
        ),
      );
      if (target === selected.current) return;
      playback.stop();
      selected.current = target;
      setSelectedID(target);
      const example =
        target === null ? null : ChantGuideDocuments.example(guide, target);
      if (example) select(example);
    },
    [guide, playback, readingViewport, section, select],
  );

  /** An example that has left the reader's view is not left singing. */
  const stopIfPlayingExampleLeft = useCallback(() => {
    if (!playback.isPlaying || selected.current === null) return;
    const block = section.blocks.find(
      (candidate) => candidate.exampleID === selected.current,
    );
    if (!block) return;
    const element = window.document.getElementById(blockElementID(block.id));
    if (
      !element ||
      !ChantGuideViewport.isVisible(frame(element), readingViewport())
    ) {
      playback.stop();
    }
  }, [playback, readingViewport, section]);

  // Nothing sung elsewhere follows the reader into a lesson, or out of it.
  useEffect(() => {
    playback.stop();
    return () => playback.stop();
  }, [playback]);

  useEffect(() => {
    const onVisibilityChange = () => {
      if (window.document.hidden) playback.stop();
    };
    window.document.addEventListener("visibilitychange", onVisibilityChange);
    return () =>
      window.document.removeEventListener(
        "visibilitychange",
        onVisibilityChange,
      );
  }, [playback]);

  // The notation is engraved for the column's width.
  useLayoutEffect(() => {
    const element = reader.current;
    if (!element) return;
    let timer: number | undefined;
    const measure = () =>
      setWidth(Math.round(element.getBoundingClientRect().width));
    measure();
    const observer = new ResizeObserver(() => {
      window.clearTimeout(timer);
      timer = window.setTimeout(measure, resizeDelay);
    });
    observer.observe(element);
    return () => {
      observer.disconnect();
      window.clearTimeout(timer);
    };
  }, []);

  // The example in view is chosen when the lesson opens, when the page comes
  // to rest, and when its layout has changed and settled.
  useEffect(() => {
    updateTarget("opened");

    // A browser also moves the page when its layout changes beneath the
    // reader, and reports that as scrolling. A movement that begins upon a
    // change of layout, with no touch of the reader's since, is the new
    // layout's; every other is the reader's own, and so is one the reader
    // lays a hand to before it has come to rest.
    let layoutMayMovePage = false;
    let layoutMovement: number | undefined;
    let scrollFollowsLayout = false;
    const onInput = () => {
      layoutMayMovePage = false;
      scrollFollowsLayout = false;
    };

    let idle: number | undefined;
    const onScroll = () => {
      if (!isScrolling.current) scrollFollowsLayout = layoutMayMovePage;
      isScrolling.current = true;
      stopIfPlayingExampleLeft();
      window.clearTimeout(idle);
      idle = window.setTimeout(() => {
        isScrolling.current = false;
        updateTarget(scrollFollowsLayout ? "layoutChanged" : "scrollEnded");
      }, scrollIdleDelay);
    };

    let settled: number | undefined;
    const onLayoutChange = () => {
      layoutMayMovePage = true;
      window.clearTimeout(layoutMovement);
      layoutMovement = window.setTimeout(() => {
        layoutMayMovePage = false;
      }, layoutScrollWindow);
      stopIfPlayingExampleLeft();
      window.clearTimeout(settled);
      settled = window.setTimeout(() => {
        if (!isScrolling.current) updateTarget("layoutChanged");
      }, settleDelay);
    };
    const observer = new ResizeObserver(onLayoutChange);
    if (reader.current) observer.observe(reader.current);

    const inputs = ["wheel", "touchstart", "touchmove", "keydown"] as const;
    for (const input of inputs) {
      window.addEventListener(input, onInput, { passive: true });
    }
    window.addEventListener("pointerdown", onInput, { passive: true });
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onLayoutChange);
    return () => {
      for (const input of inputs) window.removeEventListener(input, onInput);
      window.removeEventListener("pointerdown", onInput);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onLayoutChange);
      observer.disconnect();
      window.clearTimeout(idle);
      window.clearTimeout(settled);
      window.clearTimeout(layoutMovement);
    };
  }, [stopIfPlayingExampleLeft, updateTarget]);

  const closeControls = useCallback(() => {
    playback.stop();
    setSuppressed(true);
  }, [playback]);

  function blockView(block: ChantGuideBlock) {
    switch (block.kind) {
      case "prose":
        return (
          <section className="guide-prose">
            {block.title !== null && <h2>{block.title}</h2>}
            <div className="guide-prose__text">
              {(block.text ?? "").split("\n\n").map((paragraph, index) => (
                <p key={index}>{paragraph}</p>
              ))}
            </div>
          </section>
        );
      case "pronunciation":
        return (
          <details className="guide-disclosure guide-pronunciation">
            <summary>
              <span className="guide-disclosure__label">
                <span className="guide-pronunciation__title">
                  {block.title ?? "Pronunciation"}
                </span>
                <span className="guide-pronunciation__text">
                  {block.text ?? ""}
                </span>
              </span>
              <ChevronRight
                className="guide-disclosure__chevron"
                aria-hidden="true"
              />
            </summary>
            <p className="guide-pronunciation__detail">{block.detail ?? ""}</p>
          </details>
        );
      case "example": {
        const example =
          block.exampleID === null
            ? null
            : ChantGuideDocuments.example(guide, block.exampleID);
        if (!example) return null;
        return (
          <ChantGuideExampleView
            example={example}
            variant={variant(example)}
            width={Math.max(160, width)}
            fontsReady={fontsReady && width > 0}
            isSelected={selectedID === example.id}
            onVariant={(variantID) => {
              playback.stop();
              setVariants((current) => ({
                ...current,
                [example.id]: variantID,
              }));
              select(
                example,
                example.variants.find(
                  (candidate) => candidate.id === variantID,
                ) ?? example.variants[0],
              );
            }}
            onPlay={(eventID) => {
              setSuppressed(false);
              select(example);
              playback.play(variant(example).score, eventID);
            }}
            onPlayNote={(eventID) => {
              setSuppressed(false);
              select(example);
              playback.playNote(variant(example).score, eventID);
            }}
          />
        );
      }
    }
  }

  const showsControls = !suppressed && hasPresentedControls;
  const selectedExample =
    selectedID === null ? null : ChantGuideDocuments.example(guide, selectedID);

  return (
    <main className="guide" data-controls={showsControls ? "" : undefined}>
      <GuideBar
        ref={bar}
        title={section.title}
        label="Guide to Chant"
        onBack={onBack}
      >
        <button
          type="button"
          id="chant-guide-start"
          className="guide-bar__action"
          aria-label="Start from beginning"
          title="Start from beginning"
          onClick={() => {
            playback.stop();
            window.scrollTo(0, 0);
          }}
        >
          <ArrowUpToLine aria-hidden="true" />
        </button>
      </GuideBar>

      <div className="guide__column">
        <div ref={reader} id="chant-guide-reader" className="guide-lesson">
          <header className="guide-heading">
            <h1 id="chant-guide-lesson-title">{section.title}</h1>
            <p>Liber Usualis · {section.source}</p>
          </header>

          {section.blocks.map((block) => (
            <div key={block.id} id={blockElementID(block.id)}>
              {blockView(block)}
            </div>
          ))}
        </div>
      </div>

      {showsControls && (
        <GuideCantorBar
          ref={controls}
          score={selectedExample ? variant(selectedExample).score : null}
          onClose={closeControls}
        />
      )}
    </main>
  );
}
