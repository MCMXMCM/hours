import { ChevronRight } from "lucide-react";
import {
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
} from "react";
import { OfficeHours, officeHours, type OfficeHour } from "@/core/models.ts";
import {
  SundialAffordance,
  SundialInitialAnimationPlan,
  SundialLaunchProjection,
  SundialLayout,
  SundialPresentations,
  SundialRefreshPolicy,
  SundialTimeMath,
  type SundialPresentation,
} from "./sundial.ts";

export interface SundialViewProps {
  width: number;
  height: number;
  selection: OfficeHour;
  followsLocalTime: boolean;
  /** The shadow is cast only in the light appearance. */
  showsShadow: boolean;
  /** An hour was chosen by hand; the dial no longer follows the clock. */
  onSelect: (hour: OfficeHour) => void;
  /** The clock has moved into another hour while the dial follows it. */
  onLiveHourChange: (hour: OfficeHour) => void;
  onOpenOffice: (hour: OfficeHour) => void;
}

/** What the drawn shadow is made from; each is carried smoothly to its new value. */
interface Drawn {
  readonly verticalProgress: number;
  readonly length: number;
  readonly launchProgress: number;
  readonly strength: number;
}

/** `Animation.easeInOut(duration:)`, in milliseconds. */
const selectionDuration = 720;
const initialShadowDuration = 2_000;

/** SwiftUI's ease-in-out: the cubic curve through (0.42, 0) and (0.58, 1). */
function easeInOut(progress: number): number {
  const clamped = Math.min(Math.max(progress, 0), 1);
  // Solve the curve's x for its parameter, then read off y.
  let parameter = clamped;
  for (let step = 0; step < 6; step += 1) {
    const inverse = 1 - parameter;
    const x =
      3 * inverse * inverse * parameter * 0.42 +
      3 * inverse * parameter * parameter * 0.58 +
      parameter * parameter * parameter;
    const slope =
      3 * inverse * inverse * 0.42 +
      6 * inverse * parameter * (0.58 - 0.42) +
      3 * parameter * parameter * (1 - 0.58);
    if (Math.abs(slope) < 1e-6) break;
    parameter -= (x - clamped) / slope;
  }
  const inverse = 1 - parameter;
  return (
    3 * inverse * parameter * parameter + parameter * parameter * parameter
  );
}

/**
 * Carries the drawn values to a target over a duration, or at once. With
 * `placesShadow` the shadow's own position is taken up at once and only its
 * entrance and strength are carried, as when the dial first appears.
 */
function useCarried(
  target: Drawn,
  duration: number,
  placesShadow: boolean,
): Drawn {
  const [drawn, setDrawn] = useState(target);
  const current = useRef(target);
  const frame = useRef(0);
  const { verticalProgress, length, launchProgress, strength } = target;

  useEffect(() => {
    cancelAnimationFrame(frame.current);
    const goal: Drawn = { verticalProgress, length, launchProgress, strength };
    const from: Drawn = placesShadow
      ? { ...current.current, verticalProgress, length }
      : current.current;
    const still =
      duration <= 0 ||
      (from.verticalProgress === goal.verticalProgress &&
        from.length === goal.length &&
        from.launchProgress === goal.launchProgress &&
        from.strength === goal.strength);
    if (still) {
      current.current = goal;
      setDrawn(goal);
      return;
    }
    const began = performance.now();
    const step = (now: number) => {
      const eased = easeInOut((now - began) / duration);
      const between = (start: number, end: number) =>
        start + (end - start) * eased;
      const next: Drawn = {
        verticalProgress: between(from.verticalProgress, goal.verticalProgress),
        length: between(from.length, goal.length),
        launchProgress: between(from.launchProgress, goal.launchProgress),
        strength: between(from.strength, goal.strength),
      };
      current.current = next;
      setDrawn(next);
      if (now - began < duration) frame.current = requestAnimationFrame(step);
    };
    frame.current = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame.current);
  }, [
    duration,
    launchProgress,
    length,
    placesShadow,
    strength,
    verticalProgress,
  ]);

  return drawn;
}

type InitialStage = "waiting" | "animating" | "complete";

/** The style of a layer of the shadow softened by a blur of that radius. */
function softened(radius: number): CSSProperties {
  const blur = `blur(${radius}px)`;
  return { filter: blur, WebkitFilter: blur };
}

/**
 * The Dial display: the eight hours in a column, and the gnomon's shadow
 * lying toward the hour of the day. An hour is chosen by a tap, a swipe, or
 * the arrow keys; the chosen hour, tapped again, opens its office.
 */
