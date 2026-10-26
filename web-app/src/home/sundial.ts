// The Dial display's time and geometry, parallel to `SundialTimeMath`,
// `SundialLayout`, `SundialLaunchProjection`, `SundialPresentation`,
// `SundialInitialAnimationPlan`, `SundialAffordance`, and
// `SundialRefreshPolicy` in `HoursApp/CanonicalHourSundialView.swift`: where
// the gnomon's shadow falls at an hour of the day, how strong it is, and
// where the eight hours stand.
//
// A Swift `Calendar` is here a `WallClock`: the reading of a date on some
// clock. The default is the device's own.

import { OfficeHours, officeHours, type OfficeHour } from "@/core/models.ts";

export interface SundialShadow {
  readonly angleDegrees: number;
  readonly length: number;
  readonly centerlineDepth: number;
  readonly verticalProgress: number;
}

export interface SundialAmbientSky {
  readonly backgroundRed: number;
  readonly backgroundGreen: number;
  readonly backgroundBlue: number;
  readonly upperRed: number;
  readonly upperGreen: number;
  readonly upperBlue: number;
  readonly lowerRed: number;
  readonly lowerGreen: number;
  readonly lowerBlue: number;
  readonly darkness: number;
  readonly accentStrength: number;
  readonly shadowStrength: number;
}

/** The time a date shows on a clock. */
export interface WallClockTime {
  readonly hour: number;
  readonly minute: number;
  readonly second: number;
  readonly millisecond: number;
}

export type WallClock = (date: Date) => WallClockTime;

/** `Calendar.autoupdatingCurrent`: the device's own clock. */
export const localWallClock: WallClock = (date) => ({
  hour: date.getHours(),
  minute: date.getMinutes(),
  second: date.getSeconds(),
  millisecond: date.getMilliseconds(),
});

export interface Point {
  readonly x: number;
  readonly y: number;
}

export interface Size {
  readonly width: number;
  readonly height: number;
}

function smoothstep(value: number): number {
  const clamped = Math.min(Math.max(value, 0), 1);
  return clamped * clamped * (3 - 2 * clamped);
}

/** `truncatingRemainder(dividingBy:)`, which is JavaScript's `%`. */
function normalizedSeconds(seconds: number): number {
  const day = 24.0 * 3_600;
  return ((seconds % day) + day) % day;
}

function localSeconds(date: Date, calendar: WallClock): number {
  const components = calendar(date);
  return (
    components.hour * 3_600 +
    components.minute * 60 +
    components.second +
    components.millisecond / 1_000
  );
}

function canonicalSeconds(hour: OfficeHour): number {
  const index = Math.max(0, officeHours.indexOf(hour));
  return index * 3 * 3_600;
}

function projectedShadow(
  angleDegrees: number,
  length: number,
  verticalProgress: number,
): SundialShadow {
  const radians = (angleDegrees * Math.PI) / 180;
  const elevationProjection = Math.max(Math.cos(radians), 0);
  const fullCenterlineDepth = 0.035 + 0.28 * Math.pow(elevationProjection, 1.2);

  return {
    angleDegrees,
    length,
    centerlineDepth: length * fullCenterlineDepth,
    verticalProgress,
  };
}

function interpolateSky(
  start: SundialAmbientSky,
  end: SundialAmbientSky,
  progress: number,
): SundialAmbientSky {
  const channel = (startValue: number, endValue: number) =>
    startValue + (endValue - startValue) * progress;

  return {
    backgroundRed: channel(start.backgroundRed, end.backgroundRed),
    backgroundGreen: channel(start.backgroundGreen, end.backgroundGreen),
    backgroundBlue: channel(start.backgroundBlue, end.backgroundBlue),
    upperRed: channel(start.upperRed, end.upperRed),
    upperGreen: channel(start.upperGreen, end.upperGreen),
    upperBlue: channel(start.upperBlue, end.upperBlue),
    lowerRed: channel(start.lowerRed, end.lowerRed),
    lowerGreen: channel(start.lowerGreen, end.lowerGreen),
    lowerBlue: channel(start.lowerBlue, end.lowerBlue),
    darkness: channel(start.darkness, end.darkness),
    accentStrength: channel(start.accentStrength, end.accentStrength),
    shadowStrength: channel(start.shadowStrength, end.shadowStrength),
  };
}

