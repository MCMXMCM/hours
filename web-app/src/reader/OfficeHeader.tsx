import { useAppModel, useAppState } from "@/app/context.tsx";
import { OfficeTraditions } from "@/app/officeTradition.ts";
import {
  LocalDays,
  ObservanceTitle,
  OfficeDocuments,
  Ranks,
  type OfficeDocument,
} from "@/core/models.ts";
import { OfficeBilingualText } from "./presentation/index.ts";

/**
 * The head of an office: its rank, the hour, and the day's observance, in
 * the language of its page; with the English beneath the Latin where both
 * are set together, as on paper.
 */
export function OfficeHeader({
  office,
  showsLatin,
  showsEnglish,
  elementID = "office-top",
}: {
  office: OfficeDocument;
  showsLatin: boolean;
  showsEnglish: boolean;
  /** The element's ID, unique to its page. */
  elementID?: string;
}) {
  const model = useAppModel();
  const state = useAppState();
  const observanceLatin = ObservanceTitle.latin(
    office.observance?.titleLatin ?? office.contextLabel,
  );
  const observanceEnglish =
    office.observance?.titleEnglish != null
      ? ObservanceTitle.english(office.observance.titleEnglish)
      : null;
  const rank =
    (office.observance ? Ranks.rankLabel(office.observance) : null) ??
    // Home's day's, but not for a Mass of another day.
    (state.selectedDay &&
    (!OfficeDocuments.isMass(office) ||
      LocalDays.equals(state.selectedDay.date, office.date))
      ? Ranks.rankLabel(state.selectedDay)
      : null) ??
    OfficeDocuments.englishName(office);
  // The English beneath the Latin, or in its place where it is shown alone.
  const showsEnglishAlone = !showsLatin;
  const title = showsEnglishAlone
    ? (office.titleEnglish ?? office.titleLatin)
    : office.titleLatin;
  const observance = showsEnglishAlone
    ? (observanceEnglish ?? observanceLatin)
    : observanceLatin;
  const titleEnglish =
    showsEnglish && !showsEnglishAlone
      ? OfficeBilingualText.distinctEnglish(
          office.titleEnglish ?? null,
          office.titleLatin,
        )
      : null;
  const observanceTitleEnglish =
    showsEnglish && !showsEnglishAlone
      ? OfficeBilingualText.distinctEnglish(observanceEnglish, observanceLatin)
      : null;

  return (
    <header className="office-header" id={elementID}>
      {model.isDevelopmentCorpus && (
        <p className="office-header__banner">DEVELOPMENT CORPUS</p>
      )}
      <p className="office-header__rank">{rank}</p>
      {state.officeTradition !== "roman1960" && (
        <p className="office-header__edition">
          {OfficeTraditions.title(state.officeTradition)}
        </p>
      )}
      <h1
        className="office-header__title"
        lang={showsEnglishAlone ? "en" : "la"}
      >
        {title}
      </h1>
      {titleEnglish && (
        <p className="office-header__title-english">{titleEnglish}</p>
      )}
      <p
        className="office-header__observance"
        lang={showsEnglishAlone ? "en" : "la"}
      >
        {observance}
      </p>
      {observanceTitleEnglish && (
        <p className="office-header__observance-english">
          {observanceTitleEnglish}
        </p>
      )}
    </header>
  );
}
