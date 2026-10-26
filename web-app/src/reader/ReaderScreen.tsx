import { ChevronLeft, List, Settings2 } from "lucide-react";
import {
  Fragment,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { flushSync } from "react-dom";
import { useNavigate, useParams } from "react-router-dom";
import { readerLanguage, readerPage } from "@/app/appModel.ts";
import type { OfficeReaderScrollAnchor } from "@/app/launch.ts";
import { useAppModel, useAppState, useServices } from "@/app/context.tsx";
import { parseOfficeRoute } from "@/app/routes.ts";
import { CantorBar } from "@/cantor/CantorBar.tsx";
import { usePlayback, usePlaybackState } from "@/cantor/usePlayback.ts";
import {
  LocalDays,
  OfficeDocuments,
  OfficeHours,
  OfficeSectionKinds,
  type ChantScore,
  type OfficeDocument,
  type OfficeHour,
  type OfficeSection,
} from "@/core/models.ts";
import { notationFontsReady, type EngravedNeume } from "@/notation/engraver.ts";
import { OfficeHeader } from "./OfficeHeader.tsx";
import { OfficeSectionView } from "./OfficeSectionView.tsx";
import { OutlineSheet } from "./OutlineSheet.tsx";
import { PrayerOptionsSheet } from "./PrayerOptionsSheet.tsx";
import {
  CantorGuideViewportTracking,
  OfficeReaderPageTurn,
  OfficeReaderPresentation,
  type PartBounds,
  type ReaderPageName,
  type ReadingPlace,
} from "./presentation/index.ts";
import {
  prepareScores,
  samePreparation,
  type ScorePreparation,
  type ScorePreparationKey,
} from "./readerScores.ts";

/** The widest column the reader sets, as in the native app. */
const maximumColumnWidth = 820;
/** Space kept on either side of a staff. */
const scoreSidePadding = 12;
const topAnchorID = "office-top";
/**
 * The width of the column an office is printed in. It lies within the
 * margins of both A4 and US Letter paper.
 */
const printColumnWidth = 640;
/** The height of the reader's own bar, below which the office is read. */
const readerBarHeight = 56;
/** How long the page takes to bring the sung neume back into view. */
const followScrollDuration = 180;

/** Where the reader reads on a page, and the height of the line it was
 * read at. */
interface Reading {
  readonly place: ReadingPlace;
  readonly line: number;
}

/** The element of a part of a page: the Latin page's are the parts' own
 * IDs, the English page's are set apart from them. */
function pageElementID(page: ReaderPageName, id: string): string {
  return page === "latin" ? id : `english-${id}`;
}

function pagePanelID(page: ReaderPageName): string {
  return `reader-page-${page}`;
}

function pageTabID(page: ReaderPageName): string {
  return `reader-page-tab-${page}`;
}

/**
 * Where a reader was left in its document, and how it notes where it
 * stands: an Hour's place is kept by the model; a Mass keeps none.
 */
export interface ReaderPlace {
  restoredAnchor(): OfficeReaderScrollAnchor | null;
  restoredOffset(): number | null;
  remember(offset: number, anchor: OfficeReaderScrollAnchor | null): void;
}

/** The chant the cantor guide is singing, and the part of the office it stands in. */
interface SelectedScore {
  readonly score: ChantScore;
  readonly sectionID: string;
}

let followScroll = 0;

/** Moves the page by a distance, easing in and out as the native reader does. */
function scrollPageBy(distance: number): void {
  cancelAnimationFrame(followScroll);
  if (Math.abs(distance) < 1) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    window.scrollBy(0, distance);
    return;
  }
  const from = window.scrollY;
  const began = performance.now();
  const step = (now: number) => {
    const progress = Math.min(1, (now - began) / followScrollDuration);
    const eased =
      progress < 0.5
        ? 2 * progress * progress
        : 1 - (-2 * progress + 2) ** 2 / 2;
    window.scrollTo(0, from + distance * eased);
    if (progress < 1) followScroll = requestAnimationFrame(step);
  };
  followScroll = requestAnimationFrame(step);
}

interface PreparedOfficeScores {
  readonly key: ScorePreparationKey;
  readonly scores: Map<string, ScorePreparation>;
}

