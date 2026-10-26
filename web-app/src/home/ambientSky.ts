// The sky behind the hour wheel, as horarum.com paints it: a ground colour,
// a veil of night, and a wash of light down the page, each passing smoothly
// from one hour's to the next as the wheel turns beneath the pointer.
//
// This is the sky of `web/local-site/site.js`, ported; the wheel it follows
// is the site's own module. `tests/home/ambientSky.test.ts` holds the eight
// skies to the site's, so that the two pages cannot drift apart. The office
// reader and the Dial keep the native app's quieter sky (`styles.css`), which
// is made to be read over.

import { shortestWheelTarget, wheelAngleFor } from "@site/hour-wheel.js";
import { showThemeColor, type AppearanceState } from "@/app/appearanceState.ts";
import { officeHours, type OfficeHour } from "@/core/models.ts";

type Channels = readonly [number, number, number];

export interface AmbientSky {
  readonly background: Channels;
  readonly upper: Channels;
  readonly lower: Channels;
  readonly darkness: number;
  readonly accentStrength: number;
}

export const ambientSkies: Record<OfficeHour, AmbientSky> = {
  matins: {
    background: [0.025, 0.03, 0.055],
    upper: [0.05, 0.09, 0.22],
    lower: [0.12, 0.17, 0.33],
    darkness: 1,
    accentStrength: 0.54,
  },
  lauds: {
    background: [0.93, 0.92, 0.91],
    upper: [0.26, 0.3, 0.56],
    lower: [0.83, 0.49, 0.34],
    darkness: 0.24,
    accentStrength: 0.72,
  },
  prime: {
    background: [0.96, 0.97, 0.98],
    upper: [0.28, 0.56, 0.86],
    lower: [0.68, 0.76, 0.82],
    darkness: 0.12,
    accentStrength: 0.82,
  },
  terce: {
    background: [0.985, 0.99, 1],
    upper: [0.2, 0.57, 0.91],
    lower: [0.5, 0.74, 0.89],
    darkness: 0,
    accentStrength: 0.78,
  },
  sext: {
    background: [1, 1, 1],
    upper: [0.16, 0.58, 0.94],
    lower: [0.57, 0.78, 0.92],
    darkness: 0,
    accentStrength: 0.82,
  },
  none: {
    background: [0.98, 0.97, 0.94],
    upper: [0.28, 0.57, 0.86],
    lower: [0.66, 0.72, 0.79],
    darkness: 0.04,
    accentStrength: 0.76,
  },
  vespers: {
    background: [0.78, 0.5, 0.5],
    upper: [0.35, 0.3, 0.58],
    lower: [1, 0.5, 0.2],
    darkness: 0,
    accentStrength: 0.86,
  },
  compline: {
    background: [0.045, 0.075, 0.16],
    upper: [0.06, 0.11, 0.3],
    lower: [0.18, 0.24, 0.46],
    darkness: 0.72,
    accentStrength: 0.64,
  },
};

const nightTint: Channels = [9 / 255, 14 / 255, 33 / 255];

function mix(start: number, end: number, progress: number): number {
  return start + (end - start) * progress;
}

function mixChannels(
  start: Channels,
  end: Channels,
  progress: number,
): Channels {
  return [
    mix(start[0], end[0], progress),
    mix(start[1], end[1], progress),
    mix(start[2], end[2], progress),
  ];
}

function smoothstep(value: number): number {
  const clamped = Math.min(1, Math.max(0, value));
  return clamped * clamped * (3 - 2 * clamped);
}

