import { memo, useCallback } from "react";
import {
  OfficeSections,
  type ChantScore,
  type OfficeSection,
} from "@/core/models.ts";
import { ChantScoreView } from "@/notation/ChantScoreView.tsx";
import type { EngravedNeume } from "@/notation/engraver.ts";
import { isMassReading, MissalText } from "./MissalText.tsx";
import { OfficeText } from "./OfficeText.tsx";
import { PsalterVerse } from "./PsalterVerse.tsx";
import {
  OfficeBilingualText,
  OfficeHeadingTranslation,
  OfficePrayerText,
  OfficeReaderSectionBuilder,
  PsalmTextFormatter,
} from "./presentation/index.ts";
import type { ScorePreparation } from "./readerScores.ts";

export interface OfficeSectionViewProps {
  section: OfficeSection;
  /** The element's ID, unique to its page: the section's own unless given. */
  elementID?: string;
  /** Whether the section is a Mass's, set as a missal sets it (MissalText). */
  isMass?: boolean;
  isFollowedByContinuation: boolean;
  showsEnglish: boolean;
  /** Whether the Latin is shown; without it, the English stands alone. */
  showsLatin?: boolean;
  /** Whether the Latin is sung from its score, where it has one. */
  showsChant?: boolean;
  usesCompactPsalmody: boolean;
  isPriestOrDeaconPresent: boolean;
  scorePreparation: ScorePreparation | null;
  /** The notes being sung, when this section's score is the cantor guide's. */
  sungEventID?: string | null;
  /** Set while the office is laid out for paper. */
  paged?: boolean;
  onSelectNeume: (
    section: OfficeSection,
    score: ChantScore,
    neume: EngravedNeume,
  ) => void;
}

function PsalmTextSection({
  section,
  showsEnglish,
  showsLatin = true,
  isPriestOrDeaconPresent,
}: Pick<
  OfficeSectionViewProps,
  "section" | "showsEnglish" | "showsLatin" | "isPriestOrDeaconPresent"
>) {
  const lines = PsalmTextFormatter.lines(
    OfficePrayerText.adjustedIn(
      section.latin,
      section,
      isPriestOrDeaconPresent,
    ),
    section.english == null
      ? null
      : OfficePrayerText.adjustedIn(
          section.english,
          section,
          isPriestOrDeaconPresent,
        ),
    section.title.length === 0 &&
      !PsalmTextFormatter.isSetVerseByLine(section.latin),
  );
  // The English in its own paragraphs, where it is not set verse by verse
  // beside the Latin: where the verses of the two do not agree.
  let unalignedEnglish: string[] | null = null;
  if (section.english != null && !lines.some((line) => line.english != null)) {
    const adjusted = OfficePrayerText.adjustedIn(
      section.english,
      section,
      isPriestOrDeaconPresent,
    );
    const paragraphs = (
      section.kind === "psalm"
        ? PsalmTextFormatter.scriptureParagraphs(adjusted)
        : adjusted
    )
      .split("\n\n")
      .map((paragraph) =>
        PsalmTextFormatter.strippingScriptureReference(paragraph),
      )
      .filter((paragraph) => paragraph.trim().length > 0);
    unalignedEnglish = paragraphs.length > 0 ? paragraphs : null;
  }

  // The rest of a psalm in compact psalmody is pointed for singing and
  // numbered after the verse sung from its score; else the verses are set
  // as a psalter sets them.
  if (
    !section.id.endsWith(OfficeReaderSectionBuilder.compactContinuationSuffix)
  ) {
    const form = section.kind === "hymn" ? "stanza" : "verse";
    const spacious = (showsLatin && showsEnglish) || form === "stanza";
    return (
      <div className={spacious ? "psalter psalter--spacious" : "psalter"}>
        {!showsLatin && unalignedEnglish !== null
          ? unalignedEnglish.map((paragraph, index) => (
              <PsalterVerse
                key={index}
                text={paragraph}
                fontSize={21}
                lineSpacing={3}
                form={form}
                lang="en"
              />
            ))
          : lines.map((line) => {
              const english =
                showsLatin && showsEnglish
                  ? OfficeBilingualText.distinctEnglish(
                      line.english ?? null,
                      line.latin,
                    )
                  : null;
              // A verse the English lacks keeps its Latin.
              const alone =
                line.english != null && line.english.length > 0
                  ? line.english
                  : line.latin;
              return (
                <div className="psalter__verse" key={line.id}>
                  {showsLatin ? (
                    <>
                      <PsalterVerse
                        text={line.latin}
                        fontSize={21}
                        lineSpacing={3}
                        form={form}
                        lang="la"
                      />
                      {english && (
                        <PsalterVerse
                          text={english}
                          fontSize={18}
                          lineSpacing={3}
                          form={form}
                          principal={false}
                          italic
                          lang="en"
                        />
                      )}
                    </>
                  ) : (
                    <PsalterVerse
                      text={alone}
                      fontSize={21}
                      lineSpacing={3}
                      form={form}
                      lang="en"
                    />
                  )}
                </div>
              );
            })}
        {showsLatin && showsEnglish && unalignedEnglish !== null && (
          <OfficeText
            text={unalignedEnglish.join("\n\n")}
            fontSize={18}
            lineSpacing={3}
            italic
            secondary
            className="psalm-text__english"
          />
        )}
      </div>
    );
  }

  if (!showsLatin && unalignedEnglish !== null) {
    return (
      <div className="psalm-text" lang="en">
        {unalignedEnglish.map((paragraph, index) => (
          <OfficeText
            key={index}
            text={paragraph}
            fontSize={21}
            lineSpacing={3}
          />
        ))}
      </div>
    );
  }
  return (
    <div className="psalm-text">
      {lines.map((line) => {
        const english =
          showsLatin && showsEnglish
            ? OfficeBilingualText.distinctEnglish(
                line.english ?? null,
                line.latin,
              )
            : null;
        // A verse the English lacks keeps its Latin.
        const alone =
          line.english != null && line.english.length > 0
            ? line.english
            : line.latin;
        return (
          <div className="psalm-text__line" key={line.id}>
            {line.number != null && (
              <span
                className={
                  showsLatin
                    ? "psalm-text__number"
                    : "psalm-text__number psalm-text__number--secondary"
                }
                aria-hidden="true"
              >
                {line.number}.
              </span>
            )}
            <div className="psalm-text__verse">
              {showsLatin ? (
                <>
                  <OfficeText
                    text={line.latin}
                    fontSize={21}
                    lineSpacing={3}
                    emphasizedRanges={line.emphasizedRanges}
                    label={
                      line.number != null
                        ? `${line.number}. ${line.latin}`
                        : undefined
                    }
                  />
                  {english && (
                    <OfficeText
                      text={english}
                      fontSize={18}
                      lineSpacing={3}
                      italic
                      secondary
                      className="psalm-text__english"
                    />
                  )}
                </>
              ) : (
                <OfficeText
                  text={alone}
                  fontSize={21}
                  lineSpacing={3}
                  label={
                    line.number != null ? `${line.number}. ${alone}` : undefined
                  }
                />
              )}
            </div>
          </div>
        );
      })}
      {showsLatin && showsEnglish && unalignedEnglish !== null && (
        <OfficeText
          text={unalignedEnglish.join("\n\n")}
          fontSize={18}
          lineSpacing={3}
          italic
          secondary
          className="psalm-text__english"
        />
      )}
    </div>
  );
}

