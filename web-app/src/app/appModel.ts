// What is selected, what is loaded, and what the reader has chosen: the web
// counterpart of `HoursApp/AppModel.swift`, kept parallel to it.

import {
  LocalDays,
  OfficeHours,
  type LocalDay,
  type OfficeDocument,
  type OfficeHour,
} from "@/core/models.ts";
import { Corpus, CorpusError, type CalendarDay } from "@/data/corpus.ts";
import {
  launch,
  sanitizedReaderScrollOffset,
  type OfficeReaderScrollAnchor,
  type ReaderPage,
  type ReaderSession,
} from "./launch.ts";
import type { OfficeTradition } from "./officeTradition.ts";
import { Preferences, preferenceKeys } from "./preferences.ts";
import { Store } from "./store.ts";

export interface AppState {
  /** The edition's first and last civil dates, once known. */
  readonly coverage: {
    readonly start: LocalDay;
    readonly end: LocalDay;
  } | null;
  readonly selectedDay: CalendarDay | null;
  readonly office: OfficeDocument | null;
  readonly isLoading: boolean;
  readonly errorMessage: string | null;
  readonly officeTradition: OfficeTradition;
  readonly isChangingTradition: boolean;
  readonly traditionErrorMessage: string | null;
  readonly selectedHour: OfficeHour;
  readonly automaticallySelectsCurrentOffice: boolean;
  readonly isReaderSessionActive: boolean;
  readonly selectedCivilDate: LocalDay;
  readonly showsEnglish: boolean;
  /** Whether the Latin is shown; without it, the English stands alone. */
  readonly showsLatin: boolean;
  /** Whether the Latin is sung from its notation, where it has chant. */
  readonly showsChant: boolean;
  readonly notationScale: number;
  readonly usesCompactPsalmody: boolean;
  readonly isPriestOrDeaconPresent: boolean;
  /** Whether a Mass shows its Ordinary, or the propers of the day alone. */
  readonly showsMassOrdinary: boolean;
  /** The page a reader of both languages is turned to. */
  readonly turnedPage: ReaderPage;
}

export type { ReaderPage };

/** The languages of the reader's text: the Latin, both, or the English. */
export type ReaderLanguage = "latin" | "both" | "english";

export function readerLanguage(
  state: Pick<AppState, "showsLatin" | "showsEnglish">,
): ReaderLanguage {
  if (state.showsLatin && !state.showsEnglish) return "latin";
  if (!state.showsLatin && state.showsEnglish) return "english";
  return "both";
}

/**
 * The page the reader shows: the language chosen, or, where both are, the
 * page it is turned to.
 */
export function readerPage(
  state: Pick<AppState, "showsLatin" | "showsEnglish" | "turnedPage">,
): ReaderPage {
  switch (readerLanguage(state)) {
    case "latin":
      return "latin";
    case "english":
      return "english";
    case "both":
      return state.turnedPage;
  }
}

/** Whether the chant is shown: the Latin, sung from its notation. */
export function showsScores(
  state: Pick<AppState, "showsLatin" | "showsChant">,
): boolean {
  return state.showsLatin && state.showsChant;
}

export const defaultNotationScale = 1.0;
export const notationScaleRange = {
  minimum: 0.6,
  maximum: 1.6,
  step: 0.1,
} as const;

function describe(error: unknown): string {
  if (error instanceof CorpusError) {
    switch (error.failure) {
      case "offline":
        return "The Office could not be loaded. Check the connection and try again.";
      case "outdated":
        return "This copy of Hours is out of date. Reload the page to update it.";
      case "unavailable":
        return "This office is not available.";
    }
  }
  return error instanceof Error ? error.message : String(error);
}

export class AppModel {
  readonly store: Store<AppState>;
  private readonly corpus: Corpus;
  private readonly preferences: Preferences;
  private readonly now: () => Date;
  private readerSession: ReaderSession | null;
  private hasCompletedStartup = false;
  private isStarting = false;
  private startup: Promise<void> | null = null;
  private selectionGeneration = 0;

