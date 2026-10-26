import { useEffect, useRef } from "react";
import {
  HourWheel,
  shortestWheelTarget,
  wheelHourForRotation,
} from "@site/hour-wheel.js";
import {
  coastDuration,
  coastRotation,
  dragRotation,
  minimumCoastVelocity,
  releaseAngularVelocity,
  springDuration,
  springRotation,
} from "@site/hour-wheel-physics.js";
import { OfficeHours, officeHours, type OfficeHour } from "@/core/models.ts";
import { liveWheelRotationAt, openingWheelRotation } from "./ambientSky.ts";

export interface HourWheelViewProps {
  /** The hour the model has selected. */
  selection: OfficeHour;
  /** True while the wheel turns with the clock. */
  followsLocalTime: boolean;
  /** The wheel is drawn for the dark appearance. */
  dark: boolean;
  /** A manual act has ended automatic selection. */
  onFollowsLocalTimeChange: (follows: boolean) => void;
  /** The wheel stands at a new angle, in degrees: the sky follows it. */
  onRotationChange: (rotation: number) => void;
  /** The hour under the pointer changed, perhaps mid-spin. */
  onDisplayedHourChange: (hour: OfficeHour) => void;
  /** The reader chose an hour; the wheel is still turning to it. */
  onSelectionChange: (hour: OfficeHour) => void;
  /** The wheel has come to rest on an hour. */
  onSelectionSettled: (hour: OfficeHour) => void;
}

type Motion =
  | { kind: "ambient" }
  | { kind: "manual" }
  | {
      kind: "tap";
      startRotation: number;
      targetRotation: number;
      targetHour: OfficeHour;
      startedAt: number;
      duration: number;
      finishKind: "ambient" | "manual";
    }
  | {
      kind: "coasting";
      startRotation: number;
      initialVelocity: number;
      startedAt: number;
      duration: number;
    }
  | {
      kind: "snapping";
      startRotation: number;
      targetRotation: number;
      targetHour: OfficeHour;
      startedAt: number;
    };

interface PointerDrag {
  pointerID: number;
  startX: number;
  startRotation: number;
  previousMotion: Motion;
  didDrag: boolean;
  samples: Array<{ x: number; time: number }>;
}

const appearanceTransitionDuration = 720;
const minimumTapSpinDuration = 900;
const maximumTapSpinDuration = 2200;
/** The live wheel is brought up to the clock this often. */
const liveRefreshInterval = 15_000;

function nearest(canonical: number, reference: number): number {
  return canonical + Math.round((reference - canonical) / 360) * 360;
}

function easeInOutCubic(progress: number): number {
  return progress < 0.5
    ? 4 * progress * progress * progress
    : 1 - Math.pow(-2 * progress + 2, 3) / 2;
}

function hourForRotation(rotation: number): OfficeHour {
  return wheelHourForRotation(rotation) as OfficeHour;
}

/**
 * Drives the wheel: it turns with the clock, follows a drag, coasts and
 * springs to rest on an hour, and spins to an hour that is tapped.
 */
class WheelController {
  private readonly wheel: HourWheel;
  private readonly stage: HTMLElement;
  private readonly reducesMotion: MediaQueryList;
  private callbacks: HourWheelViewProps;
  private rotation: number;
  private appearanceBlend: number;
  private displayedHour: OfficeHour;
  private motion: Motion;
  private drag: PointerDrag | null = null;
  private suppressNextClick = false;
  private frame: number | null = null;
  private lastFrameAt = performance.now();
  private liveTimer: number | null = null;
  private readonly resizes: ResizeObserver;
  private disposed = false;

  constructor(
    canvas: HTMLCanvasElement,
    stage: HTMLElement,
    props: HourWheelViewProps,
  ) {
    this.stage = stage;
    this.callbacks = props;
    this.reducesMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    this.wheel = new HourWheel(canvas, {
      tapestrySource: "/wheel/tapestry.webp",
    });
    this.displayedHour = props.selection;
    this.appearanceBlend = props.dark ? 1 : 0;
    this.rotation = openingWheelRotation(
      props.selection,
      props.followsLocalTime,
      this.reducesMotion.matches,
      new Date(),
    );
    this.motion = { kind: props.followsLocalTime ? "ambient" : "manual" };
    void this.wheel.ready.then(() => {
      if (this.disposed) return;
      this.wheel.resize();
      this.apply();
    });
    this.apply();
    this.scheduleLiveRefresh();
    // The stylesheet sizes the wheel; it is drawn anew for each size.
    this.resizes = new ResizeObserver(() => {
      this.wheel.resize();
      this.apply();
    });
    this.resizes.observe(stage);

    stage.addEventListener("pointerdown", this.pointerDown);
    stage.addEventListener("pointermove", this.pointerMove);
    stage.addEventListener("pointerup", this.pointerUp);
    stage.addEventListener("pointercancel", this.pointerCancel);
    stage.addEventListener("click", this.click);
    document.addEventListener("visibilitychange", this.visibilityChange);
  }