export function SundialView({
  width,
  height,
  selection,
  followsLocalTime,
  showsShadow,
  onSelect,
  onLiveHourChange,
  onOpenOffice,
}: SundialViewProps) {
  const gradient = useId();
  const layout = useMemo(
    () => new SundialLayout({ width, height }),
    [height, width],
  );
  const reducesMotion = useMemo(
    () => window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    [],
  );

  // The clock is read every five minutes while the page is in view.
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const read = () => {
      if (!document.hidden) setNow(new Date());
    };
    const timer = window.setInterval(
      read,
      SundialRefreshPolicy.liveInterval * 1_000,
    );
    document.addEventListener("visibilitychange", read);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", read);
    };
  }, []);
  const liveHour = OfficeHours.current(now);
  const reportLiveHour = useRef(onLiveHourChange);
  reportLiveHour.current = onLiveHourChange;
  const reportedHour = useRef(liveHour);
  useEffect(() => {
    if (reportedHour.current === liveHour) return;
    reportedHour.current = liveHour;
    if (followsLocalTime) reportLiveHour.current(liveHour);
  }, [followsLocalTime, liveHour]);

  // As the dial first appears the shadow enters and travels to the hour.
  const [stage, setStage] = useState<InitialStage>(() =>
    reducesMotion || document.hidden ? "complete" : "waiting",
  );
  const [initialPresentation, setInitialPresentation] =
    useState<SundialPresentation>(SundialPresentations.matins);
  const follows = useRef(followsLocalTime);
  follows.current = followsLocalTime;
  useEffect(() => {
    if (stage !== "waiting") return;
    let finish: number | undefined;
    const start = window.setTimeout(() => {
      const presentation = follows.current
        ? SundialInitialAnimationPlan.presentation(new Date())
        : null;
      if (presentation === null) {
        setStage("complete");
        return;
      }
      setInitialPresentation(presentation);
      setStage("animating");
      finish = window.setTimeout(
        () => setStage("complete"),
        initialShadowDuration,
      );
    }, 100);
    return () => {
      window.clearTimeout(start);
      window.clearTimeout(finish);
    };
    // The entrance is made once, when the dial is first shown.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const usesInitialPresentation = followsLocalTime && stage !== "complete";
  const livePresentation = SundialPresentations.live(liveHour);
  const displayedShadow = usesInitialPresentation
    ? initialPresentation.shadow
    : followsLocalTime
      ? livePresentation.shadow
      : SundialTimeMath.shadow(selection);
  const initialProgress = stage === "waiting" ? 0 : 1;
  const strength = !showsShadow
    ? 0
    : usesInitialPresentation
      ? initialPresentation.strength * initialProgress
      : followsLocalTime
        ? livePresentation.strength
        : SundialTimeMath.ambientSky(selection).shadowStrength;

  const drawn = useCarried(
    {
      verticalProgress: displayedShadow.verticalProgress,
      length: displayedShadow.length,
      launchProgress: usesInitialPresentation ? initialProgress : 1,
      strength,
    },
    reducesMotion
      ? 0
      : stage === "animating"
        ? initialShadowDuration
        : stage === "waiting"
          ? 0
          : selectionDuration,
    stage === "animating",
  );

  const projected = SundialLaunchProjection.shadow(
    {
      angleDegrees: 0,
      length: drawn.length,
      centerlineDepth: 0,
      verticalProgress: drawn.verticalProgress,
    },
    drawn.launchProgress,
  );
  const path = layout.shadowPath(projected);
  const points = path.map((point) => `${point.x},${point.y}`).join(" ");
  const source = layout.shadowSource(projected);
  const tip = layout.shadowTip(projected);

  const select = (hour: OfficeHour) => {
    setStage("complete");
    onSelect(hour);
  };
  const selectAdjacentHour = (offset: number) => {
    const currentIndex = Math.max(0, officeHours.indexOf(selection));
    const nextIndex =
      (currentIndex + offset + officeHours.length) % officeHours.length;
    select(officeHours[nextIndex]);
  };

  // A swipe moves to the next hour or the one before.
  const swipe = useRef<{ pointer: number; x: number; y: number } | null>(null);
  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    swipe.current = {
      pointer: event.pointerId,
      x: event.clientX,
      y: event.clientY,
    };
  };
  const swallowsClick = useRef(false);
  const onPointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    const began = swipe.current;
    swipe.current = null;
    if (!began || began.pointer !== event.pointerId) return;
    const horizontalDistance = event.clientX - began.x;
    const verticalDistance = event.clientY - began.y;
    if (Math.hypot(horizontalDistance, verticalDistance) < 24) return;
    if (
      Math.abs(verticalDistance) >= 24 &&
      Math.abs(verticalDistance) > Math.abs(horizontalDistance)
    ) {
      swallowsClick.current = true;
      selectAdjacentHour(verticalDistance < 0 ? 1 : -1);
    } else if (Math.abs(horizontalDistance) >= 40) {
      swallowsClick.current = true;
      selectAdjacentHour(horizontalDistance < 0 ? 1 : -1);
    }
    // The click that ends a swipe belongs to the swipe, not to an hour.
    window.setTimeout(() => {
      swallowsClick.current = false;
    }, 0);
  };

  // The keyboard's focus goes with the hour chosen.
  const dial = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const group = dial.current;
    if (!group || !group.contains(document.activeElement)) return;
    group.querySelector<HTMLElement>('[aria-current="true"]')?.focus();
  }, [selection]);

  return (
    <div
      ref={dial}
      className="sundial"
      role="group"
      aria-label="Canonical hours"
      aria-description={
        followsLocalTime
          ? "Tap an hour or swipe toward another hour."
          : `${OfficeHours.englishTitle(selection)} selected manually`
      }
      style={{ width, height }}
      onPointerDown={onPointerDown}
      onPointerUp={onPointerUp}
      onPointerCancel={() => {
        swipe.current = null;
      }}
      onKeyDown={(event) => {
        if (event.key === "ArrowDown" || event.key === "ArrowRight") {
          event.preventDefault();
          selectAdjacentHour(1);
        } else if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
          event.preventDefault();
          selectAdjacentHour(-1);
        }
      }}
    >
      {path.length > 0 && drawn.strength > 0 && (
        // The shadow is two layers, as the native Dial draws it: a faint,
        // wide one about a darker one that pales toward its tip. Each layer
        // is softened whole, as an element: a blur set on a shape within an
        // SVG is not drawn by every browser, and the shadow was then a wedge
        // with hard edges.
        <>
          <svg
            className="sundial__shadow"
            width={width}
            height={height}
            viewBox={`0 0 ${width} ${height}`}
            aria-hidden="true"
            style={softened(layout.shadowOuterBlurRadius)}
          >
            <polygon points={points} fillOpacity={0.13 * drawn.strength} />
          </svg>
          <svg
            className="sundial__shadow"
            width={width}
            height={height}
            viewBox={`0 0 ${width} ${height}`}
            aria-hidden="true"
            style={softened(layout.shadowInnerBlurRadius)}
          >
            <defs>
              <linearGradient
                id={gradient}
                gradientUnits="userSpaceOnUse"
                x1={source.x}
                y1={source.y}
                x2={tip.x}
                y2={tip.y}
              >
                <stop offset="0" stopOpacity={0.34 * drawn.strength} />
                <stop offset="0.58" stopOpacity={0.2 * drawn.strength} />
                <stop offset="1" stopOpacity={0.07 * drawn.strength} />
              </linearGradient>
            </defs>
            <polygon points={points} fill={`url(#${gradient})`} />
          </svg>
        </>
      )}

      {officeHours.map((hour) => {
        const position = layout.labelPosition(hour);
        const isSelected = selection === hour;
        const showsSelectionChevron =
          isSelected &&
          SundialAffordance.showsSelectionChevron(hour, showsShadow);
        return (
          <button
            key={hour}
            type="button"
            className="sundial__hour"
            aria-label={`${OfficeHours.latinName(hour)}, ${OfficeHours.englishTitle(hour)}`}
            aria-current={isSelected ? "true" : undefined}
            aria-description={
              isSelected
                ? `Selected, ${OfficeHours.customaryTimeRange(hour)}. Opens this office`
                : `${OfficeHours.customaryTimeRange(hour)}. Focuses this hour`
            }
            style={{
              left: position.x - SundialLayout.hourRowWidth / 2,
              top: position.y - 22,
              width: SundialLayout.hourRowWidth,
            }}
            onClick={() => {
              if (swallowsClick.current) return;
              if (isSelected) onOpenOffice(hour);
              else select(hour);
            }}
          >
            <span className="sundial__name" lang="la">
              {OfficeHours.latinName(hour)}
            </span>
            <span className="sundial__disclosure" aria-hidden="true">
              <ChevronRight data-shown={showsSelectionChevron || undefined} />
            </span>
          </button>
        );
      })}
    </div>
  );
}
