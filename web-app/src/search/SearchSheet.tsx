import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Music,
  Search,
  SearchX,
  TextSearch,
} from "lucide-react";
import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useNavigate } from "react-router-dom";
import { useAppState, useServices } from "@/app/context.tsx";
import { massPath, officePath } from "@/app/routes.ts";
import { useStore } from "@/app/store.ts";
import { Sheet } from "@/components/Sheet.tsx";
import {
  LocalDays,
  ObservanceTitle,
  OfficeHours,
  OfficeSectionKinds,
  type ChantScore,
  type OfficeHour,
} from "@/core/models.ts";
import { trimmingWhitespaceAndNewlines } from "@/core/swiftString.ts";
import {
  LiturgicalSearchHits,
  LiturgicalTitleResults,
  MassPartChoices,
  PrayerSearchCategories,
  SearchResultPresentation,
  type LiturgicalSearchHit,
  type LiturgicalSearchLanguage,
  type LiturgicalTitleResult,
  type LiturgicalUsageContext,
  type MassPartChoice,
  type MassUsageContext,
  type PrayerSearchCategory,
} from "./index.ts";
import { SearchLibrary, type LibraryState } from "./library.ts";
import type { DayRange } from "./protocol.ts";
import { SearchRecents } from "./recents.ts";
import { SearchDetail } from "./SearchDetail.tsx";

const SearchChant = lazy(() => import("./SearchChant.tsx"));

export interface SearchSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

type SearchPhase =
  | { readonly type: "idle" }
  | {
      readonly type: "loadedContent";
      readonly results: LiturgicalSearchHit[];
    }
  | {
      readonly type: "loadedTitles";
      readonly results: LiturgicalTitleResult[];
    }
  | { readonly type: "failed"; readonly message: string };

/** What the sheet is showing beyond its list of results. */
type Destination =
  | { readonly type: "results" }
  | { readonly type: "detail"; readonly hit: LiturgicalSearchHit }
  | {
      readonly type: "chant";
      readonly hit: LiturgicalSearchHit;
      readonly score: ChantScore;
    };

/** A pause after the last keystroke before a search is made, in milliseconds. */
const searchDelay = 225;
/** A search slower than this shows that it is under way. */
const indicatorDelay = 120;

const megabytes = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

function megabyteText(bytes: number): string {
  return `${megabytes.format(bytes / 1_000_000)} MB`;
}

/**
 * The days in which usages are sought, as the native app has it: from today
 * through the following church-calendar year, so that each Office is found
 * at its next occurrence.
 */
function currentUsageRange(): DayRange {
  const days = LocalDays.upcomingOfficesRange(LocalDays.currentOfficeDay());
  return { lowerBound: days.start, upperBound: days.end };
}

function languageTitle(language: LiturgicalSearchLanguage): string {
  switch (language) {
    case "latin":
      return "Latin";
    case "english":
      return "English";
    default:
      return "Both Languages";
  }
}

const monthAndDay = new Intl.DateTimeFormat("en-US", {
  month: "long",
  day: "numeric",
});

function SearchHitRow({ hit }: { hit: LiturgicalSearchHit }) {
  return (
    <span className="search-hit">
      <span className="search-hit__title">
        {SearchResultPresentation.title(hit)}
        {LiturgicalSearchHits.isOfTheMass(hit) && (
          <span className="search-hit__mass">Mass</span>
        )}
        {hit.hasScoredRealizations && (
          <Music role="img" aria-label="Chant settings available" />
        )}
      </span>
      <span
        className="search-hit__snippet"
        lang={hit.snippetLanguage === "latin" ? "la" : undefined}
        data-language={hit.snippetLanguage}
      >
        {hit.snippet}
      </span>
    </span>
  );
}