/** One part of an office: its heading, its rubric, and its text or chant. */
export const OfficeSectionView = memo(function OfficeSectionView({
  section,
  elementID = section.id,
  isMass = false,
  isFollowedByContinuation,
  showsEnglish,
  showsLatin = true,
  showsChant = true,
  usesCompactPsalmody,
  isPriestOrDeaconPresent,
  scorePreparation,
  sungEventID,
  paged = false,
  onSelectNeume,
}: OfficeSectionViewProps) {
  const score = section.chant ?? null;
  const selectNeume = useCallback(
    (neume: EngravedNeume) => {
      if (score) onSelectNeume(section, score, neume);
    },
    [onSelectNeume, score, section],
  );
  // Sung from its score, where the Latin is shown with its chant.
  const showsScore =
    showsLatin &&
    showsChant &&
    score !== null &&
    !OfficePrayerText.requiresTextFallbackFor(section, isPriestOrDeaconPresent);
  // Psalms, and canticles set as psalms, verse by verse, and hymns stanza
  // by stanza: those without chant, and those whose chant is not shown. An
  // antiphon is set as prose.
  const usesPointedPsalmodyLayout =
    !showsScore &&
    !OfficeReaderSectionBuilder.isAntiphon(section) &&
    (section.kind === "psalm" ||
      (section.kind === "canticle" &&
        (usesCompactPsalmody ||
          score !== null ||
          PsalmTextFormatter.isSetVerseByLine(section.latin))) ||
      (section.kind === "hymn" && score !== null));
  const showsEnglishAlone = !showsLatin;
  // An antiphon read without its chant, set as a psalter sets one: in
  // italic after its red "Ant.", at the size of the psalm's verses.
  const isAntiphonText =
    !showsScore && !isMass && OfficeReaderSectionBuilder.isAntiphon(section);
  const rubric = OfficeSections.userFacingRubric(section);
  // The heading's English: the edition's, or the usual English of a heading
  // it prints in Latin alone.
  const headingEnglish =
    (section.titleEnglish != null && section.titleEnglish.length > 0
      ? section.titleEnglish
      : null) ?? OfficeHeadingTranslation.english(section.title);
  const heading = showsEnglishAlone
    ? (headingEnglish ?? section.title)
    : section.title;
  const titleEnglish =
    showsEnglish && showsLatin
      ? OfficeBilingualText.distinctEnglish(headingEnglish, section.title)
      : null;
  const shownRubric =
    showsEnglishAlone && rubric !== null
      ? section.rubricEnglish != null && section.rubricEnglish.length > 0
        ? section.rubricEnglish
        : rubric
      : rubric;
  const rubricEnglish =
    showsEnglish && showsLatin && rubric !== null
      ? OfficeBilingualText.distinctEnglish(
          section.rubricEnglish ?? null,
          rubric,
        )
      : null;

  let english: string | null = null;
  if (
    showsEnglish &&
    showsLatin &&
    section.english != null &&
    !usesPointedPsalmodyLayout
  ) {
    english = OfficeBilingualText.distinctEnglish(
      OfficePrayerText.adjustedIn(
        section.kind === "psalm"
          ? PsalmTextFormatter.scriptureParagraphs(section.english)
          : section.english,
        section,
        isPriestOrDeaconPresent,
      ),
      OfficePrayerText.adjustedIn(
        section.latin,
        section,
        isPriestOrDeaconPresent,
      ),
    );
  }

  const spacing = isFollowedByContinuation
    ? "continues"
    : section.kind === "psalm" || usesPointedPsalmodyLayout
      ? "psalmody"
      : "part";

  return (
    <section
      id={elementID}
      className={`office-section office-section--${spacing}`}
    >
      {section.title.length > 0 &&
        (section.kind === "psalm" ? (
          <h2
            className="office-section__psalm-title"
            lang={showsEnglishAlone ? "en" : "la"}
          >
            {heading}
          </h2>
        ) : (
          <div
            className={
              isMass
                ? "office-section__heading office-section__heading--missal"
                : "office-section__heading"
            }
          >
            <h2 lang={showsEnglishAlone ? "en" : "la"}>
              {heading.toUpperCase()}
            </h2>
            {titleEnglish && <p>{titleEnglish}</p>}
          </div>
        ))}

      {shownRubric !== null && (
        <div className="office-section__rubric">
          <p lang={showsEnglishAlone ? "en" : "la"}>{shownRubric}</p>
          {rubricEnglish && (
            <p className="office-section__rubric-english">{rubricEnglish}</p>
          )}
        </div>
      )}

      {showsScore && score ? (
        <div className="office-section__score">
          <ChantScoreView
            engraving={
              scorePreparation ?? {
                error: "The chant layout was not prepared.",
              }
            }
            sungEventID={sungEventID}
            onSelectNeume={selectNeume}
            paged={paged}
          />
        </div>
      ) : usesPointedPsalmodyLayout ? (
        <PsalmTextSection
          section={section}
          showsEnglish={showsEnglish}
          showsLatin={showsLatin}
          isPriestOrDeaconPresent={isPriestOrDeaconPresent}
        />
      ) : isMass ? (
        <div lang={showsEnglishAlone ? "en" : "la"}>
          <MissalText
            text={OfficePrayerText.adjustedIn(
              showsEnglishAlone &&
                section.english != null &&
                section.english.length > 0
                ? section.english
                : section.latin,
              section,
              isPriestOrDeaconPresent,
            )}
            fontSize={23}
            lineSpacing={7}
            voice={showsEnglishAlone ? "englishAlone" : "latin"}
            opensWithInitial
            isReading={isMassReading(section.kind)}
          />
        </div>
      ) : showsEnglishAlone ? (
        <div
          lang="en"
          className={isAntiphonText ? "office-section__antiphon" : undefined}
        >
          <OfficeText
            text={OfficePrayerText.adjustedIn(
              section.english != null && section.english.length > 0
                ? section.english
                : section.latin,
              section,
              isPriestOrDeaconPresent,
            )}
            fontSize={isAntiphonText ? 21 : 23}
            lineSpacing={isAntiphonText ? 3 : 7}
            className="office-section__prose"
          />
        </div>
      ) : (
        <div
          lang="la"
          className={isAntiphonText ? "office-section__antiphon" : undefined}
        >
          <OfficeText
            text={OfficePrayerText.adjustedIn(
              section.latin,
              section,
              isPriestOrDeaconPresent,
            )}
            fontSize={isAntiphonText ? 21 : 23}
            lineSpacing={isAntiphonText ? 3 : 7}
            className="office-section__prose"
          />
        </div>
      )}

      {english !== null &&
        (isMass && !showsScore ? (
          <MissalText
            text={english}
            fontSize={19}
            lineSpacing={5}
            voice="english"
          />
        ) : (
          <OfficeText
            text={english}
            fontSize={isAntiphonText ? 18 : 19}
            lineSpacing={isAntiphonText ? 3 : 5}
            italic={showsScore}
            secondary
            className="office-section__english"
          />
        ))}
    </section>
  );
});
