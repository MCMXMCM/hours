// The search screen's side of the library: whether an edition's library is
// on this device, fetching it when the reader asks, and putting questions to
// the worker that holds it.

import type { OfficeTradition } from "@/app/officeTradition.ts";
import { Store } from "@/app/store.ts";
import type { OfficeHour, OfficeSectionKind } from "@/core/models.ts";
import type { Corpus } from "@/data/corpus.ts";
import type {
  LiturgicalSearchHit,
  LiturgicalSearchLanguage,
  LiturgicalSearchResult,
  LiturgicalUsageContext,
  MassPartFilter,
  MassUsageContext,
} from "./models.ts";
import type {
  DayRange,
  LibrarySource,
  SearchCall,
  SearchReply,
  SearchRequest,
  SearchResults,
} from "./protocol.ts";

export type LibraryStatus =
  /** Not yet known whether the library is on this device. */
  | "checking"
  /** The corpus at hand was published without a library. */
  | "unavailable"
  /** It must be fetched before anything can be searched. */
  | "absent"
  | "fetching"
  | "ready"
  | "failed";

export interface LibraryState {
  readonly tradition: OfficeTradition | null;
  readonly status: LibraryStatus;
  /** How much of the library has arrived, and how much there is. */
  readonly received: number;
  readonly total: number;
  /** What the fetch will cost the reader's connection, in bytes. */
  readonly compressedBytes: number;
  /** Why the library could not be had. */
  readonly message: string | null;
}

