// What the app's appearance is at a given moment, and how the page is made
// to wear it. This is kept apart from the store that holds it
// (`appearance.ts`) so that the page can be given its appearance before the
// app has arrived (see `src/firstPaint.ts`), by the rule the app follows.

import type { OfficeHour } from "@/core/models.ts";
import { preferenceKeys, type Preferences } from "./preferences.ts";
import { officeAtPath } from "./routes.ts";

export type AppearanceMode = "dynamic" | "system";
export type HourSelectionView = "wheel" | "sunDial";

export interface AppearanceState {
  readonly mode: AppearanceMode;
  readonly hourSelectionView: HourSelectionView;
  /** The hour now shown: the wheel's live hour, else the selected or open one. */
  readonly displayedHour: OfficeHour | null;
  readonly systemIsDark: boolean;
}

export function isNightHour(hour: OfficeHour): boolean {
  return hour === "matins" || hour === "compline";
}

export function isDark(state: AppearanceState): boolean {
  if (state.mode === "system" || state.displayedHour === null) {
    return state.mode === "system" ? state.systemIsDark : false;
  }
  return isNightHour(state.displayedHour);
}

/**
 * The hour a visit first shows: that of the office its address names, and
 * otherwise the hour selected, which Home shows and a guide is opened over.
 */
export function openingHour(
  pathname: string,
  selectedHour: OfficeHour,
): OfficeHour {
  return officeAtPath(pathname)?.hour ?? selectedHour;
}

/** The appearance as the reader's settings leave it, for an hour and a device. */
export function savedAppearance(
  preferences: Preferences,
  displayedHour: OfficeHour | null,
  systemIsDark: boolean,
): AppearanceState {
  return {
    mode:
      preferences.string(preferenceKeys.appearanceMode) === "system"
        ? "system"
        : "dynamic",
    hourSelectionView:
      preferences.string(preferenceKeys.hourSelectionView) === "sunDial"
        ? "sunDial"
        : "wheel",
    displayedHour,
    systemIsDark,
  };
}

/**
 * Gives the browser's own bars a colour: the page's, unless another is
 * named. (Home names the head of its sky; see `src/home/ambientSky.ts`.)
 */
export function showThemeColor(
  root: HTMLElement,
  color = root.dataset.theme === "dark" ? "#000000" : "#ffffff",
): void {
  const meta = root.ownerDocument?.querySelector<HTMLMetaElement>(
    'meta[name="theme-color"]',
  );
  if (meta) meta.content = color;
}

/** Marks the document with an appearance, for the stylesheet to follow. */
export function showAppearance(
  root: HTMLElement,
  state: AppearanceState,
): void {
  root.dataset.theme = isDark(state) ? "dark" : "light";
  if (root.dataset.homeSky === undefined) showThemeColor(root);
  // The sky is painted only in the Dynamic appearance.
  if (state.mode === "dynamic" && state.displayedHour) {
    root.dataset.sky = state.displayedHour;
  } else {
    delete root.dataset.sky;
  }
}