/** The sky when the wheel stands at `rotation`: between two hours, their blend. */
export function ambientSkyForRotation(rotation: number): AmbientSky {
  const dialAngle = ((-rotation % 360) + 360) % 360;
  const centers = officeHours.map((hour) => wheelAngleFor(hour));
  for (let index = 0; index < officeHours.length; index += 1) {
    const nextIndex = (index + 1) % officeHours.length;
    const start = centers[index];
    const end = nextIndex === 0 ? centers[nextIndex] + 360 : centers[nextIndex];
    const angle =
      nextIndex === 0 && dialAngle < start ? dialAngle + 360 : dialAngle;
    if (angle >= start && angle < end) {
      const from = ambientSkies[officeHours[index]];
      const to = ambientSkies[officeHours[nextIndex]];
      const progress = smoothstep((angle - start) / (end - start));
      return {
        background: mixChannels(from.background, to.background, progress),
        upper: mixChannels(from.upper, to.upper, progress),
        lower: mixChannels(from.lower, to.lower, progress),
        darkness: mix(from.darkness, to.darkness, progress),
        accentStrength: mix(from.accentStrength, to.accentStrength, progress),
      };
    }
  }
  return ambientSkies.matins;
}

/** The colour at the head of the page, which the browser's own bars take. */
export function ambientTopColor(sky: AmbientSky): Channels {
  return mixChannels(
    mixChannels(sky.background, nightTint, 0.08 * sky.darkness),
    sky.upper,
    0.18 * sky.accentStrength,
  );
}

function rgb(channels: Channels): string {
  return channels.map((channel) => Math.round(channel * 255)).join(", ");
}

/** Where the wheel stands as the day turns: once round in twenty-four hours. */
export function liveWheelRotationAt(date: Date): number {
  const milliseconds =
    date.getHours() * 3_600_000 +
    date.getMinutes() * 60_000 +
    date.getSeconds() * 1_000 +
    date.getMilliseconds();
  return milliseconds === 0 ? 0 : -(milliseconds / 86_400_000) * 360;
}

/**
 * Where the wheel stands when Home opens: with the clock while it follows
 * the clock, and otherwise squarely on the hour selected.
 */
export function openingWheelRotation(
  selection: OfficeHour,
  followsLocalTime: boolean,
  reducesMotion: boolean,
  now: Date,
): number {
  return followsLocalTime && !reducesMotion
    ? liveWheelRotationAt(now)
    : shortestWheelTarget(selection, 0);
}

/** The sky lies under the wheel, in the Dynamic appearance. */
export function homeShowsSky(state: AppearanceState): boolean {
  return state.mode === "dynamic" && state.hourSelectionView === "wheel";
}

const properties = [
  "--home-sky-background",
  "--home-sky-top",
  "--home-sky-upper",
  "--home-sky-lower",
  "--home-sky-accent",
  "--home-sky-night",
] as const;

/**
 * Paints the sky for a wheel standing at `rotation`. The page takes it from
 * these properties (see "Home's sky" in `styles.css`), and the browser's
 * bars take the colour at its head.
 */
export function showHomeSky(root: HTMLElement, rotation: number): void {
  const values = homeSkyProperties(rotation);
  for (const property of properties)
    root.style.setProperty(property, values[property]);
  root.dataset.homeSky = "";
  showThemeColor(root, values["--home-sky-top"]);
}

/**
 * The properties of Home's sky for a wheel standing at `rotation`, which
 * Settings also sets on its small Homes.
 */
export function homeSkyProperties(
  rotation: number,
): Record<(typeof properties)[number], string> {
  const sky = ambientSkyForRotation(rotation);
  return {
    "--home-sky-background": `rgb(${rgb(sky.background)})`,
    "--home-sky-top": `rgb(${rgb(ambientTopColor(sky))})`,
    "--home-sky-upper": rgb(sky.upper),
    "--home-sky-lower": rgb(sky.lower),
    "--home-sky-accent": String(0.18 * sky.accentStrength),
    "--home-sky-night": String(0.08 * sky.darkness),
  };
}

/** Takes Home's sky away again, leaving the page its own. */
export function hideHomeSky(root: HTMLElement): void {
  if (root.dataset.homeSky === undefined) return;
  for (const property of properties) root.style.removeProperty(property);
  delete root.dataset.homeSky;
  showThemeColor(root);
}