/** The worker, as much of it as this module uses. */
export interface LibraryWorker {
  postMessage(message: SearchRequest): void;
  onmessage: ((event: MessageEvent<SearchReply>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
  terminate(): void;
}

interface Pending {
  resolve(value: unknown): void;
  reject(error: Error): void;
  progress?: (received: number, total: number) => void;
}

function makeWorker(): LibraryWorker {
  return new Worker(new URL("./libraryWorker.ts", import.meta.url), {
    type: "module",
    name: "hours-library",
  }) as unknown as LibraryWorker;
}

export class SearchLibrary {
  readonly store = new Store<LibraryState>({
    tradition: null,
    status: "checking",
    received: 0,
    total: 0,
    compressedBytes: 0,
    message: null,
  });

  private readonly corpus: Corpus;
  private readonly spawn: () => LibraryWorker;
  private worker: LibraryWorker | null = null;
  private readonly pending = new Map<number, Pending>();
  private nextID = 1;
  private source: LibrarySource | null = null;

  constructor(corpus: Corpus, spawn: () => LibraryWorker = makeWorker) {
    this.corpus = corpus;
    this.spawn = spawn;
  }

  // MARK: The library

  /**
   * Finds out whether an edition's library is on this device, and opens it
   * if it is. Nothing is fetched until the reader asks, with `download`.
   */
  async prepare(tradition: OfficeTradition): Promise<void> {
    const current = this.store.value;
    if (
      current.tradition === tradition &&
      (current.status === "ready" || current.status === "fetching")
    ) {
      return;
    }
    this.store.set({
      tradition,
      status: "checking",
      received: 0,
      total: 0,
      compressedBytes: 0,
      message: null,
    });
    try {
      const library = await this.corpus.library(tradition);
      if (this.store.value.tradition !== tradition) return;
      if (library === null) {
        this.source = null;
        this.store.update({ status: "unavailable" });
        return;
      }
      const source: LibrarySource = { tradition, ...library };
      this.source = source;
      this.store.update({
        total: library.bytes,
        compressedBytes: library.compressedBytes,
      });
      const { isStored } = await this.call({ type: "status", source });
      if (this.store.value.tradition !== tradition) return;
      if (isStored) {
        await this.open(source);
      } else {
        this.store.update({ status: "absent" });
      }
    } catch (error) {
      if (this.store.value.tradition !== tradition) return;
      this.fail(error);
    }
  }

  /** Fetches the library of the edition last prepared, and opens it. */
  async download(): Promise<void> {
    const source = this.source;
    if (source === null || this.store.value.status === "fetching") return;
    try {
      await this.open(source);
    } catch (error) {
      if (this.source === source) this.fail(error);
    }
  }

  /** Removes every library from this device. */
  async forget(): Promise<void> {
    await this.call({ type: "forget" });
    if (this.source !== null) {
      this.store.update({ status: "absent", received: 0, message: null });
    }
  }

  /** Lets the worker, and the memory it holds, go. */
  close(): void {
    this.worker?.terminate();
    this.worker = null;
    for (const request of this.pending.values()) {
      request.reject(new Error("Search was closed."));
    }
    this.pending.clear();
    const state = this.store.value;
    if (state.status === "ready" || state.status === "fetching") {
      this.store.update({ status: "checking", received: 0 });
    }
  }

  private async open(source: LibrarySource): Promise<void> {
    this.store.update({ status: "fetching", received: 0, message: null });
    await this.call({ type: "open", source }, (received, total) => {
      if (this.source === source) this.store.update({ received, total });
    });
    if (this.source !== source) return;
    this.store.update({ status: "ready", received: source.bytes });
  }

  private fail(error: unknown): void {
    this.store.update({
      status: "failed",
      message: error instanceof Error ? error.message : String(error),
    });
  }

  // MARK: Questions

  searchHits(
    query: string,
    language: LiturgicalSearchLanguage,
    kind: OfficeSectionKind | null,
    hour: OfficeHour | null,
    requiresScore: boolean,
    limit = 50,
  ): Promise<LiturgicalSearchHit[]> {
    return this.call({
      type: "searchHits",
      query,
      language,
      kind,
      hour,
      requiresScore,
      limit,
    });
  }

  searchOfficeTitles(
    query: string,
    language: LiturgicalSearchLanguage,
    hour: OfficeHour | null,
    usageRange: DayRange | null,
    limit = 50,
  ): Promise<LiturgicalUsageContext[]> {
    return this.call({
      type: "searchOfficeTitles",
      query,
      language,
      hour,
      usageRange,
      limit,
    });
  }

  searchMassTitles(
    query: string,
    language: LiturgicalSearchLanguage,
    usageRange: DayRange | null,
    limit = 50,
  ): Promise<MassUsageContext[]> {
    return this.call({
      type: "searchMassTitles",
      query,
      language,
      usageRange,
      limit,
    });
  }

  searchMassParts(
    query: string,
    language: LiturgicalSearchLanguage,
    filter: MassPartFilter,
    limit = 50,
  ): Promise<LiturgicalSearchHit[]> {
    return this.call({
      type: "searchMassParts",
      query,
      language,
      filter,
      limit,
    });
  }

  /** Has the worker read the Missal for a search of its parts while the reader types. */
  prepareMassPartSearch(): Promise<null> {
    return this.call({ type: "prepareMassPartSearch" });
  }

  searchDetail(
    id: string,
    usageRange: DayRange | null,
  ): Promise<LiturgicalSearchResult> {
    return this.call({ type: "searchDetail", id, usageRange });
  }

  // MARK: The worker

  private call<Call extends SearchCall>(
    call: Call,
    progress?: (received: number, total: number) => void,
  ): Promise<SearchResults[Call["type"]]> {
    const worker = this.startedWorker();
    const id = this.nextID;
    this.nextID += 1;
    return new Promise((resolve, reject) => {
      this.pending.set(id, {
        resolve: resolve as (value: unknown) => void,
        reject,
        progress,
      });
      worker.postMessage({ id, call });
    });
  }

  private startedWorker(): LibraryWorker {
    if (this.worker) return this.worker;
    const worker = this.spawn();
    worker.onmessage = (event) => {
      const reply = event.data;
      const request = this.pending.get(reply.id);
      if (!request) return;
      if ("progress" in reply) {
        request.progress?.(reply.progress.received, reply.progress.total);
        return;
      }
      this.pending.delete(reply.id);
      if (reply.ok) request.resolve(reply.value);
      else request.reject(new Error(reply.message));
    };
    worker.onerror = (event) => {
      // The worker could not be started, or has died; every question fails.
      const error = new Error(
        event.message || "Search could not be started in this browser.",
      );
      for (const request of this.pending.values()) request.reject(error);
      this.pending.clear();
      worker.terminate();
      if (this.worker === worker) this.worker = null;
    };
    this.worker = worker;
    return worker;
  }
}