  dispose(): void {
    this.disposed = true;
    if (this.frame !== null) cancelAnimationFrame(this.frame);
    if (this.liveTimer !== null) window.clearInterval(this.liveTimer);
    this.resizes.disconnect();
    this.stage.removeEventListener("pointerdown", this.pointerDown);
    this.stage.removeEventListener("pointermove", this.pointerMove);
    this.stage.removeEventListener("pointerup", this.pointerUp);
    this.stage.removeEventListener("pointercancel", this.pointerCancel);
    this.stage.removeEventListener("click", this.click);
    document.removeEventListener("visibilitychange", this.visibilityChange);
  }

  /** New properties from the view: a selection made elsewhere. */
  update(props: HourWheelViewProps, previous: HourWheelViewProps): void {
    this.callbacks = props;
    if (props.dark !== previous.dark) this.animate();
    const followsChanged = props.followsLocalTime !== previous.followsLocalTime;
    if (followsChanged && props.followsLocalTime) {
      // Returning to the clock: turn to the present hour and resume.
      const now = new Date();
      const hour = OfficeHours.current(now);
      this.settleOn(hour, {
        isManual: false,
        targetRotation: this.reducesMotion.matches
          ? shortestWheelTarget(hour, this.rotation)
          : nearest(liveWheelRotationAt(now), this.rotation),
      });
      return;
    }
    if (
      this.drag ||
      this.motion.kind === "coasting" ||
      this.motion.kind === "snapping"
    ) {
      return;
    }
    const target =
      this.motion.kind === "tap" ? this.motion.targetHour : this.displayedHour;
    if (props.selection !== target) {
      this.settleOn(props.selection, { isManual: !props.followsLocalTime });
    }
  }

  selectAdjacentHour(direction: -1 | 1): void {
    const index = officeHours.indexOf(this.displayedHour);
    const next =
      officeHours[
        (index + direction + officeHours.length) % officeHours.length
      ];
    this.chooseManually(next);
  }

  chooseManually(hour: OfficeHour): void {
    this.callbacks.onFollowsLocalTimeChange(false);
    this.callbacks.onSelectionChange(hour);
    this.settleOn(hour, { isManual: true, announces: true });
  }

  private scheduleLiveRefresh(): void {
    this.liveTimer = window.setInterval(() => {
      if (this.motion.kind === "ambient" && !document.hidden)
        this.refreshLive();
    }, liveRefreshInterval);
  }

  private refreshLive(): void {
    if (this.motion.kind !== "ambient") return;
    const now = new Date();
    if (this.reducesMotion.matches) {
      this.rotation = shortestWheelTarget(
        OfficeHours.current(now),
        this.rotation,
      );
    } else {
      this.rotation = nearest(liveWheelRotationAt(now), this.rotation);
    }
    const hour = hourForRotation(this.rotation);
    const changed = hour !== this.displayedHour;
    this.apply();
    // The clock has carried the wheel into the next hour.
    if (changed) this.callbacks.onSelectionSettled(hour);
  }

  private settleOn(
    hour: OfficeHour,
    options: {
      isManual: boolean;
      targetRotation?: number;
      announces?: boolean;
    },
  ): void {
    const targetRotation =
      options.targetRotation ?? shortestWheelTarget(hour, this.rotation);
    const finishKind = options.isManual ? "manual" : "ambient";
    if (this.reducesMotion.matches) {
      this.rotation = targetRotation;
      this.motion = { kind: finishKind };
      this.apply();
      if (options.announces) this.callbacks.onSelectionSettled(hour);
      return;
    }
    const distance = Math.abs(targetRotation - this.rotation);
    this.motion = {
      kind: "tap",
      startRotation: this.rotation,
      targetRotation,
      targetHour: hour,
      startedAt: performance.now(),
      duration: Math.min(
        maximumTapSpinDuration,
        Math.max(
          minimumTapSpinDuration,
          minimumTapSpinDuration + (distance / 180) * 1300,
        ),
      ),
      finishKind,
    };
    this.announcesSettle = options.announces ?? false;
    this.animate();
  }