  /** `pathname` is the address of the visit, which the native app has not. */
  constructor(
    corpus: Corpus,
    preferences: Preferences,
    now: () => Date = () => new Date(),
    pathname?: string,
  ) {
    this.corpus = corpus;
    this.preferences = preferences;
    this.now = now;

    const opening = launch(preferences, now(), pathname);
    this.readerSession = opening.readerSession;

    this.store = new Store<AppState>({
      coverage: null,
      selectedDay: null,
      office: null,
      isLoading: false,
      errorMessage: null,
      officeTradition: opening.officeTradition,
      isChangingTradition: false,
      traditionErrorMessage: null,
      selectedHour: opening.selectedHour,
      automaticallySelectsCurrentOffice:
        opening.automaticallySelectsCurrentOffice,
      isReaderSessionActive: this.readerSession !== null,
      selectedCivilDate: LocalDays.fromDate(now()),
      showsEnglish: preferences.bool(preferenceKeys.showsEnglish),
      // The Latin is shown unless the English is shown alone.
      showsLatin:
        !preferences.has(preferenceKeys.showsLatin) ||
        preferences.bool(preferenceKeys.showsLatin) ||
        !preferences.bool(preferenceKeys.showsEnglish),
      showsChant: preferences.has(preferenceKeys.showsChant)
        ? preferences.bool(preferenceKeys.showsChant)
        : true,
      notationScale: preferences.has(preferenceKeys.notationScale)
        ? AppModel.clampedNotationScale(
            preferences.double(preferenceKeys.notationScale),
          )
        : defaultNotationScale,
      usesCompactPsalmody: preferences.bool(preferenceKeys.compactPsalmody),
      isPriestOrDeaconPresent: preferences.bool(
        preferenceKeys.priestOrDeaconPresent,
      ),
      showsMassOrdinary: preferences.has(preferenceKeys.showsMassOrdinary)
        ? preferences.bool(preferenceKeys.showsMassOrdinary)
        : true,
      turnedPage: this.readerSession?.page ?? "latin",
    });
  }

  static clampedNotationScale(scale: number): number {
    return Math.max(
      notationScaleRange.minimum,
      Math.min(notationScaleRange.maximum, scale),
    );
  }

  get state(): AppState {
    return this.store.value;
  }

  get isDevelopmentCorpus(): boolean {
    return this.state.office?.format === "legacyReconstructed";
  }

  // MARK: Prayer options

  /** The English shown or hidden; hidden, the Latin is shown. */
  setShowsEnglish(showsEnglish: boolean): void {
    this.setLanguages(this.state.showsLatin || !showsEnglish, showsEnglish);
  }

  /** The Latin shown or hidden; hidden, the English is shown alone. */
  setShowsLatin(showsLatin: boolean): void {
    this.setLanguages(showsLatin, this.state.showsEnglish || !showsLatin);
  }

  setReaderLanguage(language: ReaderLanguage): void {
    // Both chosen, the reader stays on the page it shows.
    const page = readerPage(this.state);
    this.setLanguages(language !== "english", language !== "latin");
    if (language === "both") this.turnReaderPage(page);
  }

  /**
   * Turns a reader of both languages to one of its pages, which an office
   * shows again on its return. A reader of one language has but one page.
   */
  turnReaderPage(page: ReaderPage): void {
    if (readerLanguage(this.state) !== "both") return;
    this.store.update({ turnedPage: page });
    if (this.readerSession) {
      this.readerSession.page = page;
      this.preferences.set(preferenceKeys.readerPage, page);
    }
  }

  /** A Mass newly opened begins on its Latin page; it keeps no place. */
  beginMass(): void {
    this.store.update({ turnedPage: "latin" });
  }

  setShowsChant(showsChant: boolean): void {
    this.store.update({ showsChant });
    this.preferences.set(preferenceKeys.showsChant, showsChant);
  }

  private setLanguages(showsLatin: boolean, showsEnglish: boolean): void {
    this.store.update({ showsLatin, showsEnglish });
    this.preferences.set(preferenceKeys.showsLatin, showsLatin);
    this.preferences.set(preferenceKeys.showsEnglish, showsEnglish);
  }

  setNotationScale(scale: number): void {
    const notationScale = AppModel.clampedNotationScale(scale);
    this.store.update({ notationScale });
    this.preferences.set(preferenceKeys.notationScale, notationScale);
  }

  setUsesCompactPsalmody(usesCompactPsalmody: boolean): void {
    this.store.update({ usesCompactPsalmody });
    this.preferences.set(preferenceKeys.compactPsalmody, usesCompactPsalmody);
  }