function sky(
  background: readonly [number, number, number],
  upper: readonly [number, number, number],
  lower: readonly [number, number, number],
  darkness: number,
  accentStrength: number,
  shadowStrength: number,
): SundialAmbientSky {
  return {
    backgroundRed: background[0],
    backgroundGreen: background[1],
    backgroundBlue: background[2],
    upperRed: upper[0],
    upperGreen: upper[1],
    upperBlue: upper[2],
    lowerRed: lower[0],
    lowerGreen: lower[1],
    lowerBlue: lower[2],
    darkness,
    accentStrength,
    shadowStrength,
  };
}

/** The sky at the head of each canonical hour, Matins to Compline. */
const ambientSkyKeyframes: readonly SundialAmbientSky[] = [
  sky([0.025, 0.03, 0.055], [0.05, 0.09, 0.22], [0.12, 0.17, 0.33], 1, 0.54, 0),
  sky(
    [0.93, 0.92, 0.91],
    [0.26, 0.3, 0.56],
    [0.83, 0.49, 0.34],
    0.24,
    0.72,
    0.26,
  ),
  sky(
    [0.96, 0.97, 0.98],
    [0.28, 0.56, 0.86],
    [0.68, 0.76, 0.82],
    0.12,
    0.82,
    0.76,
  ),
  sky([0.985, 0.99, 1], [0.2, 0.57, 0.91], [0.5, 0.74, 0.89], 0, 0.78, 0.92),
  sky([1, 1, 1], [0.16, 0.58, 0.94], [0.57, 0.78, 0.92], 0, 0.82, 1),
  sky(
    [0.98, 0.97, 0.94],
    [0.28, 0.57, 0.86],
    [0.66, 0.72, 0.79],
    0.04,
    0.76,
    0.84,
  ),
  sky(
    [0.93, 0.91, 0.9],
    [0.32, 0.28, 0.54],
    [0.86, 0.39, 0.27],
    0.18,
    0.7,
    0.3,
  ),
  sky([0.025, 0.03, 0.055], [0.05, 0.09, 0.22], [0.12, 0.17, 0.33], 1, 0.54, 0),
];

export const SundialTimeMath = {
  angle(hour: OfficeHour): number {
    switch (hour) {
      case "matins":
      case "lauds":
        return -90;
      case "prime":
        return -60;
      case "terce":
        return -30;
      case "sext":
        return 0;
      case "none":
        return 30;
      case "vespers":
        return 60;
      case "compline":
        return 90;
    }
  },

  /** `shadow(for:)`. */
  shadow(hour: OfficeHour): SundialShadow {
    return SundialTimeMath.shadowAtSeconds(canonicalSeconds(hour));
  },

  /** `ambientSky(for:)`. */
  ambientSky(hour: OfficeHour): SundialAmbientSky {
    return SundialTimeMath.ambientSkyAtSeconds(canonicalSeconds(hour));
  },

  prefersDarkAppearance(hour: OfficeHour): boolean {
    return hour === "matins" || hour === "compline";
  },

  /** `shadow(at:calendar:)`. */
  shadowAt(date: Date, calendar: WallClock = localWallClock): SundialShadow {
    return SundialTimeMath.shadowAtSeconds(localSeconds(date, calendar));
  },

  /** `ambientSky(at:calendar:)`. */
  ambientSkyAt(
    date: Date,
    calendar: WallClock = localWallClock,
  ): SundialAmbientSky {
    return SundialTimeMath.ambientSkyAtSeconds(localSeconds(date, calendar));
  },

  displayedAmbientSky(selection: OfficeHour): SundialAmbientSky {
    return SundialTimeMath.ambientSky(selection);
  },

  /** `ambientSky(secondsAfterMidnight:)`. */
  ambientSkyAtSeconds(seconds: number): SundialAmbientSky {
    const normalized = normalizedSeconds(seconds);
    const segmentDuration = 3.0 * 3_600;
    const segment = Math.trunc(normalized / segmentDuration);
    const nextSegment = (segment + 1) % ambientSkyKeyframes.length;
    const rawProgress =
      (normalized - segment * segmentDuration) / segmentDuration;
    return interpolateSky(
      ambientSkyKeyframes[segment],
      ambientSkyKeyframes[nextSegment],
      smoothstep(rawProgress),
    );
  },

  /** `shadow(secondsAfterMidnight:)`. */
  shadowAtSeconds(seconds: number): SundialShadow {
    const threeHours = 3.0 * 3_600;
    const normalized = normalizedSeconds(seconds);
    const complineStart = 21.0 * 3_600;

    if (normalized < threeHours) {
      return projectedShadow(
        -90,
        normalized / threeHours,
        normalized / complineStart,
      );
    }

    const vespersStart = 18.0 * 3_600;

    if (normalized <= vespersStart) {
      const progress = (normalized - threeHours) / (vespersStart - threeHours);
      return projectedShadow(
        -90 + 150 * progress,
        1,
        normalized / complineStart,
      );
    }

    if (normalized < complineStart) {
      const progress = (normalized - vespersStart) / threeHours;
      return projectedShadow(
        60 + 30 * progress,
        1 - smoothstep(progress),
        normalized / complineStart,
      );
    }

    return projectedShadow(90, 0, 1);
  },
};

