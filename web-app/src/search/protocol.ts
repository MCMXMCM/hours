// What passes between the search screen and the worker that holds an
// edition's library. The worker runs SQLite; the screen only asks.

import type { OfficeTradition } from "@/app/officeTradition.ts";
import type { LocalDay, OfficeHour, OfficeSectionKind } from "@/core/models.ts";
import type {
  LiturgicalSearchHit,
  LiturgicalSearchLanguage,
  LiturgicalSearchResult,
  LiturgicalUsageContext,
  MassPartFilter,
  MassUsageContext,
} from "./models.ts";

/** An edition's library as the corpus publishes it. */
export interface LibrarySource {
  readonly tradition: OfficeTradition;
  /** Where the database is fetched from. */
  readonly url: string;
  /** Its size once decoded, by which a complete download is known. */
  readonly bytes: number;
  /** Its size as it travels, for telling the reader what will be fetched. */
  readonly compressedBytes: number;
  /** The name it is kept under; it changes when the library does. */
  readonly name: string;
}

export interface DayRange {
  readonly lowerBound: LocalDay;
  readonly upperBound: LocalDay;
}

export type SearchCall =
  /** Whether the library is already on this device. */
  | { readonly type: "status"; readonly source: LibrarySource }
  /** Fetches the library if it is not on this device, and opens it. */
  | { readonly type: "open"; readonly source: LibrarySource }
  | {
      readonly type: "searchHits";
      readonly query: string;
      readonly language: LiturgicalSearchLanguage;
      readonly kind: OfficeSectionKind | null;
      readonly hour: OfficeHour | null;
      readonly requiresScore: boolean;
      readonly limit: number;
    }
  | {
      readonly type: "searchOfficeTitles";
      readonly query: string;
      readonly language: LiturgicalSearchLanguage;
      readonly hour: OfficeHour | null;
      readonly usageRange: DayRange | null;
      readonly limit: number;
    }
  /** The Masses found by their titles, or by the titles of their days. */
  | {
      readonly type: "searchMassTitles";
      readonly query: string;
      readonly language: LiturgicalSearchLanguage;
      readonly usageRange: DayRange | null;
      readonly limit: number;
    }
  /** The parts of the Mass whose words hold the query's. */
  | {
      readonly type: "searchMassParts";
      readonly query: string;
      readonly language: LiturgicalSearchLanguage;
      readonly filter: MassPartFilter;
      readonly limit: number;
    }
  /** Reads the Missal for a search of its parts, ahead of the first. */
  | { readonly type: "prepareMassPartSearch" }
  | {
      readonly type: "searchDetail";
      readonly id: string;
      readonly usageRange: DayRange | null;
    }
  /** Removes every library kept on this device. */
  | { readonly type: "forget" };

export interface SearchResults {
  status: { readonly isStored: boolean };
  open: { readonly isPersistent: boolean };
  searchHits: LiturgicalSearchHit[];
  searchOfficeTitles: LiturgicalUsageContext[];
  searchMassTitles: MassUsageContext[];
  searchMassParts: LiturgicalSearchHit[];
  prepareMassPartSearch: null;
  searchDetail: LiturgicalSearchResult;
  forget: null;
}

export interface SearchRequest {
  readonly id: number;
  readonly call: SearchCall;
}

export type SearchReply =
  | { readonly id: number; readonly ok: true; readonly value: unknown }
  | { readonly id: number; readonly ok: false; readonly message: string }
  /** How much of the library has arrived, while it is being fetched. */
  | {
      readonly id: number;
      readonly progress: { readonly received: number; readonly total: number };
    };
