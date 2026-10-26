import {
  ChevronLeft,
  ChevronRight,
  Ellipsis,
  Info,
  Search,
} from "lucide-react";
import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { useNavigate } from "react-router-dom";
import { isDark, type HourSelectionView } from "@/app/appearanceState.ts";
import {
  useAppModel,
  useAppState,
  useAppearance,
  useServices,
} from "@/app/context.tsx";
import { OfficeTraditions } from "@/app/officeTradition.ts";
import { massPath, officePath } from "@/app/routes.ts";
import {
  LocalDays,
  OfficeHours,
  type LiturgicalDay,
  type LocalDay,
  type OfficeDocument,
  type OfficeHour,
} from "@/core/models.ts";
import { AboutSheet } from "@/settings/AboutSheet.tsx";
import { SettingsSheet } from "@/settings/SettingsSheet.tsx";
import {
  hideHomeSky,
  homeShowsSky,
  openingWheelRotation,
  showHomeSky,
} from "./ambientSky.ts";
import { homeHeaderPresentation } from "./homeHeaderPresentation.ts";
import { HourWheelView } from "./HourWheelView.tsx";
import { MonthDaysSheet } from "./MonthDaysSheet.tsx";
import { sundialIdealHeight, SundialLayout } from "./sundial.ts";
import { SundialView } from "./SundialView.tsx";

const SearchSheet = lazy(() => import("@/search/SearchSheet.tsx"));

const dateFormatter = new Intl.DateTimeFormat("en-US", {
  weekday: "long",
  month: "long",
  day: "numeric",
  year: "numeric",
});

function useSize(): [
  React.RefObject<HTMLElement | null>,
  { width: number; height: number },
] {
  const element = useRef<HTMLElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const measure = () => {
      const bounds = target.getBoundingClientRect();
      setSize((previous) =>
        previous.width === bounds.width && previous.height === bounds.height
          ? previous
          : { width: bounds.width, height: bounds.height },
      );
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    return () => observer.disconnect();
  }, []);
  return [element, size];
}

function headerSummary(day: LiturgicalDay, context: string | null): string {
  return [
    dateFormatter.format(LocalDays.date(day.date)),
    homeHeaderPresentation(day, null).rankDisplayName,
    homeHeaderPresentation(day, null).titleLatin,
    context,
  ]
    .filter(Boolean)
    .join(", ");
}

function DayHeader({
  day,
  office,
  onOpen,
  onOpenMass,
}: {
  day: LiturgicalDay;
  office: OfficeDocument | null;
  onOpen: () => void;
  onOpenMass: () => void;
}) {
  const state = useAppState();
  const presentation = homeHeaderPresentation(day, office);
  const details = [
    dateFormatter.format(LocalDays.date(day.date)),
    ...presentation.commemorations.map(
      (commemoration) => commemoration.titleLatin,
    ),
  ];
  // The day's Mass stands in red under the civil date, above Pray, named by
  // its weekday, for the day shown need not be today; the rest of the header
  // opens the month's days, as one button and the date beneath it.
  return (
    <div className="home-header">
      <button
        type="button"
        className="home-header__open"
        aria-label="Offices for this month"
        aria-description={`${headerSummary(day, presentation.officeContext)}. Shows the feast days and classes for this month.`}
        onClick={onOpen}
      >
        {presentation.rankDisplayName && (
          <span className="home-header__rank">
            {presentation.rankDisplayName}
          </span>
        )}
        {state.officeTradition !== "roman1960" && (
          <span className="home-header__edition">
            {OfficeTraditions.title(state.officeTradition)}
          </span>
        )}
        <span
          className="home-header__title"
          lang="la"
          role="heading"
          aria-level={1}
        >
          {presentation.titleLatin}
        </span>
        {presentation.officeContext && (
          <span className="home-header__context">
            {presentation.officeContext}
          </span>
        )}
      </button>
      <span className="home-header__date" onClick={onOpen}>
        {details.join(" · ")}
      </span>
      <button
        type="button"
        className="home-header__mass"
        aria-description="Opens the Mass of the day, with its chant"
        onClick={onOpenMass}
      >
        <span>Mass</span>
        <svg viewBox="0 0 8 13" aria-hidden="true">
          <path d="M1.5 1.5l5 5-5 5" />
        </svg>
      </button>
    </div>
  );
}