  setPriestOrDeaconPresent(isPriestOrDeaconPresent: boolean): void {
    this.store.update({ isPriestOrDeaconPresent });
    this.preferences.set(
      preferenceKeys.priestOrDeaconPresent,
      isPriestOrDeaconPresent,
    );
  }

  setShowsMassOrdinary(showsMassOrdinary: boolean): void {
    this.store.update({ showsMassOrdinary });
    this.preferences.set(preferenceKeys.showsMassOrdinary, showsMassOrdinary);
  }

  // MARK: Startup

  /** Finds the edition and opens the office to begin with. Safe to call again. */
  start(): Promise<void> {
    if (this.startup) return this.startup;
    if (this.hasCompletedStartup && this.state.selectedDay !== null) {
      return Promise.resolve();
    }
    this.isStarting = true;
    this.store.update({ isLoading: true });
    this.startup = this.performStartup().finally(() => {
      this.isStarting = false;
      this.startup = null;
      this.store.update({ isLoading: false });
    });
    return this.startup;
  }

  private async performStartup(): Promise<void> {
    try {
      const coverage = await this.corpus.coverage(this.state.officeTradition);
      this.store.update({ coverage });

      // Automatic selection follows the civil date: Matins after
      // midnight belongs to the new liturgical day.
      const now = this.now();
      const currentHour = OfficeHours.current(now);
      const currentDay = LocalDays.currentOfficeDay(now);
      let initialHour: OfficeHour;
      let initialDay: LocalDay;
      if (this.readerSession && this.covers(coverage, this.readerSession.day)) {
        initialHour = this.readerSession.hour;
        initialDay = this.readerSession.day;
        this.store.update({ selectedHour: initialHour });
      } else if (this.state.automaticallySelectsCurrentOffice) {
        if (this.readerSession) this.endReaderSession();
        initialHour = currentHour;
        initialDay = currentDay;
        this.store.update({ selectedHour: currentHour });
      } else {
        if (this.readerSession) this.endReaderSession();
        initialHour = this.state.selectedHour;
        initialDay = currentDay;
      }
      const initial = this.covers(coverage, initialDay)
        ? initialDay
        : coverage.start;
      this.store.update({ selectedCivilDate: initial });
      await this.select(initial, initialHour);
      this.hasCompletedStartup =
        this.state.selectedDay !== null && this.state.office !== null;
    } catch (error) {
      this.store.update({ errorMessage: describe(error) });
    }
  }

  private covers(
    coverage: { readonly start: LocalDay; readonly end: LocalDay },
    day: LocalDay,
  ): boolean {
    return (
      LocalDays.compare(day, coverage.start) >= 0 &&
      LocalDays.compare(day, coverage.end) <= 0
    );
  }

  async refreshAfterBecomingActive(): Promise<void> {
    if (this.startup) await this.startup;
    if (this.state.isReaderSessionActive) return;
    if (this.state.selectedDay === null) {
      await this.start();
      return;
    }
    if (this.state.automaticallySelectsCurrentOffice) {
      await this.selectCurrentOffice();
    } else if (this.state.office === null) {
      await this.selectHour(this.state.selectedHour);
    }
  }

  // MARK: Selection

  /** The day so many days from the selected one, or null beyond the edition. */
  async availableDay(
    offsetFromSelectedBy: number,
  ): Promise<CalendarDay | null> {
    const selected = this.state.selectedDay?.date;
    const coverage = this.state.coverage;
    if (!selected || !coverage) return null;
    const day = LocalDays.adding(selected, offsetFromSelectedBy);
    if (!this.covers(coverage, day)) return null;
    try {
      return await this.corpus.day(this.state.officeTradition, day);
    } catch {
      return null;
    }
  }

  setAutomaticOfficeSelection(isEnabled: boolean): void {
    this.store.update({ automaticallySelectsCurrentOffice: isEnabled });
    this.preferences.set(preferenceKeys.automaticOfficeSelection, isEnabled);
    if (!isEnabled) {
      this.preferences.set(
        preferenceKeys.manuallySelectedHour,
        this.state.selectedHour,
      );
    }
  }

