/// <reference lib="webworker" />
// Holds an edition's library and answers the search screen's questions.
//
// The library is the edition's own SQLite database (see `webLibrary.ts` in
// the content compiler), and the questions are put to it by the same SQL the
// native app uses, through SQLite compiled to WebAssembly. The database is
// kept in the browser's private file system, where SQLite reads only the
// pages a query touches; a browser without that keeps it in memory instead.

import sqlite3InitModule, {
  type Database,
  type SAHPoolUtil,
  type Sqlite3Static,
} from "@sqlite.org/sqlite-wasm";
import { retryingFetch } from "@/data/retryingFetch.ts";
import type {
  LibrarySource,
  SearchCall,
  SearchReply,
  SearchRequest,
} from "./protocol.ts";
import { MissalSearch, searchMassTitles } from "./missal.ts";
import { MassPartSearch } from "./models.ts";
import {
  SearchRepository,
  type SearchDatabase,
  type SearchValue,
} from "./repository.ts";

declare const self: DedicatedWorkerGlobalScope;

/** The directory in the private file system that holds the libraries. */
const poolDirectory = "/hours-library";

let sqlite: Promise<Sqlite3Static> | null = null;
let pool: Promise<SAHPoolUtil | null> | null = null;
let opened: {
  name: string;
  database: Database;
  repository: SearchRepository;
  /** The Missal the library carries, if it was exported with one. */
  missal: MissalSearch | null;
} | null = null;

function module(): Promise<Sqlite3Static> {
  sqlite ??= sqlite3InitModule();
  return sqlite;
}

/**
 * The private file system's pool of database files, or `null` where a
 * browser has none to give or another tab is holding it.
 */
function filePool(): Promise<SAHPoolUtil | null> {
  pool ??= module()
    .then((sqlite3) =>
      sqlite3.installOpfsSAHPoolVfs({
        name: "hours-library",
        directory: poolDirectory,
        initialCapacity: 4,
      }),
    )
    .catch(() => null);
  return pool;
}

function fileName(source: LibrarySource): string {
  return `/${source.name}.sqlite`;
}

/** Reads a response in pieces, reporting how much has arrived. */
function pieces(
  response: Response,
  report: (received: number) => void,
): () => Promise<Uint8Array | undefined> {
  const reader = response.body!.getReader();
  let received = 0;
  return async () => {
    const { done, value } = await reader.read();
    if (done) return undefined;
    received += value.byteLength;
    report(received);
    return value;
  };
}

async function fetched(source: LibrarySource): Promise<Response> {
  const response = await retryingFetch(source.url);
  if (!response.ok || !response.body) {
    throw new Error(
      `The library could not be fetched (${response.status}). Check the connection and try again.`,
    );
  }
  return response;
}

function incomplete(received: number, source: LibrarySource): Error {
  return new Error(
    `Only ${received} of the library's ${source.bytes} bytes arrived. Check the connection and try again.`,
  );
}

function adapter(database: Database): SearchDatabase {
  return {
    rows: (sql, bindings) =>
      database.selectArrays(
        sql,
        bindings ? [...bindings] : undefined,
      ) as SearchValue[][],
  };
}