  private announcesSettle = false;

  private startSnap(rotation: number, startedAt = performance.now()): void {
    const targetHour = hourForRotation(rotation);
    const targetRotation = shortestWheelTarget(targetHour, rotation);
    this.callbacks.onSelectionChange(targetHour);
    if (this.reducesMotion.matches) {
      this.rotation = targetRotation;
      this.motion = { kind: "manual" };
      this.apply();
      this.callbacks.onSelectionSettled(targetHour);
      return;
    }
    this.motion = {
      kind: "snapping",
      startRotation: rotation,
      targetRotation,
      targetHour,
      startedAt,
    };
    this.animate();
  }

  private animate(): void {
    if (this.frame !== null || this.disposed) return;
    this.lastFrameAt = performance.now();
    this.frame = requestAnimationFrame(this.drawFrame);
  }

  private drawFrame = (now: number): void => {
    this.frame = null;
    const elapsed = Math.min(100, Math.max(0, now - this.lastFrameAt));
    this.lastFrameAt = now;
    const motion = this.motion;
    let settled: OfficeHour | null = null;

    if (motion.kind === "tap") {
      const progress = Math.min(1, (now - motion.startedAt) / motion.duration);
      this.rotation =
        motion.startRotation +
        (motion.targetRotation - motion.startRotation) *
          easeInOutCubic(progress);
      if (progress >= 1) {
        this.rotation = motion.targetRotation;
        this.motion = { kind: motion.finishKind };
        if (this.announcesSettle) settled = motion.targetHour;
        this.announcesSettle = false;
      }
    } else if (motion.kind === "coasting") {
      const coastElapsed = (now - motion.startedAt) / 1_000;
      this.rotation = coastRotation(
        motion.startRotation,
        motion.initialVelocity,
        coastElapsed,
        motion.duration,
      );
      if (coastElapsed >= motion.duration) this.startSnap(this.rotation, now);
    } else if (motion.kind === "snapping") {
      const snapElapsed = (now - motion.startedAt) / 1_000;
      this.rotation = springRotation(
        motion.startRotation,
        motion.targetRotation,
        snapElapsed,
      );
      if (snapElapsed >= springDuration) {
        this.rotation = motion.targetRotation;
        this.motion = { kind: "manual" };
        settled = motion.targetHour;
      }
    }

    const targetBlend = this.callbacks.dark ? 1 : 0;
    const blendStep = Math.min(1, elapsed / appearanceTransitionDuration);
    this.appearanceBlend += (targetBlend - this.appearanceBlend) * blendStep;
    if (Math.abs(targetBlend - this.appearanceBlend) < 0.002)
      this.appearanceBlend = targetBlend;

    this.apply();
    if (settled) this.callbacks.onSelectionSettled(settled);

    const moving =
      this.motion.kind === "tap" ||
      this.motion.kind === "coasting" ||
      this.motion.kind === "snapping";
    if (moving || this.appearanceBlend !== targetBlend) this.animate();
  };

  /** Shows the wheel as it now stands and reports the hour under the pointer. */
  private apply(): void {
    const hour =
      this.motion.kind === "tap"
        ? this.motion.targetHour
        : hourForRotation(this.rotation);
    this.wheel.setState({
      rotation: this.rotation,
      selectedID: hour,
      appearanceBlend: this.appearanceBlend,
    });
    this.callbacks.onRotationChange(this.rotation);
    if (hour !== this.displayedHour) {
      this.displayedHour = hour;
      this.callbacks.onDisplayedHourChange(hour);
    }
  }

  /** The edge of the square the wheel is drawn in. */
  private diameter(): number {
    return this.stage.getBoundingClientRect().width;
  }

  private samples(event: PointerEvent): Array<{ x: number; time: number }> {
    const coalesced = event.getCoalescedEvents?.();
    const events = coalesced?.length ? coalesced : [event];
    return events.map((sample) => ({
      x: sample.clientX,
      time: sample.timeStamp,
    }));
  }

  private pointerDown = (event: PointerEvent): void => {
    if (
      this.drag ||
      !event.isPrimary ||
      (event.pointerType === "mouse" && event.button !== 0)
    ) {
      return;
    }
    this.stage.setPointerCapture(event.pointerId);
    this.drag = {
      pointerID: event.pointerId,
      startX: event.clientX,
      startRotation: this.rotation,
      previousMotion: this.motion,
      didDrag: false,
      samples: this.samples(event),
    };
  };