  async selectCurrentOffice(at: Date = this.now()): Promise<void> {
    if (
      !this.state.automaticallySelectsCurrentOffice ||
      this.state.isReaderSessionActive
    ) {
      return;
    }
    const hour = OfficeHours.current(at);
    const day = LocalDays.currentOfficeDay(at);
    this.setSelectedHour(hour);
    this.store.update({ selectedCivilDate: day });
    await this.select(day, hour);
  }

  /** Choosing a date is a manual act: it ends automatic selection. */
  async selectCivilDate(day: LocalDay): Promise<void> {
    if (this.state.automaticallySelectsCurrentOffice) {
      this.setAutomaticOfficeSelection(false);
    }
    this.store.update({ selectedCivilDate: day });
    await this.select(day, this.state.selectedHour);
  }

  async selectHour(hour: OfficeHour): Promise<void> {
    this.setSelectedHour(hour);
    const selectedDay = this.state.selectedDay;
    if (!selectedDay) return;
    await this.select(selectedDay.date, hour);
  }

  /** Opens a particular office, as from a search result or a link. */
  async selectOffice(day: LocalDay, hour: OfficeHour): Promise<void> {
    this.setSelectedHour(hour);
    this.store.update({ selectedCivilDate: day });
    await this.select(day, hour);
  }

  /**
   * Names the selected hour without loading its office: the wheel reports
   * the hour it is turning to at once, and the office follows when it rests.
   */
  setSelectedHour(hour: OfficeHour): void {
    if (this.state.selectedHour === hour) return;
    this.store.update({ selectedHour: hour });
    if (!this.state.automaticallySelectsCurrentOffice) {
      this.preferences.set(preferenceKeys.manuallySelectedHour, hour);
    }
  }

  private async select(day: LocalDay, hour: OfficeHour): Promise<void> {
    const state = this.state;
    if (
      state.selectedDay &&
      LocalDays.equals(state.selectedDay.date, day) &&
      state.office &&
      LocalDays.equals(state.office.date, day) &&
      state.office.hour === hour
    ) {
      this.selectionGeneration += 1;
      this.store.update({ isLoading: false, errorMessage: null });
      return;
    }

    if (state.selectedDay && !LocalDays.equals(state.selectedDay.date, day)) {
      this.store.update({ office: null });
    }

    this.selectionGeneration += 1;
    const generation = this.selectionGeneration;
    const tradition = state.officeTradition;
    this.store.update({ isLoading: true, errorMessage: null });

    try {
      const [resolvedDay, resolvedOffice] = await Promise.all([
        this.corpus.day(tradition, day),
        this.corpus.office(tradition, day, hour),
      ]);
      if (generation !== this.selectionGeneration) return;
      this.store.update({ selectedDay: resolvedDay, office: resolvedOffice });
    } catch (error) {
      if (generation !== this.selectionGeneration) return;
      const selected = this.state.selectedDay;
      this.store.update({
        selectedDay:
          selected && LocalDays.equals(selected.date, day) ? selected : null,
        office: null,
        errorMessage: describe(error),
      });
    }
    if (generation === this.selectionGeneration) {
      this.store.update({ isLoading: false });
    }
  }

  /** Has the office at hand before it is opened. */
  prefetch(day: LocalDay, hour: OfficeHour): void {
    this.corpus.prefetch(this.state.officeTradition, day, hour);
  }

  /** Fetches a day's Masses ahead, for use offline. */
  prefetchMasses(day: LocalDay): void {
    this.corpus.prefetchMasses(this.state.officeTradition, day);
  }

  // MARK: Edition

  /**
   * Load the complete replacement before changing the reader's selected
   * tradition. A missing or invalid edition leaves the current office and
   * preference intact.
   */
  async changeOfficeTradition(tradition: OfficeTradition): Promise<boolean> {
    const state = this.state;
    if (
      tradition === state.officeTradition ||
      state.isChangingTradition ||
      this.isStarting
    ) {
      return false;
    }
    this.store.update({
      isChangingTradition: true,
      traditionErrorMessage: null,
      isLoading: false,
    });
    this.selectionGeneration += 1;
    const generation = this.selectionGeneration;
    const day = state.selectedDay?.date ?? state.selectedCivilDate;
    const hour = state.selectedHour;
    try {
      const coverage = await this.corpus.coverage(tradition);
      const [newDay, newOffice] = await Promise.all([
        this.corpus.day(tradition, day),
        this.corpus.office(tradition, day, hour),
      ]);
      if (generation !== this.selectionGeneration) return false;

      this.endReaderSession();
      this.store.update({
        coverage,
        officeTradition: tradition,
        selectedDay: newDay,
        office: newOffice,
        errorMessage: null,
      });
      this.hasCompletedStartup = true;
      this.preferences.set(preferenceKeys.officeTradition, tradition);
      // Search hit IDs are local to a corpus. Queries themselves remain useful.
      this.preferences.remove(preferenceKeys.recentHits);
      return true;
    } catch (error) {
      if (generation === this.selectionGeneration) {
        this.store.update({ traditionErrorMessage: describe(error) });
      }
      return false;
    } finally {
      this.store.update({ isChangingTradition: false });
    }
  }