async function open(
  source: LibrarySource,
  report: (received: number) => void,
): Promise<{ isPersistent: boolean }> {
  const name = fileName(source);
  if (opened?.name === name) return { isPersistent: true };
  opened?.database.close();
  opened = null;

  const sqlite3 = await module();
  const files = await filePool();
  let database: Database;
  let isPersistent = false;
  if (files) {
    if (!files.getFileNames().includes(name)) {
      // An earlier library of this edition gives up its place.
      for (const stored of files.getFileNames()) {
        if (stored.startsWith(`/${source.tradition}-`)) files.unlink(stored);
      }
      await files.reserveMinimumCapacity(files.getFileCount() + 2);
      let received = 0;
      const response = await fetched(source);
      await files.importDb(
        name,
        pieces(response, (count) => {
          received = count;
          report(count);
        }),
      );
      if (received !== source.bytes) {
        files.unlink(name);
        throw incomplete(received, source);
      }
      // Ask that the browser not reclaim the library when room is short.
      void navigator.storage?.persist?.().catch(() => false);
    }
    database = new files.OpfsSAHPoolDb(name);
    isPersistent = true;
  } else {
    // Without a file system the whole database is held in memory, and is
    // fetched again on the next visit (from the browser's cache, if kept).
    const response = await fetched(source);
    const bytes = new Uint8Array(source.bytes);
    const next = pieces(response, report);
    let received = 0;
    for (let piece = await next(); piece; piece = await next()) {
      if (received + piece.byteLength > bytes.byteLength) {
        throw incomplete(received + piece.byteLength, source);
      }
      bytes.set(piece, received);
      received += piece.byteLength;
    }
    if (received !== source.bytes) throw incomplete(received, source);
    database = new sqlite3.oo1.DB(":memory:");
    const pointer = sqlite3.wasm.allocFromTypedArray(bytes);
    const result = sqlite3.capi.sqlite3_deserialize(
      database.pointer!,
      "main",
      pointer,
      bytes.byteLength,
      bytes.byteLength,
      sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE |
        sqlite3.capi.SQLITE_DESERIALIZE_READONLY,
    );
    if (result !== 0) {
      database.close();
      throw new Error("The library could not be opened.");
    }
  }

  opened = {
    name,
    database,
    repository: new SearchRepository(adapter(database), {
      tradition: source.tradition,
    }),
    missal: MissalSearch.open(adapter(database)),
  };
  return { isPersistent };
}

function library(): NonNullable<typeof opened> {
  if (!opened) throw new Error("The office corpus has not finished loading.");
  return opened;
}

function repository(): SearchRepository {
  return library().repository;
}

async function answer(
  call: SearchCall,
  report: (received: number, total: number) => void,
): Promise<unknown> {
  switch (call.type) {
    case "status": {
      const files = await filePool();
      return {
        isStored:
          files?.getFileNames().includes(fileName(call.source)) ?? false,
      };
    }
    case "open":
      return open(call.source, (received) =>
        report(received, call.source.bytes),
      );
    case "searchHits":
      return repository().searchHits(
        call.query,
        call.language,
        call.kind,
        call.hour,
        call.requiresScore,
        call.limit,
      );
    case "searchOfficeTitles":
      return repository().searchOfficeTitles(
        call.query,
        call.language,
        call.hour,
        call.usageRange,
        call.limit,
      );
    case "searchMassTitles": {
      const { repository, missal } = library();
      return searchMassTitles(
        repository,
        missal,
        call.query,
        call.language,
        call.usageRange,
        call.limit,
      );
    }
    case "searchMassParts": {
      const { missal } = library();
      return missal === null
        ? []
        : missal.searchMassParts(
            call.query,
            call.language,
            call.filter,
            call.limit,
          );
    }
    case "prepareMassPartSearch":
      library().missal?.prepareMassPartSearch();
      return null;
    case "searchDetail": {
      // A part of the Mass is the Missal's.
      if (call.id.startsWith(MassPartSearch.idPrefix)) {
        const { missal } = library();
        if (missal === null) {
          throw new Error(`Search resource ${call.id} is missing.`);
        }
        return missal.massPartDetail(call.id, call.usageRange);
      }
      return repository().searchDetail(call.id, call.usageRange);
    }
    case "forget": {
      opened?.database.close();
      opened = null;
      await (await filePool())?.wipeFiles();
      return null;
    }
  }
}

self.onmessage = (event: MessageEvent<SearchRequest>) => {
  const { id, call } = event.data;
  let reported = 0;
  const report = (received: number, total: number) => {
    // A few times a second is as often as a progress bar can use.
    const now = performance.now();
    if (received < total && now - reported < 120) return;
    reported = now;
    self.postMessage({
      id,
      progress: { received, total },
    } satisfies SearchReply);
  };
  answer(call, report).then(
    (value) => self.postMessage({ id, ok: true, value } satisfies SearchReply),
    (error: unknown) =>
      self.postMessage({
        id,
        ok: false,
        message: error instanceof Error ? error.message : String(error),
      } satisfies SearchReply),
  );
};