/** How far a drag of the day header must travel to turn the day. */
function commitDistance(width: number): number {
  return Math.min(112, Math.max(64, width * 0.18));
}

/** The day a swipe turns to, drawn beside the one shown: after it (1) or before it (-1). */
interface IncomingDay {
  day: LiturgicalDay;
  offset: -1 | 1;
}

const reducesMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** How long the header takes to turn to the day beside it. */
const turnDuration = 420;

/**
 * Sets the header, and the day drawn beside it, so far from their place: at
 * once while it is dragged, or turning there (`turns`) or springing back.
 */
function placeHeader(
  region: HTMLElement | null,
  offset: number,
  animation: "none" | "settles" | "turns",
) {
  const target = region?.firstElementChild as HTMLElement | null | undefined;
  if (!target) return;
  target.style.transition =
    animation === "none" || reducesMotion()
      ? "none"
      : animation === "turns"
        ? `transform ${turnDuration}ms cubic-bezier(0.22, 0.9, 0.3, 1.04)`
        : "transform 320ms cubic-bezier(0.2, 0.9, 0.3, 1.1)";
  target.style.transform = offset === 0 ? "" : `translateX(${offset}px)`;
}

/**
 * Above the wheel the header and Pray stand midway in the room left them, so
 * that a day whose header is taller or shorter than the last moves both. They
 * are carried from where the header stood (`bottom`, its foot) to their new
 * place, not set there at a stroke.
 */
function glideToPlace(region: HTMLElement | null, bottom: number) {
  const slide = region?.firstElementChild as HTMLElement | null | undefined;
  const content = region?.closest<HTMLElement>(".home__content-fit");
  if (!slide || !content || reducesMotion()) return;
  const offset = bottom - slide.getBoundingClientRect().bottom;
  if (Math.abs(offset) < 0.5) return;
  content.style.transition = "none";
  content.style.transform = `translateY(${offset}px)`;
  void content.offsetHeight;
  content.style.transition = "transform 300ms cubic-bezier(0.2, 0.9, 0.3, 1)";
  content.style.transform = "";
}

/**
 * The day header answers a horizontal drag: left for the next day, right for
 * the previous one. As in the native apps, the day it turns to is drawn a
 * width away beside the one shown and moves with it, so that one drag carries
 * both; the day is turned when the header comes to rest, and the one drawn
 * beside it stays in its place until Home holds that day. At either end of
 * the edition the header yields a little and returns. Each display sets out a
 * header of its own, and the drag is attached to the one now shown.
 */