export const SundialRefreshPolicy = {
  /** Seconds between readings of the clock while the dial follows it. */
  liveInterval: 5 * 60,
};

export interface SundialPresentation {
  readonly shadow: SundialShadow;
  readonly strength: number;
}

export const SundialPresentations = {
  matins: {
    shadow: SundialTimeMath.shadow("matins"),
    strength: 0,
  } satisfies SundialPresentation,

  lauds: {
    shadow: SundialTimeMath.shadow("lauds"),
    strength: SundialTimeMath.ambientSky("lauds").shadowStrength,
  } satisfies SundialPresentation,

  /** `SundialPresentation.live(for:)`. */
  live(hour: OfficeHour): SundialPresentation {
    return {
      shadow: SundialTimeMath.shadow(hour),
      strength: SundialTimeMath.ambientSky(hour).shadowStrength,
    };
  },
};

export const SundialInitialAnimationPlan = {
  /**
   * Where the shadow is sent as the dial first appears: to the hour the
   * clock shows, or nowhere at Matins, which has no shadow.
   */
  presentation(
    date: Date,
    calendar: WallClock = localWallClock,
  ): SundialPresentation | null {
    const time = calendar(date);
    // The hour is a matter of the clock's reading alone.
    const hour = OfficeHours.current(
      new Date(2001, 0, 1, time.hour, time.minute),
    );

    if (hour === "matins") return null;
    return SundialPresentations.live(hour);
  },
};

export const SundialAffordance = {
  showsSelectionChevron(hour: OfficeHour, shadowsEnabled: boolean): boolean {
    return !shadowsEnabled || SundialTimeMath.prefersDarkAppearance(hour);
  },
};

const minimumHourRowSpacing = 50;
const hourLabelWidth = 120;
const disclosureSpacing = 12;
const disclosureWidth = 16;
const hourRowWidth = hourLabelWidth + disclosureSpacing + disclosureWidth;
const minimumHeight = (officeHours.length - 1) * minimumHourRowSpacing + 88;
const laudsProgress = 1.0 / (officeHours.length - 1);
const topRowY = 22;

/** The dial's geometry in a space of a given size. */
export class SundialLayout {
  static readonly minimumHourRowSpacing = minimumHourRowSpacing;
  static readonly hourLabelWidth = hourLabelWidth;
  static readonly disclosureSpacing = disclosureSpacing;
  static readonly disclosureWidth = disclosureWidth;
  static readonly hourRowWidth = hourRowWidth;
  static readonly minimumHeight = minimumHeight;

  readonly size: Size;

  constructor(size: Size) {
    this.size = size;
  }

  private get labelTrailingPadding(): number {
    return Math.max(16, Math.min(24, this.size.width * 0.05));
  }

  private get hourRowLeadingEdge(): number {
    return Math.max(
      0,
      this.size.width - hourRowWidth - this.labelTrailingPadding,
    );
  }

  private get bottomHourRowY(): number {
    return Math.max(topRowY, this.size.height - 66);
  }

  private get rowSpacing(): number {
    return Math.max(
      minimumHourRowSpacing,
      (this.bottomHourRowY - topRowY) / Math.max(officeHours.length - 1, 1),
    );
  }

  private get shadowOrigin(): Point {
    return {
      x: -Math.max(18, this.size.width * 0.045),
      y: topRowY + this.rowSpacing * 3.5,
    };
  }

  get shadowOuterBlurRadius(): number {
    return Math.max(2.6, Math.min(5, this.size.width * 0.011));
  }

  get shadowInnerBlurRadius(): number {
    return Math.max(1, Math.min(2, this.size.width * 0.004));
  }

  /** The centre of an hour's row. */
  labelPosition(hour: OfficeHour): Point {
    const index = Math.max(0, officeHours.indexOf(hour));
    return {
      x: this.hourRowLeadingEdge + hourRowWidth / 2,
      y: topRowY + index * this.rowSpacing,
    };
  }

