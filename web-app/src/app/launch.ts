// What a visit begins with, as the last one left it: the edition, the office
// that was open, and the hour selected. It is read from the preferences
// alone and waits upon nothing, so that the page can be given the appearance
// of its hour before the app has arrived (see `src/firstPaint.ts`).

import {
  LocalDays,
  OfficeHours,
  type LocalDay,
  type OfficeHour,
} from "@/core/models.ts";
import {
  OfficeTraditions,
  defaultOfficeTradition,
  type OfficeTradition,
} from "./officeTradition.ts";
import { preferenceKeys, type Preferences } from "./preferences.ts";
import { officeAtPath } from "./routes.ts";

/** Where the reader stood in an office, so that it can be found again. */
export interface OfficeReaderScrollAnchor {
  /** The first section in view. */
  readonly sectionID: string;
  /** How far that section's top lay from the top of the reading area. */
  readonly offset: number;
}

/** A page of the reader: the Latin, or the English. A reader that shows
 * both languages sets each on a page of its own and turns between them. */
export type ReaderPage = "latin" | "english";

export interface ReaderSession {
  readonly day: LocalDay;
  readonly hour: OfficeHour;
  scrollOffset: number;
  scrollAnchor: OfficeReaderScrollAnchor | null;
  /** The page the reader is turned to, where it shows both languages. */
  page: ReaderPage;
}

export interface Launch {
  readonly officeTradition: OfficeTradition;
  readonly automaticallySelectsCurrentOffice: boolean;
  /** The office left open at the last visit, if it was of this edition. */
  readonly readerSession: ReaderSession | null;
  readonly selectedHour: OfficeHour;
}

export function sanitizedReaderScrollOffset(scrollOffset: number): number {
  return Number.isFinite(scrollOffset) ? Math.max(0, scrollOffset) : 0;
}

function restoredReaderSession(
  preferences: Preferences,
  selectedTradition: OfficeTradition,
): ReaderSession | null {
  const savedTradition =
    preferences.string(preferenceKeys.readerTradition) ??
    defaultOfficeTradition;
  if (selectedTradition !== savedTradition) return null;
  if (!preferences.bool(preferenceKeys.readerIsPresented)) return null;
  const day = LocalDays.fromISO(
    preferences.string(preferenceKeys.readerDay) ?? "",
  );
  const hour = preferences.string(preferenceKeys.readerHour);
  if (!day || !OfficeHours.isOfficeHour(hour)) return null;
  return {
    day,
    hour,
    scrollOffset: sanitizedReaderScrollOffset(
      preferences.double(preferenceKeys.readerScrollOffset),
    ),
    scrollAnchor: preferences.json<OfficeReaderScrollAnchor>(
      preferenceKeys.readerScrollAnchor,
    ),
    page:
      preferences.string(preferenceKeys.readerPage) === "english"
        ? "english"
        : "latin",
  };
}

/**
 * The hour selected is that of the office left open; else the hour last
 * chosen by hand, if the reader chooses by hand; else the hour of the clock.
 *
 * On the web an office is open only at its own address. Given the address of
 * the visit, an office left open is returned to there and nowhere else: Home
 * begins as though it had been closed, and so follows the clock.
 */
export function launch(
  preferences: Preferences,
  now: Date,
  pathname?: string,
): Launch {
  const savedTradition = preferences.string(preferenceKeys.officeTradition);
  const officeTradition = OfficeTraditions.isOfficeTradition(savedTradition)
    ? savedTradition
    : defaultOfficeTradition;
  const automaticallySelectsCurrentOffice = preferences.has(
    preferenceKeys.automaticOfficeSelection,
  )
    ? preferences.bool(preferenceKeys.automaticOfficeSelection)
    : true;

  const left = restoredReaderSession(preferences, officeTradition);
  const addressed = pathname === undefined ? null : officeAtPath(pathname);
  const readerSession =
    left &&
    (pathname === undefined ||
      (addressed !== null &&
        addressed.hour === left.hour &&
        LocalDays.equals(addressed.day, left.day)))
      ? left
      : null;
  const savedHour = preferences.string(preferenceKeys.manuallySelectedHour);
  let selectedHour: OfficeHour;
  if (readerSession) {
    selectedHour = readerSession.hour;
  } else if (
    !automaticallySelectsCurrentOffice &&
    OfficeHours.isOfficeHour(savedHour)
  ) {
    selectedHour = savedHour;
  } else {
    selectedHour = OfficeHours.current(now);
  }

  return {
    officeTradition,
    automaticallySelectsCurrentOffice,
    readerSession,
    selectedHour,
  };
}