function useDaySwipe(
  width: number,
  selectedDate: LocalDay | null,
  neighbours: Partial<Record<-1 | 1, LiturgicalDay>>,
  canMove: (offset: -1 | 1) => boolean,
  move: (offset: -1 | 1) => void,
  display: HourSelectionView,
) {
  const region = useRef<HTMLElement>(null);
  const drag = useRef<{
    pointer: number;
    startX: number;
    startY: number;
    active: boolean;
  } | null>(null);
  const suppressClick = useRef(false);
  const [incoming, setIncoming] = useState<IncomingDay | null>(null);
  // The day a turn is bringing in, until Home holds it.
  const turning = useRef<{
    date: LocalDay;
    timeout: number;
    bottom: number;
  } | null>(null);

  const rest = useCallback(() => {
    const turned = turning.current;
    if (turned) window.clearTimeout(turned.timeout);
    turning.current = null;
    placeHeader(region.current, 0, "none");
    setIncoming(null);
    if (turned) glideToPlace(region.current, turned.bottom);
  }, []);

  const turn = useCallback(
    (offset: -1 | 1) => {
      if (turning.current || !selectedDate || !canMove(offset)) return;
      if (reducesMotion()) {
        rest();
        move(offset);
        return;
      }
      const next = neighbours[offset];
      setIncoming(next ? { day: next, offset } : null);
      turning.current = {
        date: LocalDays.adding(selectedDate, offset),
        // Should the day not come, the header returns to the one it holds.
        timeout: window.setTimeout(rest, turnDuration + 3000),
        bottom:
          region.current?.firstElementChild?.getBoundingClientRect().bottom ??
          0,
      };
      placeHeader(region.current, -offset * width, "turns");
      window.setTimeout(() => move(offset), turnDuration);
    },
    [canMove, move, neighbours, rest, selectedDate, width],
  );

  // Once Home holds the day turned to, it takes the place of the one drawn
  // there, before the page is next painted.
  useLayoutEffect(() => {
    const turned = turning.current;
    if (turned && selectedDate && LocalDays.equals(selectedDate, turned.date))
      rest();
  }, [rest, selectedDate]);

  useEffect(() => {
    const element = region.current;
    if (!element) return;

    const down = (event: PointerEvent) => {
      if (
        turning.current ||
        !event.isPrimary ||
        (event.pointerType === "mouse" && event.button !== 0)
      )
        return;
      drag.current = {
        pointer: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        active: false,
      };
    };
    const moveHandler = (event: PointerEvent) => {
      const current = drag.current;
      if (!current || event.pointerId !== current.pointer) return;
      const deltaX = event.clientX - current.startX;
      const deltaY = event.clientY - current.startY;
      if (!current.active) {
        if (Math.abs(deltaX) < 10 || Math.abs(deltaX) < Math.abs(deltaY))
          return;
        current.active = true;
        element.setPointerCapture(event.pointerId);
      }
      const direction = deltaX < 0 ? 1 : -1;
      const movable = canMove(direction);
      const next = movable ? neighbours[direction] : undefined;
      setIncoming((shown) =>
        !next
          ? null
          : shown?.day === next && shown.offset === direction
            ? shown
            : { day: next, offset: direction },
      );
      // Beyond the edition's first or last day the header only gives a little.
      placeHeader(element, movable ? deltaX : deltaX * 0.22, "none");
    };
    const finish = (event: PointerEvent, cancelled: boolean) => {
      const current = drag.current;
      if (!current || event.pointerId !== current.pointer) return;
      drag.current = null;
      if (!current.active) return;
      suppressClick.current = true;
      window.setTimeout(() => {
        suppressClick.current = false;
      }, 0);
      const deltaX = event.clientX - current.startX;
      const direction = deltaX < 0 ? 1 : -1;
      if (
        !cancelled &&
        Math.abs(deltaX) >= commitDistance(width) &&
        canMove(direction)
      ) {
        turn(direction);
      } else {
        placeHeader(element, 0, "settles");
        window.setTimeout(() => {
          if (!drag.current && !turning.current) setIncoming(null);
        }, 320);
      }
    };
    const up = (event: PointerEvent) => finish(event, false);
    const cancel = (event: PointerEvent) => finish(event, true);
    const click = (event: MouseEvent) => {
      if (suppressClick.current) {
        event.preventDefault();
        event.stopPropagation();
      }
    };

    element.addEventListener("pointerdown", down);
    element.addEventListener("pointermove", moveHandler);
    element.addEventListener("pointerup", up);
    element.addEventListener("pointercancel", cancel);
    element.addEventListener("click", click, true);
    return () => {
      element.removeEventListener("pointerdown", down);
      element.removeEventListener("pointermove", moveHandler);
      element.removeEventListener("pointerup", up);
      element.removeEventListener("pointercancel", cancel);
      element.removeEventListener("click", click, true);
    };
  }, [canMove, display, neighbours, turn, width]);

  return { region, incoming, turn };
}