function OfficeTitleRow({ context }: { context: LiturgicalUsageContext }) {
  const english = context.observanceTitleEnglish;
  return (
    <>
      <span className="search-usage">
        <span className="search-usage__title" lang="la">
          {ObservanceTitle.latin(context.observanceTitleLatin)}
        </span>
        {english != null && english !== context.observanceTitleLatin && (
          <span className="search-usage__english">
            {ObservanceTitle.english(english)}
          </span>
        )}
        <span className="search-usage__summary">
          {OfficeHours.englishTitle(context.hour)}
          {" \u{B7} "}
          {monthAndDay.format(LocalDays.date(context.firstDate))}
        </span>
      </span>
      <ChevronRight aria-hidden="true" className="search-row__chevron" />
    </>
  );
}

/**
 * A Mass found by its title. It is told from the Hours by the word "Mass",
 * red as Home's link to the Mass is, where an Office names its Hour.
 */
function MassTitleRow({ mass }: { mass: MassUsageContext }) {
  const english = mass.titleEnglish;
  return (
    <>
      <span className="search-usage">
        <span className="search-usage__title" lang="la">
          {ObservanceTitle.latin(mass.titleLatin)}
        </span>
        {english != null && english !== mass.titleLatin && (
          <span className="search-usage__english">
            {ObservanceTitle.english(english)}
          </span>
        )}
        <span className="search-usage__summary">
          <span className="search-usage__mass">Mass</span>
          {" \u{B7} "}
          {monthAndDay.format(LocalDays.date(mass.firstDate))}
        </span>
      </span>
      <ChevronRight aria-hidden="true" className="search-row__chevron" />
    </>
  );
}

/** What stands in for results while an edition's library is not yet open. */
function LibraryPanel({
  state,
  onDownload,
}: {
  state: LibraryState;
  onDownload: () => void;
}) {
  if (state.status === "checking") {
    return (
      <div className="search-empty" role="status" aria-label="Loading">
        <span className="spinner" />
      </div>
    );
  }
  if (state.status === "unavailable") {
    return (
      <div className="search-empty">
        <SearchX aria-hidden="true" />
        <h3>Search unavailable</h3>
        <p>This copy of the Office was published without its library.</p>
      </div>
    );
  }
  if (state.status === "fetching") {
    const fraction = state.total > 0 ? state.received / state.total : 0;
    return (
      <div className="search-empty" role="status">
        <TextSearch aria-hidden="true" />
        <h3>Fetching the library</h3>
        <progress
          className="search-library__progress"
          value={fraction}
          aria-label="Library fetched"
        />
        <p>
          {megabyteText(fraction * state.compressedBytes)} of{" "}
          {megabyteText(state.compressedBytes)}
        </p>
      </div>
    );
  }
  return (
    <div className="search-empty">
      <TextSearch aria-hidden="true" />
      <h3>Search the Office</h3>
      <p>
        Find feast days, prayers, readings, psalms, hymns, responsories, chants,
        and the parts of the Mass in Latin or English.
      </p>
      <p>
        To search, Hours keeps this edition{"\u{2019}"}s library on this device.
        It is fetched once.
      </p>
      {state.status === "failed" && state.message !== null && (
        <p className="search-library__error" role="alert">
          {state.message}
        </p>
      )}
      <button
        type="button"
        className="search-library__fetch"
        onClick={onDownload}
      >
        {state.status === "failed" ? "Try again" : "Fetch library"}
        <span>{megabyteText(state.compressedBytes)}</span>
      </button>
    </div>
  );
}

/**
 * `performSearch`'s search of texts: the Office's texts the category names,
 * and the parts of the Mass it names among the Mass's, as one list.
 */
async function searchContent(
  library: SearchLibrary,
  query: string,
  language: LiturgicalSearchLanguage,
  category: PrayerSearchCategory,
  hour: OfficeHour | null,
  part: MassPartChoice,
): Promise<LiturgicalSearchHit[]> {
  const office = PrayerSearchCategories.searchesOffice(category)
    ? library.searchHits(
        query,
        language,
        PrayerSearchCategories.kind(category),
        hour,
        PrayerSearchCategories.requiresScore(category),
      )
    : Promise.resolve([]);
  // The Mass is of no Hour, and is not found under one.
  const filter =
    hour === null ? PrayerSearchCategories.massFilter(category, part) : null;
  const mass =
    filter === null
      ? Promise.resolve([])
      : library.searchMassParts(query, language, filter);
  const [officeHits, massHits] = await Promise.all([office, mass]);
  return LiturgicalSearchHits.merged(officeHits, massHits);
}

