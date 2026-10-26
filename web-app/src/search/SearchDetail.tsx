import { ChevronRight, SearchX } from "lucide-react";
import { useEffect, useState } from "react";
import {
  LocalDays,
  ObservanceTitle,
  OfficeHours,
  type ChantScore,
} from "@/core/models.ts";
import {
  PrayerSearchChantSettings,
  PrayerSearchDetailPresentations,
  PrayerSearchMassUsageRows,
  PrayerSearchUsageRows,
  type LiturgicalSearchHit,
  type LiturgicalUsageContext,
  type MassUsageContext,
  type PrayerSearchDetailPresentation,
} from "./index.ts";
import type { SearchLibrary } from "./library.ts";
import type { DayRange } from "./protocol.ts";

export interface SearchDetailProps {
  hit: LiturgicalSearchHit;
  library: SearchLibrary;
  usageRange: DayRange;
  onOpenOffice: (context: LiturgicalUsageContext) => void;
  onOpenMass: (mass: MassUsageContext) => void;
  onOpenChant: (score: ChantScore) => void;
}

const monthAndDay = new Intl.DateTimeFormat("en-US", {
  month: "long",
  day: "numeric",
});

type DetailPhase =
  | { readonly type: "loading" }
  | {
      readonly type: "loaded";
      readonly presentation: PrayerSearchDetailPresentation;
    }
  | { readonly type: "failed"; readonly message: string };

/** One result in full: its text, its chant settings, and where it is used. */
export function SearchDetail({
  hit,
  library,
  usageRange,
  onOpenOffice,
  onOpenMass,
  onOpenChant,
}: SearchDetailProps) {
  const [phase, setPhase] = useState<DetailPhase>({ type: "loading" });

  useEffect(() => {
    let cancelled = false;
    library.searchDetail(hit.id, usageRange).then(
      (result) => {
        if (cancelled) return;
        setPhase({
          type: "loaded",
          presentation: PrayerSearchDetailPresentations.make(result),
        });
      },
      (error: unknown) => {
        if (cancelled) return;
        setPhase({
          type: "failed",
          message: error instanceof Error ? error.message : String(error),
        });
      },
    );
    return () => {
      cancelled = true;
    };
    // The range is that of the day the result was opened on.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hit.id, library]);

  if (phase.type === "loading") {
    return (
      <div className="search-empty" role="status">
        <span className="spinner" />
        <p>Loading result{"\u{2026}"}</p>
      </div>
    );
  }
  if (phase.type === "failed") {
    return (
      <div className="search-empty">
        <SearchX aria-hidden="true" />
        <h3>Result unavailable</h3>
        <p>{phase.message}</p>
      </div>
    );
  }

  const { presentation } = phase;
  const english = presentation.result.english;
  const settings = presentation.chantSettings.length > 0 && (
    <section aria-labelledby="search-detail-chant">
      <h3 id="search-detail-chant">Chant settings</h3>
      <ul>
        {presentation.chantSettings.map((setting) => (
          <li key={setting.score.id}>
            <button
              type="button"
              className="search-row"
              data-setting={setting.score.id}
              onClick={() => onOpenChant(setting.score)}
            >
              <span className="search-setting">
                <span className="search-setting__incipit" lang="la">
                  {setting.score.incipit}
                </span>
                <span className="search-setting__label">
                  {PrayerSearchChantSettings.label(setting)}
                </span>
                <span className="search-setting__source">
                  {setting.score.provenance.sourceBook}
                </span>
              </span>
              <ChevronRight
                aria-hidden="true"
                className="search-row__chevron"
              />
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
  return (
    <div className="search-detail">
      {/* The words of the Ordinary are the same at every Mass: its settings
          are what is looked for, and come first. */}
      {presentation.leadsWithSettings && settings}
      <section aria-labelledby="search-detail-latin">
        <h3 id="search-detail-latin">Latin</h3>
        <p className="search-detail__latin" lang="la">
          {presentation.latinText}
        </p>
      </section>
      {english != null && (
        <section aria-labelledby="search-detail-english">
          <h3 id="search-detail-english">English</h3>
          <p className="search-detail__english">{english}</p>
        </section>
      )}
      {!presentation.leadsWithSettings && settings}
      {presentation.result.massContexts.length > 0 && (
        <section aria-labelledby="search-detail-mass">
          <header className="search-detail__usage">
            <h3 id="search-detail-mass">Used in the Mass</h3>
          </header>
          <ul>
            {presentation.result.massContexts.map((mass, position) => {
              const englishTitle = mass.titleEnglish;
              return (
                <li key={position}>
                  <button
                    type="button"
                    className="search-row"
                    title="Opens this Mass"
                    data-mass-usage=""
                    onClick={() => onOpenMass(mass)}
                  >
                    <span className="search-usage">
                      <span className="search-usage__day" lang="la">
                        {ObservanceTitle.latin(mass.titleLatin)}
                      </span>
                      {englishTitle != null &&
                        englishTitle !== mass.titleLatin && (
                          <span className="search-usage__english">
                            {ObservanceTitle.english(englishTitle)}
                          </span>
                        )}
                      <span className="search-usage__summary">
                        {PrayerSearchMassUsageRows.summary(
                          mass,
                          monthAndDay.format(LocalDays.date(mass.firstDate)),
                        )}
                      </span>
                    </span>
                    <ChevronRight
                      aria-hidden="true"
                      className="search-row__chevron"
                    />
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      )}
      {presentation.usageGroups.map((group, index) => (
        <section
          key={group.hour}
          aria-label={OfficeHours.englishTitle(group.hour)}
        >
          <header className="search-detail__usage">
            {index === 0 && <p>Used in the Office</p>}
            <h3>{OfficeHours.englishTitle(group.hour)}</h3>
          </header>
          <ul>
            {group.contexts.map((context, position) => {
              const english = PrayerSearchUsageRows.titleEnglish(context);
              return (
                <li key={position}>
                  <button
                    type="button"
                    className="search-row"
                    title={PrayerSearchUsageRows.accessibilityHint(context)}
                    onClick={() => onOpenOffice(context)}
                  >
                    <span className="search-usage">
                      <span className="search-usage__day" lang="la">
                        {PrayerSearchUsageRows.titleLatin(context)}
                      </span>
                      {english !== null && (
                        <span className="search-usage__english">{english}</span>
                      )}
                      <span className="search-usage__summary">
                        {PrayerSearchUsageRows.settingSummary(context)}
                      </span>
                    </span>
                    <ChevronRight
                      aria-hidden="true"
                      className="search-row__chevron"
                    />
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </div>
  );
}