function useColumnWidth(): [React.RefObject<HTMLDivElement | null>, number] {
  const column = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const element = column.current;
    if (!element) return;
    let timer: number | undefined;
    const measure = () =>
      setWidth(Math.round(element.getBoundingClientRect().width));
    measure();
    const observer = new ResizeObserver(() => {
      // A resize re-engraves every score; wait until it has stopped.
      window.clearTimeout(timer);
      timer = window.setTimeout(measure, 120);
    });
    observer.observe(element);
    return () => {
      observer.disconnect();
      window.clearTimeout(timer);
    };
  }, []);
  return [column, width];
}

export function Reader({
  office,
  skyHour = office.hour,
  place,
  title,
  titleEnglish,
  onClose,
  header,
}: {
  office: OfficeDocument;
  /** The Hour whose light the reader takes: the Hour read unless another is
   * given, as a Mass takes the Hour chosen on Home. */
  skyHour?: OfficeHour;
  /** Where the reader was left, and how it remembers; none, it opens at
   * the head of its document and keeps no place. */
  place?: ReaderPlace;
  /** The bar's title: the Hour's Latin name unless another is given. */
  title?: string;
  /** The bar's title where the English is shown alone: the Hour's English
   * name unless another is given. */
  titleEnglish?: string;
  onClose?: () => void;
  /** What stands above the document's own header (the choice of a day's Masses). */
  header?: ReactNode;
}) {
  const model = useAppModel();
  const state = useAppState();
  const navigate = useNavigate();
  const isMass = OfficeDocuments.isMass(office);
  // The words a priest or deacon says in place of the lay forms stand in
  // the Office as Prayer options say; never in the Mass, whose celebrant
  // the Missal's own words already suppose.
  const isPriestOrDeaconPresent = isMass
    ? false
    : state.isPriestOrDeaconPresent;
  const [column, columnWidth] = useColumnWidth();
  const [prepared, setPrepared] = useState<PreparedOfficeScores | null>(null);
  const [showsOutline, setShowsOutline] = useState(false);
  const [showsOptions, setShowsOptions] = useState(false);
  const restored = useRef(false);
  const playback = usePlayback();
  const cantor = usePlaybackState();
  const [selected, setSelected] = useState<SelectedScore | null>(null);
  const cantorBar = useRef<HTMLElement>(null);
  const automaticScrollTarget = useRef<string | null>(null);

  // Both languages are read on two pages, the Latin and the English, and
  // either language alone on its one page.
  const language = readerLanguage(state);
  const isPaged = language === "both";
  const shownPage = readerPage(state);

  // While the office is laid out for paper its chant is engraved for the
  // paper's column, whatever the width of the window. Paper cannot be
  // turned: with both languages chosen the Latin is printed with its
  // English beneath.
  const [isPrinting, setIsPrinting] = useState(false);

  // A page is laid out when it is first shown, and kept while both
  // languages are read, out of sight while the other is shown.
  const [laidOut, setLaidOut] = useState<ReadonlySet<ReaderPageName>>(
    () => new Set([shownPage]),
  );
  if (!laidOut.has(shownPage)) {
    setLaidOut(new Set(isPaged ? [...laidOut, shownPage] : [shownPage]));
  }
  const pages: readonly ReaderPageName[] = isPaged
    ? (["latin", "english"] as const).filter(
        // Paper is printed from the Latin page, laid out for it if need be.
        (page) => laidOut.has(page) || (isPrinting && page === "latin"),
      )
    : [shownPage];

  // The Latin page, sung where its chant is shown, prepared wherever the
  // Latin is read, as its chant is engraved before it is first turned to;
  // and the English page, which has no chant, as the English alone has
  // none, prepared once it is laid out. Writing out the words of the chant
  // for the English page reads every score again.
  const latinPresentation = useMemo(
    () =>
      state.showsLatin
        ? OfficeReaderPresentation.prepare(
            office,
            state.usesCompactPsalmody,
            state.showsMassOrdinary,
            state.showsChant,
          )
        : null,
    [
      office,
      state.showsLatin,
      state.usesCompactPsalmody,
      state.showsMassOrdinary,
      state.showsChant,
    ],
  );
  // The page shown counts as laid out in the render that lays it out.
  const laysOutEnglish = shownPage === "english" || pages.includes("english");
  const englishPresentation = useMemo(
    () =>
      laysOutEnglish
        ? OfficeReaderPresentation.prepare(
            office,
            state.usesCompactPsalmody,
            state.showsMassOrdinary,
            false,
          )
        : null,
    [
      laysOutEnglish,
      office,
      state.usesCompactPsalmody,
      state.showsMassOrdinary,
    ],
  );
  // The chant engraved is the Latin page's, where the Latin is read. One
  // language at least is shown, and its page is laid out.
  const presentation = (latinPresentation ?? englishPresentation)!;
  // The scores that open a piece, and so take an initial.
  const pieceScoreIDs = useMemo(
    () =>
      new Set(
        presentation.sections.flatMap((section) =>
          section.chant && OfficeSectionKinds.opensPiece(section.kind)
            ? [section.chant.id]
            : [],
        ),
      ),
    [presentation.sections],
  );
  /** The presentation of a page laid out (`pages`). */
  const pagePresentation = useCallback(
    (page: ReaderPageName) =>
      (page === "latin" ? latinPresentation : englishPresentation)!,
    [englishPresentation, latinPresentation],
  );

  const scoreWidth = isPrinting
    ? printColumnWidth - scoreSidePadding * 2
    : Math.max(
        0,
        Math.min(columnWidth, maximumColumnWidth) - scoreSidePadding * 2,
      );
  const preparationKey: ScorePreparationKey = useMemo(
    () => ({
      officeID: office.id,
      scoreSignature: presentation.scoreSignature,
      width: scoreWidth,
      scale: Math.round(state.notationScale * 100) / 100,
    }),
    [office.id, presentation.scoreSignature, scoreWidth, state.notationScale],
  );

  const preparedScores = useRef(prepared);
  preparedScores.current = prepared;

  useEffect(() => {
    if (preparationKey.width <= 0) return;
    // Already engraved for this column, as it is on the way to and from paper.
    if (samePreparation(preparedScores.current?.key ?? null, preparationKey)) {
      return;
    }
    let cancelled = false;
    void notationFontsReady().then(() => {
      if (cancelled) return;
      // Let the "preparing" state paint before the staves are drawn.
      window.setTimeout(() => {
        if (cancelled) return;
        setPrepared({
          key: preparationKey,
          scores: prepareScores(
            presentation.scores,
            preparationKey.width,
            preparationKey.scale,
            pieceScoreIDs,
          ),
        });
      }, 0);
    });
    return () => {
      cancelled = true;
    };
  }, [pieceScoreIDs, preparationKey, presentation.scores]);

  const isReady =
    prepared !== null && samePreparation(prepared.key, preparationKey);

  // MARK: Printing

  // Staves engraved for the window would be cut off by a narrower page, and
  // a chant drawn as one piece cannot be divided between two pages. Before
  // the browser lays the office out for paper its chant is engraved again
  // for the paper's column, each staff a piece of its own; afterwards the
  // drawings made for the window are put back as they were.
  useEffect(() => {
    let screen: PreparedOfficeScores | null = null;
    let title: string | null = null;
    const beforePrint = () => {
      if (title !== null) return;
      const key: ScorePreparationKey = {
        officeID: office.id,
        scoreSignature: presentation.scoreSignature,
        width: printColumnWidth - scoreSidePadding * 2,
        scale: Math.round(state.notationScale * 100) / 100,
      };
      screen = preparedScores.current;
      title = document.title;
      flushSync(() => {
        setPrepared({
          key,
          // Paper is drawn on where the lines fall, at no screen's pixels.
          scores: prepareScores(
            presentation.scores,
            key.width,
            key.scale,
            pieceScoreIDs,
            null,
          ),
        });
        setIsPrinting(true);
      });
      // The name a saved copy is given, as the native app names its print job.
      document.title = `${OfficeDocuments.englishName(office)} \u{2014} ${LocalDays.description(office.date)}`;
    };
    const afterPrint = () => {
      if (title === null) return;
      document.title = title;
      title = null;
      const restoredScreen = screen;
      screen = null;
      flushSync(() => {
        if (restoredScreen) setPrepared(restoredScreen);
        setIsPrinting(false);
      });
    };
    window.addEventListener("beforeprint", beforePrint);
    window.addEventListener("afterprint", afterPrint);
    return () => {
      window.removeEventListener("beforeprint", beforePrint);
      window.removeEventListener("afterprint", afterPrint);
      if (title !== null) document.title = title;
    };
  }, [
    isMass,
    office.date,
    office.hour,
    office.id,
    pieceScoreIDs,
    presentation.scoreSignature,
    presentation.scores,
    state.notationScale,
  ]);

  // MARK: Place in the office

  /** The element of a section, or of the head, on a page. */
  const elementOf = useCallback(
    (page: ReaderPageName, sectionID: string) =>
      document.getElementById(pageElementID(page, sectionID)),
    [],
  );

  /** Where the reader stands on a page: the first part whose foot lies
   * below the bar, and how far its top lies from the bar's foot. */
  const anchorOn = useCallback(
    (page: ReaderPageName) => {
      const top = readerBarHeight;
      const ids = [
        topAnchorID,
        ...pagePresentation(page).sections.map((section) => section.id),
      ];
      for (const id of ids) {
        const element = elementOf(page, id);
        if (!element) continue;
        const bounds = element.getBoundingClientRect();
        if (bounds.bottom > top) {
          return { sectionID: id, offset: bounds.top - top };
        }
      }
      return null;
    },
    [elementOf, pagePresentation],
  );

  /** Brings a page to a place it was left at: the part's top at the
   * height it stood. */
  const standAt = useCallback(
    (page: ReaderPageName, place: OfficeReaderScrollAnchor | null) => {
      if (!place) return false;
      const element = elementOf(page, place.sectionID);
      if (!element) return false;
      window.scrollTo(
        0,
        window.scrollY +
          element.getBoundingClientRect().top -
          readerBarHeight -
          place.offset,
      );
      return true;
    },
    [elementOf, pagePresentation],
  );

  /** The tops and feet of a page's parts on the screen, its head first. */
  const partsOn = useCallback(
    (page: ReaderPageName) => {
      const parts = new Map<string, PartBounds>();
      for (const id of [
        topAnchorID,
        ...pagePresentation(page).sections.map((section) => section.id),
      ]) {
        const bounds = elementOf(page, id)?.getBoundingClientRect();
        if (bounds) parts.set(id, { top: bounds.top, bottom: bounds.bottom });
      }
      return parts;
    },
    [elementOf, pagePresentation],
  );

  /** The reading line, a quarter of the way down the reading area. */
  const readingLine = () =>
    readerBarHeight +
    OfficeReaderPageTurn.readingLineFraction *
      (window.innerHeight - readerBarHeight);

  /** Where the reader reads on a page, and the line it is read at: the
   * other page is set by the same line, though the window's height change
   * meanwhile, as a browser's bars come and go. */
  const readingPlaceOn = useCallback(
    (page: ReaderPageName): Reading | null => {
      const line = readingLine();
      const place = OfficeReaderPageTurn.readingPlace(partsOn(page), line);
      return place ? { place, line } : null;
    },
    [partsOn],
  );

  /** Brings a page to the words read on the other: the same words at the
   * reading line, however much longer or shorter this page sets them. */
  const readAt = useCallback(
    (page: ReaderPageName, reading: Reading | null) => {
      if (!reading) return false;
      const placed = OfficeReaderPageTurn.placement(
        reading.place,
        partsOn(page),
        reading.line,
      );
      const element = placed ? elementOf(page, placed.sectionID) : null;
      if (!placed || !element) return false;
      window.scrollTo(
        0,
        window.scrollY + element.getBoundingClientRect().top - placed.top,
      );
      return true;
    },
    [elementOf, partsOn],
  );

  const latestAnchor = useRef<OfficeReaderScrollAnchor | null>(null);
  const latestReading = useRef<Reading | null>(null);
  useEffect(() => {
    if (!isReady || isPrinting) return;
    let timer: number | undefined;
    const remember = () => {
      latestAnchor.current = anchorOn(shownPage);
      latestReading.current = readingPlaceOn(shownPage);
      place?.remember(window.scrollY, latestAnchor.current);
    };
    const onScroll = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(remember, 160);
    };
    const onHide = () => {
      if (document.hidden) remember();
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    document.addEventListener("visibilitychange", onHide);
    window.addEventListener("pagehide", remember);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener("scroll", onScroll);
      document.removeEventListener("visibilitychange", onHide);
      window.removeEventListener("pagehide", remember);
    };
  }, [anchorOn, isPrinting, isReady, place, readingPlaceOn, shownPage]);

  // An office opens at its head, unless the reader is returning to it.
  useLayoutEffect(() => {
    if (!isReady || restored.current) return;
    restored.current = true;
    if (!standAt(shownPage, place?.restoredAnchor() ?? null)) {
      window.scrollTo(0, place?.restoredOffset() ?? 0);
    }
  }, [isReady, place, shownPage, standAt]);

  // Re-engraving at a new size or width must not lose the reader's place.
  // The place is the one last noted while reading: once the staves have been
  // taken down there is nothing left to measure it by.
  const held = useRef<OfficeReaderScrollAnchor | null>(null);
  useEffect(() => {
    if (isReady) return;
    held.current = restored.current ? latestAnchor.current : null;
  }, [isReady, preparationKey]);
  useLayoutEffect(() => {
    if (!isReady || !held.current) return;
    standAt(shownPage, held.current);
    held.current = null;
  }, [isReady, prepared, shownPage, standAt]);

  // A page shown in place of another, by a turn or by the language
  // chosen, shows the words read on the other at the reading line before
  // it is painted; a turn slides it in, or, with reduced motion, fades it in.
  const shownBefore = useRef(shownPage);
  const pendingTurn = useRef<Reading | null>(null);
  if (shownBefore.current !== shownPage && pendingTurn.current === null) {
    pendingTurn.current = latestReading.current;
  }
  const settling = useRef<() => void>(() => {});
  useEffect(() => () => settling.current(), []);
  useLayoutEffect(() => {
    const from = shownBefore.current;
    if (from === shownPage) return;
    shownBefore.current = shownPage;
    const place = pendingTurn.current;
    pendingTurn.current = null;
    if (!isReady) return;
    readAt(shownPage, place);
    latestAnchor.current = anchorOn(shownPage);
    // A page just laid out still settles after its first layout (a verse
    // breaks at its pause once it is measured): the place is kept for a
    // few frames more, until the reader moves the page.
    settling.current();
    let frame = 0;
    let request = 0;
    const stop = () => {
      cancelAnimationFrame(request);
      window.removeEventListener("wheel", stop);
      window.removeEventListener("touchstart", stop);
      window.removeEventListener("keydown", stop);
      settling.current = () => {};
    };
    const keep = () => {
      readAt(shownPage, place);
      latestAnchor.current = anchorOn(shownPage);
      latestReading.current = readingPlaceOn(shownPage);
      frame += 1;
      if (frame < 12) {
        request = requestAnimationFrame(keep);
      } else {
        stop();
      }
    };
    window.addEventListener("wheel", stop, { passive: true });
    window.addEventListener("touchstart", stop, { passive: true });
    window.addEventListener("keydown", stop);
    settling.current = stop;
    request = requestAnimationFrame(keep);
    if (!isPaged) return;
    const element = document.getElementById(pagePanelID(shownPage));
    const reduced = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const across = shownPage === "english" ? 24 : -24;
    element?.animate?.(
      reduced
        ? [{ opacity: 0 }, { opacity: 1 }]
        : [
            { opacity: 0, transform: `translateX(${across}px)` },
            { opacity: 1, transform: "none" },
          ],
      { duration: reduced ? 180 : 220, easing: "ease-out" },
    );
  }, [anchorOn, isPaged, isReady, readAt, readingPlaceOn, shownPage]);

  const jumpTo = useCallback(
    (sectionID: string) => {
      const element = elementOf(shownPage, sectionID);
      if (!element) return;
      window.scrollTo(
        0,
        window.scrollY + element.getBoundingClientRect().top - readerBarHeight,
      );
    },
    [elementOf, shownPage],
  );

  const close = () => {
    if (onClose) {
      onClose();
      return;
    }
    model.endReaderSession();
    navigate("/");
  };

  // MARK: Cantor guide

  const selectNeume = useCallback(
    (section: OfficeSection, score: ChantScore, neume: EngravedNeume) => {
      const eventID = neume.eventIDs[0];
      if (eventID === undefined) return;
      automaticScrollTarget.current = null;
      setSelected({ score, sectionID: section.id });
      playback.play(score, eventID);
    },
    [playback],
  );

  const closeCantorGuide = useCallback(() => {
    playback.stop();
    setSelected(null);
    automaticScrollTarget.current = null;
  }, [playback]);

  // Leaving the office ends the guide.
  useEffect(() => () => playback.stop(), [playback]);

  const sungEventID = selected ? cantor.currentEventID : null;

  // Keep the neume being sung in view, above the guide's bar.
  useEffect(() => {
    const active =
      selected && sungEventID
        ? elementOf("latin", selected.sectionID)?.querySelector<HTMLElement>(
            ".chant-score__neume[data-sung]",
          )
        : null;
    const bar = cantorBar.current;
    if (!selected || !active) {
      automaticScrollTarget.current = null;
      return;
    }
    if (!bar) return;
    const frame = active.getBoundingClientRect();
    const readerFrame = {
      x: 0,
      y: readerBarHeight,
      width: window.innerWidth,
      height: window.innerHeight - readerBarHeight,
    };
    const anchorY = CantorGuideViewportTracking.scrollAnchorY(
      frame,
      readerFrame,
      Math.max(0, window.innerHeight - bar.getBoundingClientRect().top),
    );
    if (anchorY === null) {
      automaticScrollTarget.current = null;
      return;
    }
    const target = `cantor-scroll-${selected.score.id}-${active.dataset.neume}`;
    if (automaticScrollTarget.current === target) return;
    automaticScrollTarget.current = target;
    // The same point of the neume and of the reader are brought together.
    scrollPageBy(
      frame.top +
        anchorY * frame.height -
        (readerFrame.y + anchorY * readerFrame.height),
    );
  }, [elementOf, selected, sungEventID]);

  // MARK: Turning the page

  /** Turns to a page, from the tabs, the keys or a swipe. The Cantor Guide,
   * which sings from the Latin page, is closed first. */
  const turn = useCallback(
    (page: ReaderPageName) => {
      if (!isPaged || page === shownPage) return;
      if (selected) closeCantorGuide();
      pendingTurn.current = readingPlaceOn(shownPage);
      model.turnReaderPage(page);
    },
    [closeCantorGuide, isPaged, model, readingPlaceOn, selected, shownPage],
  );

  // The left and right arrows turn back to the Latin and on to the English,
  // where nothing else that has the keyboard takes them.
  useEffect(() => {
    if (!isPaged) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (
        event.defaultPrevented ||
        event.altKey ||
        event.ctrlKey ||
        event.metaKey ||
        event.shiftKey ||
        (event.key !== "ArrowLeft" && event.key !== "ArrowRight") ||
        showsOutline ||
        showsOptions
      ) {
        return;
      }
      const target = event.target as Element | null;
      if (
        target?.closest(
          "input, select, textarea, [contenteditable], [role=slider], [role=dialog]",
        )
      ) {
        return;
      }
      event.preventDefault();
      turn(event.key === "ArrowRight" ? "english" : "latin");
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [isPaged, showsOptions, showsOutline, turn]);

  // A swipe across the page turns it: begun away from either edge, which
  // the browser keeps for its own swipes back and forward, and clearly
  // horizontal; the browser scrolls whatever runs nearer the vertical, and
  // the page keeps its own vertical scrolling (`touch-action`).
  useEffect(() => {
    const area = column.current;
    if (!isPaged || selected || !area) return;
    let drag: { id: number; x: number; y: number; time: number } | null = null;
    const onDown = (event: PointerEvent) => {
      if (
        event.pointerType !== "touch" ||
        !event.isPrimary ||
        !OfficeReaderPageTurn.beginsAwayFromEdges(
          event.clientX,
          window.innerWidth,
        )
      ) {
        drag = null;
        return;
      }
      drag = {
        id: event.pointerId,
        x: event.clientX,
        y: event.clientY,
        time: event.timeStamp,
      };
    };
    const onUp = (event: PointerEvent) => {
      if (!drag || event.pointerId !== drag.id) return;
      const { x, y, time } = drag;
      drag = null;
      // A selection being made or extended is not a turn.
      if (window.getSelection()?.isCollapsed === false) return;
      const page = OfficeReaderPageTurn.turnedTo(
        shownPage,
        event.clientX - x,
        event.clientY - y,
        event.timeStamp - time,
        window.innerWidth,
      );
      if (page) turn(page);
    };
    const onCancel = () => {
      drag = null;
    };
    area.addEventListener("pointerdown", onDown, { passive: true });
    area.addEventListener("pointerup", onUp, { passive: true });
    area.addEventListener("pointercancel", onCancel, { passive: true });
    return () => {
      area.removeEventListener("pointerdown", onDown);
      area.removeEventListener("pointerup", onUp);
      area.removeEventListener("pointercancel", onCancel);
    };
  }, [column, isPaged, selected, shownPage, turn]);

  const pageTabs = useRef<HTMLDivElement>(null);
  const onTabKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const page: ReaderPageName | null =
      event.key === "ArrowRight" || event.key === "End"
        ? "english"
        : event.key === "ArrowLeft" || event.key === "Home"
          ? "latin"
          : null;
    if (!page) return;
    event.preventDefault();
    turn(page);
    pageTabs.current
      ?.querySelector<HTMLElement>(`#${pageTabID(page)}`)
      ?.focus();
  };

  const renderPage = (page: ReaderPageName) => {
    // On paper, the Latin page carries the English beneath it.
    const isCombined = isPrinting && isPaged && page === "latin";
    const showsLatin = page === "latin";
    const showsEnglish = page === "english" || isCombined;
    const sections = pagePresentation(page).sections;
    return (
      <>
        <OfficeHeader
          office={office}
          showsLatin={showsLatin}
          showsEnglish={showsEnglish}
          elementID={pageElementID(page, topAnchorID)}
        />
        {sections.length === 0 ? (
          <p className="reader__status">Office text coming soon</p>
        ) : (
          sections.map((section, index) => (
            <OfficeSectionView
              key={section.id}
              section={section}
              elementID={pageElementID(page, section.id)}
              isMass={isMass}
              isFollowedByContinuation={
                index + 1 < sections.length &&
                sections[index + 1].title.length === 0
              }
              showsEnglish={showsEnglish}
              showsLatin={showsLatin}
              showsChant={state.showsChant}
              usesCompactPsalmody={state.usesCompactPsalmody}
              isPriestOrDeaconPresent={isPriestOrDeaconPresent}
              scorePreparation={
                section.chant && showsLatin
                  ? (prepared!.scores.get(section.chant.id) ?? null)
                  : null
              }
              sungEventID={
                showsLatin && selected?.sectionID === section.id
                  ? sungEventID
                  : null
              }
              paged={isPrinting}
              onSelectNeume={selectNeume}
            />
          ))
        )}
      </>
    );
  };

  return (
    <div
      className={isPaged ? "reader reader--paged" : "reader"}
      style={{ ["--reader-scale" as string]: state.notationScale }}
      data-hour={skyHour}
      data-cantor={selected ? "" : undefined}
    >
      <nav className="reader__bar" aria-label="Office">
        <button
          type="button"
          className="icon-button"
          aria-label="Back"
          onClick={close}
        >
          <ChevronLeft aria-hidden="true" />
        </button>
        <div className="reader__bar-heading">
          <p
            className="reader__bar-title"
            lang={shownPage === "latin" ? "la" : "en"}
          >
            {shownPage === "latin"
              ? (title ?? OfficeHours.latinTitle(office.hour))
              : (titleEnglish ?? OfficeHours.englishTitle(office.hour))}
          </p>
          {isPaged && (
            <div
              ref={pageTabs}
              role="tablist"
              aria-label="Page"
              className="reader__pages"
              onKeyDown={onTabKeyDown}
            >
              {(["latin", "english"] as const).map((page) => (
                <Fragment key={page}>
                  {page === "english" && (
                    <span
                      className="reader__pages-separator"
                      aria-hidden="true"
                    >
                      ·
                    </span>
                  )}
                  <button
                    type="button"
                    role="tab"
                    id={pageTabID(page)}
                    className="reader__page-tab"
                    aria-selected={page === shownPage}
                    aria-controls={pagePanelID(page)}
                    tabIndex={page === shownPage ? 0 : -1}
                    onClick={() => turn(page)}
                  >
                    {page === "latin" ? "Latin" : "English"}
                  </button>
                </Fragment>
              ))}
            </div>
          )}
        </div>
        <div className="reader__bar-actions">
          <button
            type="button"
            className="icon-button icon-button--quiet"
            aria-label="Office sections"
            onClick={() => setShowsOutline(true)}
          >
            <List aria-hidden="true" />
          </button>
          <button
            type="button"
            className="icon-button icon-button--quiet"
            aria-label="Prayer options"
            onClick={() => setShowsOptions(true)}
          >
            <Settings2 aria-hidden="true" />
          </button>
        </div>
      </nav>

      <div ref={column} className="reader__column">
        {header}
        {isReady ? (
          pages.map((page) => (
            <div
              key={page}
              id={pagePanelID(page)}
              className="reader__page"
              role={isPaged ? "tabpanel" : undefined}
              aria-labelledby={isPaged ? pageTabID(page) : undefined}
              lang={page === "latin" ? undefined : "en"}
              hidden={
                isPrinting && isPaged ? page !== "latin" : page !== shownPage
              }
            >
              {renderPage(page)}
            </div>
          ))
        ) : (
          <div className="reader__status" role="status">
            <span className="spinner" />
            <p>Preparing chant notation…</p>
          </div>
        )}
      </div>

      <OutlineSheet
        open={showsOutline}
        onOpenChange={setShowsOutline}
        entries={pagePresentation(shownPage).outlineEntries}
        onSelect={(sectionID) => {
          setShowsOutline(false);
          // Jump once the sheet has gone, so the page is free to move.
          window.setTimeout(() => jumpTo(sectionID), 220);
        }}
      />
      <PrayerOptionsSheet
        open={showsOptions}
        onOpenChange={setShowsOptions}
        isMass={isMass}
      />
      {selected && (
        <CantorBar
          ref={cantorBar}
          score={selected.score}
          onClose={closeCantorGuide}
        />
      )}
    </div>
  );
}