  /**
   * The corners of the shadow, from the upper edge of its base to its tip
   * and back to the lower edge; none where there is no shadow to draw.
   */
  shadowPath(shadow: SundialShadow): Point[] {
    const entranceProgress = Math.min(Math.max(shadow.length, 0), 1);
    const isEntrance = shadow.verticalProgress <= laudsProgress + 0.000_1;
    if (!(isEntrance || shadow.length > 0.001)) {
      return [];
    }

    const fullSourceHalfHeight = Math.max(
      8,
      Math.min(14, this.size.height * 0.024),
    );
    const sourceHalfHeight = isEntrance
      ? 0.75 + (fullSourceHalfHeight - 0.75) * smoothstep(entranceProgress)
      : fullSourceHalfHeight * shadow.length;
    const tip = this.shadowTip(shadow);
    const origin = this.shadowOrigin;

    return [
      { x: origin.x, y: origin.y - sourceHalfHeight },
      tip,
      { x: origin.x, y: origin.y + sourceHalfHeight },
    ];
  }

  shadowTip(shadow: SundialShadow): Point {
    if (!(shadow.verticalProgress <= laudsProgress)) {
      return this.shadowTarget(shadow.verticalProgress);
    }
    return this.entranceTip(Math.min(Math.max(shadow.length, 0), 1));
  }

  shadowSource(_shadow: SundialShadow): Point {
    return this.shadowOrigin;
  }

  private shadowTarget(verticalProgress: number): Point {
    const progress = Math.min(Math.max(verticalProgress, 0), 1);
    return {
      x: this.hourRowLeadingEdge + hourLabelWidth * 0.42,
      y: topRowY + (this.bottomHourRowY - topRowY) * progress,
    };
  }

  /** Before Lauds the shadow enters along a curve from above the dial. */
  private entranceTip(progress: number): Point {
    const { width, height } = this.size;
    const start = {
      x: Math.max(4, width * 0.025),
      y: -Math.max(8, height * 0.02),
    };
    const end = this.shadowTarget(laudsProgress);
    const control1 = {
      x: start.x + width * 0.025,
      y: start.y + height * 0.04,
    };
    const control2 = { x: end.x * 0.52, y: end.y * 0.42 };
    const inverse = 1 - progress;
    const startWeight = inverse * inverse * inverse;
    const control1Weight = 3 * inverse * inverse * progress;
    const control2Weight = 3 * inverse * progress * progress;
    const endWeight = progress * progress * progress;
    return {
      x:
        start.x * startWeight +
        control1.x * control1Weight +
        control2.x * control2Weight +
        end.x * endWeight,
      y:
        start.y * startWeight +
        control1.y * control1Weight +
        control2.y * control2Weight +
        end.y * endWeight,
    };
  }
}

export const SundialLaunchProjection = {
  entranceFraction: 0.45,

  /**
   * The shadow part of the way through its first appearance: it enters to
   * where it lies at Lauds, and travels from there to the hour.
   */
  shadow(target: SundialShadow, progress: number): SundialShadow {
    const clamped = Math.min(Math.max(progress, 0), 1);
    const lauds = SundialTimeMath.shadow("lauds");

    if (!(clamped < 1)) return target;

    if (clamped <= SundialLaunchProjection.entranceFraction) {
      const entranceProgress =
        clamped / SundialLaunchProjection.entranceFraction;
      return {
        angleDegrees: -90,
        length: entranceProgress,
        centerlineDepth: lauds.centerlineDepth * entranceProgress,
        verticalProgress: lauds.verticalProgress * entranceProgress,
      };
    }

    const travelProgress =
      (clamped - SundialLaunchProjection.entranceFraction) /
      (1 - SundialLaunchProjection.entranceFraction);
    return {
      angleDegrees:
        lauds.angleDegrees +
        (target.angleDegrees - lauds.angleDegrees) * travelProgress,
      length: lauds.length + (target.length - lauds.length) * travelProgress,
      centerlineDepth:
        lauds.centerlineDepth +
        (target.centerlineDepth - lauds.centerlineDepth) * travelProgress,
      verticalProgress:
        lauds.verticalProgress +
        (target.verticalProgress - lauds.verticalProgress) * travelProgress,
    };
  },
};

/** `CanonicalHourSundialView.idealHeight(for:)`. */
export function sundialIdealHeight(width: number): number {
  return Math.max(width / 0.74, minimumHeight);
}
