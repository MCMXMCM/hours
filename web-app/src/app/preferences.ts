// What the app remembers between visits. The keys are those the native app
// writes to its defaults, so the two can be read side by side.

export interface KeyValueStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

/** Storage that forgets, for a browser that refuses to keep any. */
export class MemoryStorage implements KeyValueStorage {
  private readonly values = new Map<string, string>();

  getItem(key: string): string | null {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value);
  }

  removeItem(key: string): void {
    this.values.delete(key);
  }
}

export function browserStorage(): KeyValueStorage {
  try {
    const storage = globalThis.localStorage;
    const probe = "hours.probe";
    storage.setItem(probe, "1");
    storage.removeItem(probe);
    return storage;
  } catch {
    return new MemoryStorage();
  }
}

export class Preferences {
  private readonly storage: KeyValueStorage;

  constructor(storage: KeyValueStorage = browserStorage()) {
    this.storage = storage;
  }

  has(key: string): boolean {
    return this.storage.getItem(key) !== null;
  }

  string(key: string): string | null {
    return this.storage.getItem(key);
  }

  bool(key: string): boolean {
    return this.storage.getItem(key) === "true";
  }

  double(key: string): number {
    const value = Number(this.storage.getItem(key));
    return Number.isFinite(value) ? value : 0;
  }

  json<Value>(key: string): Value | null {
    const text = this.storage.getItem(key);
    if (text === null) return null;
    try {
      return JSON.parse(text) as Value;
    } catch {
      return null;
    }
  }

  set(key: string, value: string | number | boolean | object): void {
    try {
      this.storage.setItem(
        key,
        typeof value === "object" ? JSON.stringify(value) : String(value),
      );
    } catch {
      // A full or forbidden store loses the preference, not the prayer.
    }
  }

  remove(key: string): void {
    try {
      this.storage.removeItem(key);
    } catch {
      // As above.
    }
  }
}

export const preferenceKeys = {
  automaticOfficeSelection: "automaticOfficeSelectionEnabled",
  manuallySelectedHour: "manuallySelectedOfficeHour",
  readerIsPresented: "readerRestoration.isPresented",
  readerDay: "readerRestoration.day",
  readerHour: "readerRestoration.hour",
  readerScrollOffset: "readerRestoration.scrollOffset",
  readerScrollAnchor: "readerRestoration.scrollAnchor",
  readerPage: "readerRestoration.page",
  readerTradition: "readerRestoration.tradition",
  officeTradition: "officeTradition",
  showsEnglish: "prayerOptions.showsEnglish",
  showsLatin: "prayerOptions.showsLatin",
  showsChant: "prayerOptions.showsChant",
  notationScale: "prayerOptions.notationScale",
  compactPsalmody: "prayerOptions.compactPsalmody",
  priestOrDeaconPresent: "prayerOptions.priestOrDeaconPresent",
  showsMassOrdinary: "prayerOptions.showsOrdinary",
  appearanceMode: "appearanceMode",
  hourSelectionView: "hourSelectionView",
  scholaPitch: "cantorGuide.scholaPitch",
  chantRegister: "cantorGuide.register",
  guideSound: "cantorGuide.sound",
  recentQueries: "prayerSearch.recentQueries",
  recentHits: "prayerSearch.recentHits",
} as const;
