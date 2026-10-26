// The app's appearance, parallel to `HoursApp/AppSettings.swift`.
// Dynamic follows the canonical hour on screen: dark for the night hours,
// Matins and Compline, and light for the rest. System follows the device.

import type { OfficeHour } from "@/core/models.ts";
import {
  savedAppearance,
  showAppearance,
  type AppearanceMode,
  type AppearanceState,
  type HourSelectionView,
} from "./appearanceState.ts";
import { Preferences, preferenceKeys } from "./preferences.ts";
import { Store } from "./store.ts";

export class Appearance {
  readonly store: Store<AppearanceState>;
  private readonly preferences: Preferences;

  /**
   * `displayedHour` is the hour the visit opens with. The page has worn its
   * appearance since before it was first painted, and a store that began
   * with no hour would take it off again until a screen named one.
   */
  constructor(
    preferences: Preferences,
    displayedHour: OfficeHour | null = null,
  ) {
    this.preferences = preferences;
    const query = globalThis.matchMedia?.("(prefers-color-scheme: dark)");
    this.store = new Store<AppearanceState>(
      savedAppearance(preferences, displayedHour, query?.matches ?? false),
    );
    query?.addEventListener("change", (event) => {
      this.store.update({ systemIsDark: event.matches });
    });
    this.store.subscribe(() => this.apply());
    this.apply();
  }

  setMode(mode: AppearanceMode): void {
    this.store.update({ mode });
    this.preferences.set(preferenceKeys.appearanceMode, mode);
  }

  setHourSelectionView(hourSelectionView: HourSelectionView): void {
    this.store.update({ hourSelectionView });
    this.preferences.set(preferenceKeys.hourSelectionView, hourSelectionView);
  }

  setDisplayedHour(displayedHour: OfficeHour | null): void {
    this.store.update({ displayedHour });
  }

  private apply(): void {
    const root = globalThis.document?.documentElement;
    if (root) showAppearance(root, this.store.value);
  }
}