/** The office reader, at `/office/:date/:hour`. */
export default function ReaderScreen() {
  const params = useParams();
  const navigate = useNavigate();
  const model = useAppModel();
  const state = useAppState();
  const { appearance } = useServices();
  const route = useMemo(
    () => parseOfficeRoute(params.date, params.hour),
    [params.date, params.hour],
  );

  useEffect(() => {
    if (!route) {
      navigate("/", { replace: true });
      return;
    }
    void model.start().then(() => model.selectOffice(route.day, route.hour));
  }, [model, navigate, route]);

  const office =
    route &&
    state.office &&
    LocalDays.equals(state.office.date, route.day) &&
    state.office.hour === route.hour
      ? state.office
      : null;

  useEffect(() => {
    if (!office) return;
    model.beginReaderSession(office);
    // In the reader the appearance follows the open office's hour.
    appearance.setDisplayedHour(office.hour);
  }, [appearance, model, office]);

  // An Hour keeps its place in the reader session.
  const place = useMemo<ReaderPlace | undefined>(
    () =>
      office
        ? {
            restoredAnchor: () => model.restoredReaderScrollAnchor(office),
            restoredOffset: () => model.restoredReaderScrollOffset(office),
            remember: (offset, anchor) =>
              model.updateReaderScrollOffset(offset, office, anchor),
          }
        : undefined,
    [model, office],
  );

  if (office) return <Reader key={office.id} office={office} place={place} />;
  return (
    <main className="reader reader--unloaded">
      {state.errorMessage && !state.isLoading ? (
        <div className="reader__status" role="alert">
          <h1>Office unavailable</h1>
          <p>{state.errorMessage}</p>
          <button type="button" onClick={() => navigate("/")}>
            Back
          </button>
        </div>
      ) : (
        <div className="reader__status" role="status" aria-label="Loading">
          <span className="spinner" />
        </div>
      )}
    </main>
  );
}
