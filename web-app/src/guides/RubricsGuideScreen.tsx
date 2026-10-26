import { ArrowUpRight, ChevronRight, ListMusic, Search } from "lucide-react";
import { useEffect, useRef, useState, type RefObject } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { GuideBar } from "./GuideBar.tsx";
import { guideLibrary } from "./guideLibrary.ts";
import {
  useGuideNavigation,
  useOpensAtTop,
  useRememberedScroll,
  type GuideNavigation,
} from "./guideNavigation.ts";
import { GuideOpening, GuideUnavailable } from "./GuideStatus.tsx";
import {
  RubricsCitations,
  RubricsEditions,
  RubricsRules,
  RubricsTopics,
  type RubricsEdition,
  type RubricsEditionGuide,
  type RubricsTopic,
} from "./rubricsGuide.ts";
import { useGuide } from "./useGuide.ts";
import "./guides.css";

// Where the pages of the reference are found:
// `/guides/rubrics?edition=roman1954&topic=vespers`.
const editionParameter = "edition";
const topicParameter = "topic";

function editionSearch(edition: RubricsEdition): string {
  return `?${new URLSearchParams({ [editionParameter]: edition })}`;
}

function topicSearch(edition: RubricsEdition, topicID: string): string {
  return `?${new URLSearchParams({
    [editionParameter]: edition,
    [topicParameter]: topicID,
  })}`;
}

const loadedRubricsGuides = () => guideLibrary.loadedRubricsGuides;
const loadRubricsGuides = () => guideLibrary.rubricsGuides();

/** What has been typed into an edition's search, kept while the edition is read. */
interface EditionSearch {
  readonly edition: RubricsEdition;
  readonly text: string;
}

interface EditionChooserProps {
  editions: readonly RubricsEditionGuide[];
  navigation: GuideNavigation;
}

/** The editions of the Roman Office the reference describes. */
function EditionChooser({ editions, navigation }: EditionChooserProps) {
  useOpensAtTop();
  return (
    <main className="guide">
      <GuideBar title="Rubrics" label="Rubrics" onBack={navigation.leave} />
      <div id="rubrics-editions" className="guide__column">
        <header className="guide-introduction">
          <h1>Rubrics</h1>
          <p className="guide-introduction__text">
            Choose an edition of the Roman Office to consult its principles and
            sources.
          </p>
        </header>

        <section aria-labelledby="rubrics-editions-title">
          <h2 id="rubrics-editions-title" className="guide-section-title">
            Editions
          </h2>
          <ul className="guide-list">
            {editions.map((edition) => (
              <li key={edition.id}>
                <Link
                  id={`rubrics-edition-${edition.year}`}
                  className="guide-row"
                  to={{ search: editionSearch(edition.id) }}
                  state={{ openedWithinGuide: true }}
                >
                  <span className="guide-row__text">
                    <span className="guide-row__title guide-row__title--large">
                      {edition.year}
                    </span>
                    <span className="guide-row__summary">
                      {edition.subtitle}
                    </span>
                  </span>
                  <ChevronRight
                    className="guide-row__chevron"
                    aria-hidden="true"
                  />
                </Link>
              </li>
            ))}
          </ul>
          <p className="guide-section-footer">
            Consulting a reference does not change the edition selected for
            prayer.
          </p>
        </section>
      </div>
    </main>
  );
}

interface EditionGuideProps {
  edition: RubricsEditionGuide;
  navigation: GuideNavigation;
  searchText: string;
  onSearchTextChange: (text: string) => void;
  /** How far the topics had been scrolled when one was opened. */
  scrollOffset: RefObject<number>;
}

/** An edition's reference: what it is, and its topics, which can be searched. */
function EditionGuide({
  edition,
  navigation,
  searchText,
  onSearchTextChange,
  scrollOffset,
}: EditionGuideProps) {
  useRememberedScroll(scrollOffset);
  const topics = edition.topics.filter((topic) =>
    RubricsTopics.matches(topic, searchText),
  );

  return (
    <main className="guide">
      <GuideBar
        title={`${edition.year} Rubrics`}
        label="Rubrics"
        onBack={() => navigation.up("")}
      />
      <div id="rubrics-topics" className="guide__column">
        <form
          className="guide-search"
          role="search"
          onSubmit={(event) => {
            event.preventDefault();
            (window.document.activeElement as HTMLElement | null)?.blur();
          }}
        >
          <Search aria-hidden="true" />
          <input
            type="search"
            aria-label="Search rubrics"
            placeholder="Search rubrics"
            autoCapitalize="none"
            autoComplete="off"
            autoCorrect="off"
            spellCheck={false}
            enterKeyHint="search"
            value={searchText}
            onChange={(event) => onSearchTextChange(event.target.value)}
          />
        </form>

        <header id="rubrics-introduction" className="guide-introduction">
          <h1>Rubrics</h1>
          <p className="guide-introduction__subtitle">
            The Roman Office · {edition.year}
          </p>
          <p className="guide-introduction__text">{edition.introduction}</p>
        </header>

        <section aria-labelledby="rubrics-topics-title">
          <h2 id="rubrics-topics-title" className="guide-section-title">
            {searchText.length === 0 ? "Topics" : "Matching topics"}
          </h2>
          {topics.length > 0 && (
            <ul className="guide-list">
              {topics.map((topic) => (
                <li key={topic.id}>
                  <Link
                    id={`rubrics-topic-${topic.id}`}
                    className="guide-row"
                    to={{ search: topicSearch(edition.id, topic.id) }}
                    state={{ openedWithinGuide: true }}
                    aria-description="Opens this rubric reference"
                  >
                    <span className="guide-row__text">
                      <span className="guide-row__title">{topic.title}</span>
                      <span className="guide-row__summary">
                        {topic.summary}
                      </span>
                    </span>
                    <ChevronRight
                      className="guide-row__chevron"
                      aria-hidden="true"
                    />
                  </Link>
                </li>
              ))}
            </ul>
          )}
          {topics.length === 0 && (
            <div id="rubrics-no-results" className="guide-no-results">
              <Search aria-hidden="true" />
              <h3>
                No Results for {"\u{201C}"}
                {searchText}
                {"\u{201D}"}
              </h3>
              <p>Check the spelling or try a new search.</p>
            </div>
          )}
        </section>
      </div>
    </main>
  );
}

