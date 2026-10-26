import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useAppModel, useAppState, useServices } from "@/app/context.tsx";
import { massPath, parseMassRoute } from "@/app/routes.ts";
import { type OfficeDocument } from "@/core/models.ts";
import { CorpusError, type WebMassListing } from "@/data/corpus.ts";
import { Reader } from "./ReaderScreen.tsx";

/** A Mass as the choice among a day's Masses names it. */
function massName(listing: WebMassListing): string {
  return (
    listing.labelEnglish ??
    listing.label ??
    listing.titleEnglish ??
    listing.titleLatin
  );
}

type Loaded =
  | { readonly state: "loading" }
  | { readonly state: "failed"; readonly message: string }
  | {
      readonly state: "ready";
      readonly mass: OfficeDocument;
      readonly listings: readonly WebMassListing[];
    };

/** The Mass of a day, at `/mass/:date` or `/mass/:date/:number`. */
export default function MassScreen() {
  const params = useParams();
  const navigate = useNavigate();
  const model = useAppModel();
  const state = useAppState();
  const { corpus } = useServices();
  const route = useMemo(
    () => parseMassRoute(params.date, params.number),
    [params.date, params.number],
  );
  const [loaded, setLoaded] = useState<Loaded>({ state: "loading" });
  const edition = state.officeTradition;

  useEffect(() => {
    if (!route) {
      navigate("/", { replace: true });
      return;
    }
    let isCurrent = true;
    setLoaded({ state: "loading" });
    void (async () => {
      try {
        await model.start();
        const [listings, mass] = await Promise.all([
          corpus.masses(edition, route.day),
          corpus.mass(edition, route.day, route.index),
        ]);
        if (!isCurrent) return;
        // A Mass newly opened begins on its Latin page.
        model.beginMass();
        setLoaded({ state: "ready", mass, listings });
      } catch (error) {
        if (!isCurrent) return;
        setLoaded({
          state: "failed",
          message:
            error instanceof CorpusError && error.failure === "offline"
              ? "The Mass could not be loaded. Check the connection and try again."
              : "This Mass is not available.",
        });
      }
    })();
    return () => {
      isCurrent = false;
    };
  }, [corpus, edition, model, navigate, route]);

  if (loaded.state === "ready" && route) {
    const choice =
      loaded.listings.length > 1 ? (
        <nav className="mass-choice" aria-label="The day's Masses">
          {loaded.listings.map((listing, index) => (
            <button
              key={listing.key}
              type="button"
              className="mass-choice__option"
              aria-current={index === route.index ? "page" : undefined}
              onClick={() =>
                navigate(massPath(route.day, index), { replace: true })
              }
            >
              {massName(listing)}
            </button>
          ))}
        </nav>
      ) : null;
    return (
      <Reader
        key={loaded.mass.id}
        office={loaded.mass}
        // A Mass keeps the light of the Hour chosen on Home.
        skyHour={state.selectedHour}
        title="Missa"
        titleEnglish="Mass"
        header={choice}
        onClose={() => navigate("/")}
      />
    );
  }
  return (
    <main className="reader reader--unloaded">
      {loaded.state === "failed" ? (
        <div className="reader__status" role="alert">
          <h1>Mass unavailable</h1>
          <p>{loaded.message}</p>
          <button type="button" onClick={() => navigate("/")}>
            Back
          </button>
        </div>
      ) : (
        <div className="reader__status" role="status" aria-label="Loading">
          <span className="spinner" />
        </div>
      )}
    </main>
  );
}