  // MARK: Reader session

  beginReaderSession(office: OfficeDocument): void {
    this.setSelectedHour(office.hour);
    this.store.update({
      selectedCivilDate: office.date,
      isReaderSessionActive: true,
    });
    const restored =
      this.readerSession &&
      LocalDays.equals(this.readerSession.day, office.date) &&
      this.readerSession.hour === office.hour;
    if (!restored) {
      // A newly opened Hour begins on its Latin page.
      this.readerSession = {
        day: office.date,
        hour: office.hour,
        scrollOffset: 0,
        scrollAnchor: null,
        page: "latin",
      };
      this.store.update({ turnedPage: "latin" });
    }
    this.persistReaderSession();
  }

  shouldRestoreReader(office: OfficeDocument): boolean {
    return (
      this.readerSession !== null &&
      LocalDays.equals(this.readerSession.day, office.date) &&
      this.readerSession.hour === office.hour
    );
  }

  restoredReaderScrollOffset(office: OfficeDocument): number | null {
    return this.shouldRestoreReader(office)
      ? this.readerSession!.scrollOffset
      : null;
  }

  restoredReaderScrollAnchor(
    office: OfficeDocument,
  ): OfficeReaderScrollAnchor | null {
    return this.shouldRestoreReader(office)
      ? this.readerSession!.scrollAnchor
      : null;
  }

  updateReaderScrollOffset(
    scrollOffset: number,
    office: OfficeDocument,
    anchor: OfficeReaderScrollAnchor | null = null,
  ): void {
    if (!this.shouldRestoreReader(office)) return;
    const session = this.readerSession!;
    session.scrollOffset = sanitizedReaderScrollOffset(scrollOffset);
    session.scrollAnchor = anchor;
    this.persistReaderScrollAnchor(anchor);
    this.preferences.set(
      preferenceKeys.readerScrollOffset,
      session.scrollOffset,
    );
  }

  endReaderSession(): void {
    this.readerSession = null;
    this.store.update({ isReaderSessionActive: false });
    this.preferences.remove(preferenceKeys.readerIsPresented);
    this.preferences.remove(preferenceKeys.readerDay);
    this.preferences.remove(preferenceKeys.readerHour);
    this.preferences.remove(preferenceKeys.readerScrollOffset);
    this.preferences.remove(preferenceKeys.readerTradition);
    this.preferences.remove(preferenceKeys.readerScrollAnchor);
    this.preferences.remove(preferenceKeys.readerPage);
  }

  private persistReaderSession(): void {
    const session = this.readerSession;
    if (!session) return;
    this.persistReaderScrollAnchor(session.scrollAnchor);
    this.preferences.set(preferenceKeys.readerIsPresented, true);
    this.preferences.set(
      preferenceKeys.readerTradition,
      this.state.officeTradition,
    );
    this.preferences.set(
      preferenceKeys.readerDay,
      LocalDays.description(session.day),
    );
    this.preferences.set(preferenceKeys.readerHour, session.hour);
    this.preferences.set(
      preferenceKeys.readerScrollOffset,
      session.scrollOffset,
    );
    this.preferences.set(preferenceKeys.readerPage, session.page);
  }

  private persistReaderScrollAnchor(
    anchor: OfficeReaderScrollAnchor | null,
  ): void {
    if (anchor) {
      this.preferences.set(preferenceKeys.readerScrollAnchor, anchor);
    } else {
      this.preferences.remove(preferenceKeys.readerScrollAnchor);
    }
  }
}