interface TopicReaderProps {
  topic: RubricsTopic;
  edition: RubricsEditionGuide;
  navigation: GuideNavigation;
}

/** One topic of the reference: its rules, each with the sources it rests on. */
function TopicReader({ topic, edition, navigation }: TopicReaderProps) {
  useOpensAtTop();
  return (
    <main className="guide">
      <GuideBar
        title={topic.title}
        label="Rubrics"
        onBack={() => navigation.up(editionSearch(edition.id))}
      />
      <div className="guide__column">
        <article id="rubrics-reader" className="rubrics-topic">
          <header className="guide-heading">
            <h1 id="rubrics-topic-title">{topic.title}</h1>
            <p id="rubrics-reader-edition">
              Roman Office · {edition.year} rubrics
            </p>
          </header>

          {topic.rules.map((rule) => (
            <section key={rule.id} className="rubrics-rule">
              <h2>{rule.title}</h2>
              <div className="rubrics-rule__text">
                {RubricsRules.paragraphs(rule).map((paragraph, index) => (
                  <p key={index}>{paragraph}</p>
                ))}
              </div>
              {rule.citations.length > 0 && (
                <ul className="rubrics-rule__citations">
                  {rule.citations.map((citation) => (
                    <li key={RubricsCitations.id(citation)}>
                      <a
                        className="rubrics-citation"
                        href={citation.url}
                        target="_blank"
                        rel="noreferrer"
                        aria-description="Opens the source online"
                      >
                        {citation.label}
                        <ArrowUpRight aria-hidden="true" />
                      </a>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          ))}

          {topic.id === "chant" && (
            <Link
              id="rubrics-chant-guide"
              className="rubrics-topic__examples"
              to="/guides/chant"
            >
              <ListMusic aria-hidden="true" />
              Study the examples in Guide to Chant
            </Link>
          )}
        </article>
      </div>
    </main>
  );
}

/**
 * The Rubrics reference, at `/guides/rubrics`: the editions it describes, at
 * `?edition=…` an edition's topics, and at `&topic=…` one of them. Which
 * edition is consulted is the reader's choice here, and has no bearing on
 * the edition selected for prayer.
 */
export default function RubricsGuideScreen() {
  const navigation = useGuideNavigation();
  const [parameters] = useSearchParams();
  const [guides, retry] = useGuide(loadedRubricsGuides, loadRubricsGuides);
  const [search, setSearch] = useState<EditionSearch | null>(null);
  const topicsScrollOffset = useRef(0);

  const editionID = RubricsEditions.fromRawValue(
    parameters.get(editionParameter) ?? "",
  );
  const edition =
    guides.status !== "ready" || editionID === null
      ? null
      : (guides.value.find((candidate) => candidate.id === editionID) ?? null);

  // What was sought in an edition, and how far its topics had been read, are
  // forgotten once the reader has left it for the editions.
  const showsEditions = guides.status === "ready" && edition === null;
  useEffect(() => {
    if (!showsEditions) return;
    setSearch(null);
    topicsScrollOffset.current = 0;
  }, [showsEditions]);

  if (guides.status !== "ready") {
    return (
      <main className="guide">
        <GuideBar title="Rubrics" label="Rubrics" onBack={navigation.leave} />
        {guides.status === "opening" ? (
          <GuideOpening />
        ) : (
          <GuideUnavailable message={guides.message} onRetry={retry} />
        )}
      </main>
    );
  }

  if (!edition) {
    return <EditionChooser editions={guides.value} navigation={navigation} />;
  }

  const topicID = parameters.get(topicParameter);
  const topic =
    topicID === null
      ? null
      : (edition.topics.find((candidate) => candidate.id === topicID) ?? null);
  if (topic) {
    return (
      <TopicReader
        key={`${edition.id}:${topic.id}`}
        topic={topic}
        edition={edition}
        navigation={navigation}
      />
    );
  }
  return (
    <EditionGuide
      key={edition.id}
      edition={edition}
      navigation={navigation}
      searchText={search?.edition === edition.id ? search.text : ""}
      onSearchTextChange={(text) => setSearch({ edition: edition.id, text })}
      scrollOffset={topicsScrollOffset}
    />
  );
}