export function HomeScreen() {
  const { appearance } = useServices();
  const model = useAppModel();
  const state = useAppState();
  const look = useAppearance();
  const navigate = useNavigate();
  const [container, size] = useSize();
  const [wheelSettledHour, setWheelSettledHour] = useState<OfficeHour>(
    state.selectedHour,
  );
  const [showsMonthDays, setShowsMonthDays] = useState(false);
  const [showsSettings, setShowsSettings] = useState(false);
  const [showsAbout, setShowsAbout] = useState(false);
  const [showsSearch, setShowsSearch] = useState(false);
  const [hasOpenedSearch, setHasOpenedSearch] = useState(false);
  const usesSundial = look.hourSelectionView === "sunDial";

  // Under the wheel, in the Dynamic appearance, lies the sky of horarum.com.
  // Before the wheel is drawn it is the sky of the place the wheel will
  // stand at; from then on the wheel says where it stands. The sky is taken
  // away the moment Home is left, and the wheel, which is put away a little
  // later and may yet say where it stands, is no longer heeded.
  const showsSky = homeShowsSky(look);
  const paintsSky = useRef(false);
  useLayoutEffect(() => {
    if (!showsSky) return;
    const root = document.documentElement;
    paintsSky.current = true;
    showHomeSky(
      root,
      openingWheelRotation(
        model.state.selectedHour,
        model.state.automaticallySelectsCurrentOffice,
        window.matchMedia("(prefers-reduced-motion: reduce)").matches,
        new Date(),
      ),
    );
    return () => {
      paintsSky.current = false;
      hideHomeSky(root);
    };
  }, [model, showsSky]);

  // The wheel runs on below the window (see `.home--wheel`), so the window
  // is held at its head: a page left scrolled, or a browser that scrolls a
  // page it was told not to, would otherwise carry the wheel off.
  useLayoutEffect(() => {
    if (usesSundial) return;
    const anchor = () => {
      if (window.scrollX || window.scrollY) window.scrollTo(0, 0);
    };
    anchor();
    window.addEventListener("scroll", anchor, { passive: true });
    return () => window.removeEventListener("scroll", anchor);
  }, [usesSundial]);

  // The room the header and Pray need above the wheel.
  const [contentHeight, setContentHeight] = useState(0);
  const measureContent = useCallback((element: HTMLElement | null) => {
    if (!element) return;
    const measure = () => setContentHeight(element.offsetHeight);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // Home is never shown over an open office. One left by the browser's own
  // Back, or by closing its page, is closed here, and the clock is followed
  // again; until then Automatic could not return to the present hour.
  useEffect(() => {
    model.endReaderSession();
    void model.refreshAfterBecomingActive();
  }, [model]);

  // On Home the appearance follows the hour under the wheel's pointer.
  useEffect(() => {
    appearance.setDisplayedHour(state.selectedHour);
  }, [appearance, state.selectedHour]);

  // Returning to the page is like returning to the app: follow the clock again.
  useEffect(() => {
    const refresh = () => {
      if (!document.hidden) void model.refreshAfterBecomingActive();
    };
    document.addEventListener("visibilitychange", refresh);
    window.addEventListener("focus", refresh);
    return () => {
      document.removeEventListener("visibilitychange", refresh);
      window.removeEventListener("focus", refresh);
    };
  }, [model]);

  const settle = useCallback(
    (hour: OfficeHour) => {
      setWheelSettledHour(hour);
      if (model.state.automaticallySelectsCurrentOffice) {
        void model.selectCurrentOffice();
      } else {
        void model.selectHour(hour);
      }
    },
    [model],
  );

  useEffect(() => {
    setWheelSettledHour(state.selectedHour);
  }, [state.selectedHour]);

  // Have the office at hand before Pray is tapped.
  useEffect(() => {
    if (state.selectedDay)
      model.prefetch(state.selectedDay.date, wheelSettledHour);
  }, [model, state.selectedDay, wheelSettledHour]);

  const selectedDate = state.selectedDay?.date ?? null;
  const coverage = state.coverage;
  const canMoveDay = useCallback(
    (offset: -1 | 1) => {
      if (!selectedDate || !coverage) return false;
      const target = LocalDays.adding(selectedDate, offset);
      return (
        LocalDays.compare(target, coverage.start) >= 0 &&
        LocalDays.compare(target, coverage.end) <= 0
      );
    },
    [coverage, selectedDate],
  );
  const moveDay = useCallback(
    (offset: -1 | 1) => {
      const current = model.state.selectedDay?.date;
      if (current)
        void model.selectCivilDate(LocalDays.adding(current, offset));
    },
    [model],
  );
  // The days either side, read ahead so that a swipe has the one it turns to
  // at hand, with the office it will hold.
  const [neighbours, setNeighbours] = useState<
    Partial<Record<-1 | 1, LiturgicalDay>>
  >({});
  useEffect(() => {
    let current = true;
    setNeighbours({});
    if (!selectedDate) return;
    void Promise.all([model.availableDay(-1), model.availableDay(1)]).then(
      ([before, after]) => {
        if (!current) return;
        setNeighbours({ [-1]: before ?? undefined, 1: after ?? undefined });
        for (const day of [before, after])
          if (day) model.prefetch(day.date, model.state.selectedHour);
      },
    );
    return () => {
      current = false;
    };
  }, [model, selectedDate, state.officeTradition]);
  const {
    region: headerRegion,
    incoming,
    turn: turnDay,
  } = useDaySwipe(
    size.width,
    selectedDate,
    neighbours,
    canMoveDay,
    moveDay,
    look.hourSelectionView,
  );

  const openOffice = () => {
    const day = state.selectedDay?.date ?? state.selectedCivilDate;
    navigate(officePath(day, wheelSettledHour));
  };

  // The Dial display stands at the foot of the page, the header above it.
  const sundialHeight = Math.max(
    size.width <= 500
      ? SundialLayout.minimumHeight
      : Math.min(
          sundialIdealHeight(size.width),
          Math.max(220, size.height - 220),
        ),
    SundialLayout.minimumHeight,
  );
  const sundialBottomPadding = 14;
  const headerRegionHeight = Math.max(
    0,
    size.height - sundialHeight - sundialBottomPadding,
  );
  const openHour = (hour: OfficeHour) => {
    const day = state.selectedDay?.date ?? state.selectedCivilDate;
    navigate(officePath(day, hour));
  };

  const header = state.selectedDay && (
    <section
      ref={headerRegion}
      className={
        usesSundial
          ? "home__header-region home__header-region--sundial"
          : "home__header-region"
      }
      style={usesSundial ? { height: headerRegionHeight } : undefined}
      aria-description="Swipe left for the next day or right for the previous day"
    >
      <div className="home__header-slide">
        <button
          type="button"
          className="icon-button home__day-step"
          aria-label="Previous day"
          disabled={!canMoveDay(-1)}
          onClick={() => turnDay(-1)}
        >
          <ChevronLeft aria-hidden="true" />
        </button>
        <DayHeader
          day={state.selectedDay}
          office={state.office}
          onOpen={() => setShowsMonthDays(true)}
          onOpenMass={() => navigate(massPath(state.selectedDay!.date))}
        />
        <button
          type="button"
          className="icon-button home__day-step"
          aria-label="Next day"
          disabled={!canMoveDay(1)}
          onClick={() => turnDay(1)}
        >
          <ChevronRight aria-hidden="true" />
        </button>
        {incoming && (
          <div
            className="home__header-incoming"
            style={{
              transform: `translateX(${incoming.offset * size.width}px)`,
            }}
            aria-hidden="true"
            inert
          >
            <span className="icon-button home__day-step" />
            <DayHeader
              day={incoming.day}
              office={null}
              onOpen={() => {}}
              onOpenMass={() => {}}
            />
            <span className="icon-button home__day-step" />
          </div>
        )}
      </div>
    </section>
  );

  return (
    <main
      ref={container}
      className={usesSundial ? "home home--dial" : "home home--wheel"}
      style={
        usesSundial
          ? undefined
          : ({
              "--home-content-height": `${contentHeight}px`,
            } as React.CSSProperties)
      }
    >
      <header className="home__toolbar">
        <button
          type="button"
          className="icon-button"
          aria-label="Search prayers and readings"
          onClick={() => {
            setHasOpenedSearch(true);
            setShowsSearch(true);
          }}
        >
          <Search aria-hidden="true" />
        </button>
        <div className="home__toolbar-group">
          <button
            type="button"
            className="icon-button"
            aria-label="About Hours"
            title="The canonical hour schedule and contact information"
            onClick={() => setShowsAbout(true)}
          >
            <Info aria-hidden="true" />
          </button>
          <button
            type="button"
            className="icon-button"
            aria-label="Settings"
            onClick={() => setShowsSettings(true)}
          >
            <Ellipsis aria-hidden="true" />
          </button>
        </div>
      </header>

      {state.selectedDay ? (
        usesSundial ? (
          <>
            {header}
            {size.width > 0 && (
              <div
                className="home__sundial"
                style={{ bottom: sundialBottomPadding }}
              >
                <SundialView
                  width={size.width}
                  height={sundialHeight}
                  selection={state.selectedHour}
                  followsLocalTime={state.automaticallySelectsCurrentOffice}
                  showsShadow={!isDark(look)}
                  onSelect={(hour) => {
                    if (model.state.automaticallySelectsCurrentOffice) {
                      model.setAutomaticOfficeSelection(false);
                    }
                    model.setSelectedHour(hour);
                    setWheelSettledHour(hour);
                    void model.selectHour(hour);
                  }}
                  onLiveHourChange={(hour) => {
                    model.setSelectedHour(hour);
                    void model.selectCurrentOffice();
                  }}
                  onOpenOffice={openHour}
                />
              </div>
            )}
          </>
        ) : (
          <>
            <div className="home__content">
              <div ref={measureContent} className="home__content-fit">
                {header}
                <button
                  type="button"
                  className="home__pray"
                  aria-description="Opens the selected office"
                  onClick={openOffice}
                >
                  <span>Pray {OfficeHours.englishTitle(wheelSettledHour)}</span>
                  <svg viewBox="0 0 8 13" aria-hidden="true">
                    <path d="M1.5 1.5l5 5-5 5" />
                  </svg>
                </button>
              </div>
            </div>
            <HourWheelView
              selection={state.selectedHour}
              followsLocalTime={state.automaticallySelectsCurrentOffice}
              dark={isDark(look)}
              onFollowsLocalTimeChange={(follows) => {
                if (follows !== model.state.automaticallySelectsCurrentOffice) {
                  model.setAutomaticOfficeSelection(follows);
                }
              }}
              onRotationChange={(rotation) => {
                if (paintsSky.current) {
                  showHomeSky(document.documentElement, rotation);
                }
              }}
              onDisplayedHourChange={(hour) =>
                appearance.setDisplayedHour(hour)
              }
              onSelectionChange={(hour) => model.setSelectedHour(hour)}
              onSelectionSettled={settle}
            />
          </>
        )
      ) : state.errorMessage ? (
        <div className="home__unloaded" role="alert">
          <h1>Office unavailable</h1>
          <p>{state.errorMessage}</p>
          <button
            type="button"
            onClick={() => void model.refreshAfterBecomingActive()}
          >
            Try Again
          </button>
        </div>
      ) : (
        <div className="home__unloaded" role="status" aria-label="Loading">
          <span className="spinner" />
        </div>
      )}

      <MonthDaysSheet open={showsMonthDays} onOpenChange={setShowsMonthDays} />
      <SettingsSheet open={showsSettings} onOpenChange={setShowsSettings} />
      <AboutSheet open={showsAbout} onOpenChange={setShowsAbout} />
      {/* Search brings SQLite and the library with it, so it is fetched when first opened. */}
      {hasOpenedSearch && (
        <Suspense fallback={null}>
          <SearchSheet open={showsSearch} onOpenChange={setShowsSearch} />
        </Suspense>
      )}
    </main>
  );
}
