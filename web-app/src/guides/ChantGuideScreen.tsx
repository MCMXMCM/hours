import { BookA, ChevronRight } from "lucide-react";
import { useEffect, useRef, useState, type RefObject } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { usePlayback } from "@/cantor/usePlayback.ts";
import { Sheet } from "@/components/Sheet.tsx";
import {
  ChantGuideTerms,
  type ChantGuideDocument,
} from "./chantGuideDocument.ts";
import { ChantGuideLesson } from "./ChantGuideLesson.tsx";
import { GuideBar } from "./GuideBar.tsx";
import { guideLibrary } from "./guideLibrary.ts";
import {
  useGuideNavigation,
  useRememberedScroll,
  type GuideNavigation,
} from "./guideNavigation.ts";
import { GuideOpening, GuideUnavailable } from "./GuideStatus.tsx";
import { useGuide, useNotationFonts } from "./useGuide.ts";
import "./guides.css";

/** Where a lesson of the guide is found: `/guides/chant?lesson=neumes`. */
const lessonParameter = "lesson";

function lessonSearch(sectionID: string): string {
  return `?${new URLSearchParams({ [lessonParameter]: sectionID })}`;
}

const loadedChantGuide = () => guideLibrary.loadedChantGuide;
const loadChantGuide = () => guideLibrary.chantGuide();

/** How long a sheet takes to leave the page it covers. */
const sheetDismissal = 260;

interface TopicsProps {
  document: ChantGuideDocument;
  navigation: GuideNavigation;
  /** How far the contents had been scrolled when a lesson was opened. */
  scrollOffset: RefObject<number>;
}

/** The guide's contents: what it is, its lessons, and its glossary. */
function Topics({ document, navigation, scrollOffset }: TopicsProps) {
  const [showsGlossary, setShowsGlossary] = useState(false);
  // The typeface of the notation is asked for here, so that a lesson finds it.
  useNotationFonts();
  useRememberedScroll(scrollOffset);

  return (
    <main className="guide">
      <GuideBar
        title="Guide to Chant"
        label="Guide to Chant"
        onBack={navigation.leave}
      >
        <button
          type="button"
          id="chant-guide-glossary"
          className="guide-bar__action"
          onClick={() => setShowsGlossary(true)}
        >
          <BookA aria-hidden="true" />
          <span>Glossary</span>
        </button>
      </GuideBar>

      <div id="chant-guide-topics" className="guide__column">
        <header id="chant-guide-introduction" className="guide-introduction">
          <h1>{document.title}</h1>
          <p className="guide-introduction__text">{document.introduction}</p>
        </header>

        <ul className="guide-list">
          {document.sections.map((section) => (
            <li key={section.id}>
              <Link
                id={`chant-guide-lesson-${section.id}`}
                className="guide-row"
                to={{ search: lessonSearch(section.id) }}
                state={{ openedWithinGuide: true }}
                aria-description="Opens this chant lesson"
              >
                <span className="guide-row__text">
                  <span className="guide-row__title">{section.title}</span>
                </span>
                <ChevronRight
                  className="guide-row__chevron"
                  aria-hidden="true"
                />
              </Link>
            </li>
          ))}
        </ul>
      </div>

      <Sheet
        open={showsGlossary}
        onOpenChange={setShowsGlossary}
        title="Chant glossary"
        closeLabel="Done"
      >
        <ul className="guide-glossary">
          {document.glossary.map((term) => (
            <li key={ChantGuideTerms.id(term)}>
              <button
                type="button"
                onClick={() => {
                  setShowsGlossary(false);
                  // The lesson opens once the sheet has gone.
                  window.setTimeout(
                    () => navigation.open(lessonSearch(term.sectionID)),
                    sheetDismissal,
                  );
                }}
              >
                <span className="guide-glossary__term">{term.term}</span>
                <span className="guide-glossary__definition">
                  {term.definition}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </Sheet>
    </main>
  );
}

/**
 * The Guide to Chant, at `/guides/chant`: its contents, and at
 * `?lesson=…` one of its lessons.
 */
export default function ChantGuideScreen() {
  const playback = usePlayback();
  const navigation = useGuideNavigation();
  const [parameters] = useSearchParams();
  const [guide, retry] = useGuide(loadedChantGuide, loadChantGuide);
  const topicsScrollOffset = useRef(0);

  // The guide opens in silence, whatever was being sung before it.
  useEffect(() => playback.stop(), [playback]);

  if (guide.status !== "ready") {
    return (
      <main className="guide">
        <GuideBar
          title="Guide to Chant"
          label="Guide to Chant"
          onBack={navigation.leave}
        />
        {guide.status === "opening" ? (
          <GuideOpening />
        ) : (
          <GuideUnavailable message={guide.message} onRetry={retry} />
        )}
      </main>
    );
  }

  const lessonID = parameters.get(lessonParameter);
  const section =
    lessonID === null
      ? null
      : (guide.value.sections.find((candidate) => candidate.id === lessonID) ??
        null);
  if (section) {
    return (
      <ChantGuideLesson
        key={section.id}
        document={guide.value}
        section={section}
        onBack={() => navigation.up("")}
      />
    );
  }
  return (
    <Topics
      document={guide.value}
      navigation={navigation}
      scrollOffset={topicsScrollOffset}
    />
  );
}
