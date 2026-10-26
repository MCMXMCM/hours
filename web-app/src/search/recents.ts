// What the search screen remembers: the last few searches made and results
// read, as `PrayerSearchView` keeps them, under the same keys.

import { preferenceKeys, type Preferences } from "@/app/preferences.ts";
import {
  equalsIgnoringCase,
  trimmingWhitespaceAndNewlines,
} from "@/core/swiftString.ts";
import type { LiturgicalSearchHit } from "./models.ts";

/** How many of each are kept. */
const limit = 8;

function list<Value>(preferences: Preferences, key: string): Value[] {
  const stored = preferences.json<Value[]>(key);
  return Array.isArray(stored) ? stored : [];
}

export const SearchRecents = {
  queries(preferences: Preferences): string[] {
    return list<string>(preferences, preferenceKeys.recentQueries).filter(
      (value) => typeof value === "string",
    );
  },

  hits(preferences: Preferences): LiturgicalSearchHit[] {
    return list<LiturgicalSearchHit>(
      preferences,
      preferenceKeys.recentHits,
    ).filter((hit) => typeof hit?.id === "string");
  },

  /** Puts a search at the head of the list, once, however it was cased. */
  recordQuery(preferences: Preferences, value: string): string[] {
    const trimmed = trimmingWhitespaceAndNewlines(value);
    const current = SearchRecents.queries(preferences);
    if (trimmed.length === 0) return current;
    const values = [
      trimmed,
      ...current.filter((recent) => !equalsIgnoringCase(recent, trimmed)),
    ].slice(0, limit);
    preferences.set(preferenceKeys.recentQueries, values);
    return values;
  },

  recordViewed(
    preferences: Preferences,
    hit: LiturgicalSearchHit,
  ): LiturgicalSearchHit[] {
    const values = [
      hit,
      ...SearchRecents.hits(preferences).filter(
        (recent) => recent.id !== hit.id,
      ),
    ].slice(0, limit);
    preferences.set(preferenceKeys.recentHits, values);
    return values;
  },

  clearQueries(preferences: Preferences): void {
    preferences.set(preferenceKeys.recentQueries, []);
  },

  clearHits(preferences: Preferences): void {
    preferences.set(preferenceKeys.recentHits, []);
  },
};