  private pointerMove = (event: PointerEvent): void => {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointerID) return;
    const translation = event.clientX - drag.startX;
    if (!drag.didDrag && Math.abs(translation) < 8) return;
    if (!drag.didDrag) {
      drag.didDrag = true;
      drag.startRotation = this.rotation;
      drag.startX = event.clientX - Math.sign(translation) * 8;
      this.motion = { kind: "manual" };
      this.stage.classList.add("is-dragging");
    }
    this.rotation =
      drag.startRotation +
      dragRotation(event.clientX - drag.startX, this.diameter());
    drag.samples.push(...this.samples(event));
    const latest = drag.samples[drag.samples.length - 1].time;
    drag.samples = drag.samples.filter((sample) => sample.time >= latest - 160);
    this.apply();
  };

  private finishDrag(event: PointerEvent, cancelled: boolean): void {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointerID) return;
    this.drag = null;
    this.stage.classList.remove("is-dragging");
    if (this.stage.hasPointerCapture(event.pointerId)) {
      this.stage.releasePointerCapture(event.pointerId);
    }
    if (!drag.didDrag) return;

    drag.samples.push(...this.samples(event));
    this.suppressNextClick = !cancelled;
    // Completing a drag is a manual act.
    this.callbacks.onFollowsLocalTimeChange(false);
    const velocity = cancelled
      ? 0
      : releaseAngularVelocity(drag.samples, this.diameter());
    if (
      this.reducesMotion.matches ||
      Math.abs(velocity) < minimumCoastVelocity
    ) {
      this.startSnap(this.rotation);
      return;
    }
    this.motion = {
      kind: "coasting",
      startRotation: this.rotation,
      initialVelocity: velocity,
      startedAt: performance.now(),
      duration: coastDuration(velocity),
    };
    this.animate();
  }

  private pointerUp = (event: PointerEvent): void =>
    this.finishDrag(event, false);
  private pointerCancel = (event: PointerEvent): void =>
    this.finishDrag(event, true);

  private click = (event: MouseEvent): void => {
    if (this.suppressNextClick) {
      this.suppressNextClick = false;
      return;
    }
    const hour = this.wheel.hourAtPoint(event.clientX, event.clientY);
    if (!hour || !OfficeHours.isOfficeHour(hour)) return;
    this.chooseManually(hour);
  };

  private visibilityChange = (): void => {
    if (!document.hidden) this.refreshLive();
  };
}

/**
 * The hour wheel: the upper half of a disc of the day's eight hours, turning
 * beneath a fixed pointer. Its size and place are the stylesheet's.
 */
export function HourWheelView(props: HourWheelViewProps) {
  const stage = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const controller = useRef<WheelController | null>(null);
  const latest = useRef(props);

  useEffect(() => {
    if (!stage.current || !canvas.current) return;
    const created = new WheelController(
      canvas.current,
      stage.current,
      latest.current,
    );
    controller.current = created;
    return () => {
      created.dispose();
      controller.current = null;
    };
  }, []);

  useEffect(() => {
    controller.current?.update(props, latest.current);
    latest.current = props;
  });

  const { selection } = props;
  // Within the group the keyboard's focus goes with the hour chosen.
  const choices = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const group = choices.current;
    if (!group || !group.contains(document.activeElement)) return;
    group.querySelector<HTMLElement>('[aria-checked="true"]')?.focus();
  }, [selection]);

  return (
    <div className="hour-wheel">
      <div ref={stage} className="hour-wheel__stage">
        <canvas ref={canvas} aria-hidden="true" />
      </div>
      <div className="hour-wheel__pointer" aria-hidden="true" />
      <div
        ref={choices}
        className="hour-wheel__choices"
        role="radiogroup"
        aria-label="Canonical hours"
      >
        {officeHours.map((hour) => (
          <button
            key={hour}
            type="button"
            role="radio"
            aria-checked={hour === selection}
            aria-label={OfficeHours.englishTitle(hour)}
            aria-description={`${hour === selection ? "Selected, " : ""}${OfficeHours.customaryTimeRange(hour)}`}
            tabIndex={hour === selection ? 0 : -1}
            onClick={() => controller.current?.chooseManually(hour)}
            onKeyDown={(event) => {
              if (["ArrowRight", "ArrowDown", "PageDown"].includes(event.key)) {
                event.preventDefault();
                controller.current?.selectAdjacentHour(1);
              } else if (
                ["ArrowLeft", "ArrowUp", "PageUp"].includes(event.key)
              ) {
                event.preventDefault();
                controller.current?.selectAdjacentHour(-1);
              }
            }}
          />
        ))}
      </div>
    </div>
  );
}