/** Search, as the native app presents it: a sheet over Home. */
export default function SearchSheet({ open, onOpenChange }: SearchSheetProps) {
  const { corpus, preferences } = useServices();
  const app = useAppState();
  const navigate = useNavigate();
  const library = useMemo(() => new SearchLibrary(corpus), [corpus]);
  const libraryState = useStore(library.store);

  const [query, setQuery] = useState("");
  const [language, setLanguage] = useState<LiturgicalSearchLanguage>("all");
  const [category, setCategory] = useState<PrayerSearchCategory>("all");
  const [hour, setHour] = useState<OfficeHour | null>(null);
  const [massPart, setMassPart] = useState<MassPartChoice>("any");
  const [phase, setPhase] = useState<SearchPhase>({ type: "idle" });
  const [isSearching, setIsSearching] = useState(false);
  const [destination, setDestination] = useState<Destination>({
    type: "results",
  });
  const [recentQueries, setRecentQueries] = useState(() =>
    SearchRecents.queries(preferences),
  );
  const [recentHits, setRecentHits] = useState(() =>
    SearchRecents.hits(preferences),
  );
  const field = useRef<HTMLInputElement>(null);
  const backButton = useRef<HTMLButtonElement>(null);
  const results = useRef<HTMLDivElement>(null);
  /** The result last opened, to which the keyboard's focus returns. */
  const lastOpened = useRef<string | null>(null);

  const trimmedQuery = trimmingWhitespaceAndNewlines(query);
  const tradition = app.officeTradition;
  const isReady = libraryState.status === "ready";
  // The Mass is of no Hour; a part of it is chosen instead.
  const searchedHour = category === "mass" ? null : hour;
  const searchedPart: MassPartChoice = category === "mass" ? massPart : "any";
  const massPartMenu = useRef<HTMLLabelElement>(null);

  // The library is looked for when search opens, and let go when it closes.
  useEffect(() => {
    if (!open) return;
    void library.prepare(tradition);
    // Search hit IDs are local to a corpus, and the app model has cleared them.
    setRecentHits(SearchRecents.hits(preferences));
    setRecentQueries(SearchRecents.queries(preferences));
  }, [library, open, preferences, tradition]);
  useEffect(() => () => library.close(), [library]);

  // The Missal is read for a search of its parts while the reader types.
  useEffect(() => {
    if (!open || !isReady) return;
    void library.prepareMassPartSearch().catch(() => null);
  }, [isReady, library, open]);

  // The parts of the Mass stand at the end of the filters, where the Hours
  // stood: choosing the Mass brings them into view.
  useEffect(() => {
    if (category !== "mass") return;
    massPartMenu.current?.scrollIntoView({
      block: "nearest",
      inline: "nearest",
      behavior: "smooth",
    });
  }, [category]);

  // A keyboard is at hand on a desk, and the field is where it is wanted: the
  // sheet opens with the caret in it, and has it again when a library that
  // had to be fetched is ready. A touch screen would raise its keyboard over
  // what the sheet has to show, and is left to the reader's tap.
  const fieldIfKeyboardIsAtHand = useCallback(
    () =>
      window.matchMedia("(hover: hover) and (pointer: fine)").matches
        ? field.current
        : null,
    [],
  );
  useEffect(() => {
    if (!open || !isReady) return;
    const timer = window.setTimeout(
      () => fieldIfKeyboardIsAtHand()?.focus(),
      80,
    );
    return () => window.clearTimeout(timer);
  }, [fieldIfKeyboardIsAtHand, isReady, open]);

  // `performSearch`: wait for the typing to pause, then ask; an answer to a
  // question no longer being asked is dropped.
  useEffect(() => {
    if (!open || !isReady || trimmedQuery.length === 0) {
      setPhase({ type: "idle" });
      setIsSearching(false);
      return;
    }
    let cancelled = false;
    let indicator: number | undefined;
    const timer = window.setTimeout(() => {
      indicator = window.setTimeout(() => {
        if (!cancelled) setIsSearching(true);
      }, indicatorDelay);
      const usageRange = currentUsageRange();
      const request: Promise<SearchPhase> =
        category === "titles"
          ? Promise.all([
              library.searchOfficeTitles(
                trimmedQuery,
                language,
                searchedHour,
                usageRange,
              ),
              // The Mass is of no Hour, and is not found under one.
              searchedHour === null
                ? library.searchMassTitles(trimmedQuery, language, usageRange)
                : Promise.resolve([]),
            ]).then(([offices, masses]) => ({
              type: "loadedTitles",
              results: LiturgicalTitleResults.merged(offices, masses),
            }))
          : searchContent(
              library,
              trimmedQuery,
              language,
              category,
              searchedHour,
              searchedPart,
            ).then((results) => ({ type: "loadedContent", results }));
      request
        .catch((error: unknown): SearchPhase => ({
          type: "failed",
          message: error instanceof Error ? error.message : String(error),
        }))
        .then((loaded) => {
          window.clearTimeout(indicator);
          if (cancelled) return;
          setIsSearching(false);
          setPhase(loaded);
        });
    }, searchDelay);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      window.clearTimeout(indicator);
    };
  }, [
    category,
    isReady,
    language,
    library,
    open,
    searchedHour,
    searchedPart,
    trimmedQuery,
  ]);

  const recordRecentQuery = useCallback(
    (value: string) =>
      setRecentQueries(SearchRecents.recordQuery(preferences, value)),
    [preferences],
  );
  const recordRecentlyViewed = useCallback(
    (hit: LiturgicalSearchHit) =>
      setRecentHits(SearchRecents.recordViewed(preferences, hit)),
    [preferences],
  );

  const openOffice = useCallback(
    (context: LiturgicalUsageContext) => {
      onOpenChange(false);
      navigate(officePath(context.firstDate, context.hour));
    },
    [navigate, onOpenChange],
  );

  const openMass = useCallback(
    (mass: MassUsageContext) => {
      recordRecentQuery(trimmedQuery);
      onOpenChange(false);
      navigate(massPath(mass.firstDate, mass.index));
    },
    [navigate, onOpenChange, recordRecentQuery, trimmedQuery],
  );

  const openDetail = (hit: LiturgicalSearchHit, fromResults: boolean) => {
    if (fromResults) recordRecentQuery(trimmedQuery);
    recordRecentlyViewed(hit);
    lastOpened.current = hit.id;
    setDestination({ type: "detail", hit });
  };

  // The control that was in hand is gone when the sheet turns to another of
  // its pages. Focus is given to the way back, and on returning to the
  // results to the result that was opened, rather than left to fall away.
  useLayoutEffect(() => {
    if (!open) return;
    if (destination.type !== "results") {
      backButton.current?.focus({ preventScroll: true });
      return;
    }
    const opened = lastOpened.current;
    if (opened === null) return;
    lastOpened.current = null;
    const row = Array.from(
      results.current?.querySelectorAll<HTMLElement>("[data-hit]") ?? [],
    ).find((candidate) => candidate.dataset.hit === opened);
    (row ?? field.current)?.focus({ preventScroll: true });
  }, [destination, open]);

  const header =
    destination.type === "results" ? (
      <form
        className="search-field"
        role="search"
        onSubmit={(event) => {
          event.preventDefault();
          field.current?.blur();
          recordRecentQuery(trimmedQuery);
        }}
      >
        <Search aria-hidden="true" />
        <input
          ref={field}
          type="search"
          aria-label="Search"
          placeholder="Prayer, feast, reading, or chant"
          autoCapitalize="none"
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
      </form>
    ) : (
      <div className="search-bar">
        <button
          ref={backButton}
          type="button"
          className="search-bar__back"
          onClick={() =>
            setDestination(
              destination.type === "chant"
                ? { type: "detail", hit: destination.hit }
                : { type: "results" },
            )
          }
        >
          <ChevronLeft aria-hidden="true" />
          Back
        </button>
        <h2
          className="search-bar__title"
          lang={destination.type === "chant" ? "la" : undefined}
        >
          {destination.type === "chant"
            ? destination.score.incipit
            : SearchResultPresentation.title(destination.hit)}
        </h2>
      </div>
    );

  let content: React.ReactNode;
  if (destination.type === "detail") {
    content = (
      <SearchDetail
        key={destination.hit.id}
        hit={destination.hit}
        library={library}
        usageRange={currentUsageRange()}
        onOpenOffice={openOffice}
        onOpenMass={openMass}
        onOpenChant={(score) =>
          setDestination({ type: "chant", hit: destination.hit, score })
        }
      />
    );
  } else if (destination.type === "chant") {
    content = null;
  } else if (!isReady) {
    content = (
      <LibraryPanel
        state={libraryState}
        onDownload={() => void library.download()}
      />
    );
  } else if (phase.type === "failed") {
    content = (
      <div className="search-empty">
        <SearchX aria-hidden="true" />
        <h3>Search unavailable</h3>
        <p>{phase.message}</p>
      </div>
    );
  } else if (phase.type === "idle") {
    content =
      recentQueries.length === 0 && recentHits.length === 0 ? (
        <div className="search-empty">
          <TextSearch aria-hidden="true" />
          <h3>Search the Office</h3>
          <p>
            Find feast days, prayers, readings, psalms, hymns, responsories,
            chants, and the parts of the Mass in Latin or English.
          </p>
        </div>
      ) : (
        <div className="search-list">
          {recentQueries.length > 0 && (
            <section aria-labelledby="search-recent-queries">
              <header className="search-history">
                <h3 id="search-recent-queries">Recently Searched</h3>
                <button
                  type="button"
                  onClick={() => {
                    SearchRecents.clearQueries(preferences);
                    setRecentQueries([]);
                  }}
                >
                  Clear
                </button>
              </header>
              <ul>
                {recentQueries.map((recent) => (
                  <li key={recent}>
                    <button
                      type="button"
                      className="search-row search-row--query"
                      onClick={() => setQuery(recent)}
                    >
                      <Search aria-hidden="true" />
                      {recent}
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          )}
          {recentHits.length > 0 && (
            <section aria-labelledby="search-recent-hits">
              <header className="search-history">
                <h3 id="search-recent-hits">Recently Viewed</h3>
                <button
                  type="button"
                  onClick={() => {
                    SearchRecents.clearHits(preferences);
                    setRecentHits([]);
                  }}
                >
                  Clear
                </button>
              </header>
              <ul>
                {recentHits.map((hit) => (
                  <li key={hit.id}>
                    <button
                      type="button"
                      className="search-row"
                      data-hit={hit.id}
                      onClick={() => openDetail(hit, false)}
                    >
                      <SearchHitRow hit={hit} />
                      <ChevronRight
                        aria-hidden="true"
                        className="search-row__chevron"
                      />
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>
      );
  } else if (phase.results.length === 0) {
    content = (
      <div className="search-empty">
        <Search aria-hidden="true" />
        <h3>
          No Results for {"\u{201C}"}
          {trimmedQuery}
          {"\u{201D}"}
        </h3>
        <p>Check the spelling or try a new search.</p>
      </div>
    );
  } else if (phase.type === "loadedContent") {
    content = (
      <ul className="search-list" aria-label="Results">
        {phase.results.map((hit) => (
          <li key={hit.id}>
            <button
              type="button"
              className="search-row"
              data-hit={hit.id}
              onClick={() => openDetail(hit, true)}
            >
              <SearchHitRow hit={hit} />
              <ChevronRight
                aria-hidden="true"
                className="search-row__chevron"
              />
            </button>
          </li>
        ))}
      </ul>
    );
  } else {
    content = (
      <ul className="search-list" aria-label="Results">
        {phase.results.map((result) =>
          result.type === "office" ? (
            <li
              key={`${result.context.observanceID ?? result.context.observanceTitleLatin}-${LocalDays.description(result.context.firstDate)}-${result.context.hour}`}
            >
              <button
                type="button"
                className="search-row"
                title="Opens this office"
                onClick={() => {
                  recordRecentQuery(trimmedQuery);
                  openOffice(result.context);
                }}
              >
                <OfficeTitleRow context={result.context} />
              </button>
            </li>
          ) : (
            <li
              key={`mass-${result.mass.titleLatin}-${result.mass.label ?? ""}-${LocalDays.description(result.mass.firstDate)}`}
            >
              <button
                type="button"
                className="search-row"
                title="Opens this Mass"
                onClick={() => {
                  recordRecentQuery(trimmedQuery);
                  openMass(result.mass);
                }}
              >
                <MassTitleRow mass={result.mass} />
              </button>
            </li>
          ),
        )}
      </ul>
    );
  }

  const showsFilters =
    destination.type === "results" && isReady && trimmedQuery.length > 0;

  return (
    <Sheet
      open={open}
      onOpenChange={(next) => {
        if (!next) setDestination({ type: "results" });
        onOpenChange(next);
      }}
      title="Search"
      header={header}
      closeLabel="Close Search"
      initialFocus={fieldIfKeyboardIsAtHand}
    >
      <div ref={results} className="search">
        {showsFilters && (
          <div className="search-filters" role="group" aria-label="Filters">
            {PrayerSearchCategories.allCases.map((option) => (
              <button
                key={option}
                type="button"
                className="search-chip"
                aria-pressed={category === option}
                onClick={() => setCategory(option)}
              >
                {PrayerSearchCategories.title(option)}
              </button>
            ))}
            {category === "mass" ? (
              // The Mass is of no Hour: its parts are chosen instead.
              <label
                ref={massPartMenu}
                className="search-chip search-chip--menu"
                data-active={massPart !== "any" || undefined}
              >
                <span>{MassPartChoices.title(massPart)}</span>
                <ChevronDown aria-hidden="true" />
                <select
                  aria-label="Part of the Mass"
                  value={massPart}
                  onChange={(event) =>
                    setMassPart(
                      MassPartChoices.fromRawValue(event.target.value) ?? "any",
                    )
                  }
                >
                  {MassPartChoices.allCases.slice(0, 3).map((option) => (
                    <option key={option} value={option}>
                      {MassPartChoices.title(option)}
                    </option>
                  ))}
                  <hr />
                  {MassPartChoices.allCases.slice(3).map((option) => (
                    <option key={option} value={option}>
                      {MassPartChoices.title(option)}
                    </option>
                  ))}
                </select>
              </label>
            ) : (
              <label
                className="search-chip search-chip--menu"
                data-active={hour !== null || undefined}
              >
                <span>
                  {hour === null
                    ? "Any Office"
                    : OfficeHours.englishTitle(hour)}
                </span>
                <ChevronDown aria-hidden="true" />
                <select
                  aria-label="Office"
                  value={hour ?? ""}
                  onChange={(event) =>
                    setHour(
                      event.target.value === ""
                        ? null
                        : (event.target.value as OfficeHour),
                    )
                  }
                >
                  <option value="">Any Office</option>
                  {OfficeHours.allCases.map((option) => (
                    <option key={option} value={option}>
                      {OfficeHours.englishTitle(option)}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label
              className="search-chip search-chip--menu"
              data-active={language !== "all" || undefined}
            >
              <span>{languageTitle(language)}</span>
              <ChevronDown aria-hidden="true" />
              <select
                aria-label="Language"
                value={language}
                onChange={(event) =>
                  setLanguage(event.target.value as LiturgicalSearchLanguage)
                }
              >
                <option value="all">Both Languages</option>
                <option value="latin">Latin</option>
                <option value="english">English</option>
              </select>
            </label>
            {isSearching && (
              <span
                className="spinner spinner--small"
                role="status"
                aria-label="Searching"
              />
            )}
          </div>
        )}
        {destination.type === "chant" ? (
          <Suspense
            fallback={
              <div className="search-empty" role="status" aria-label="Loading">
                <span className="spinner" />
              </div>
            }
          >
            <SearchChant
              key={destination.score.id}
              score={destination.score}
              opensPiece={OfficeSectionKinds.opensPiece(destination.hit.kind)}
            />
          </Suspense>
        ) : (
          content
        )}
      </div>
    </Sheet>
  );
}
