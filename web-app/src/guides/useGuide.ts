import { useCallback, useEffect, useState } from "react";
import { notationFontsReady } from "@/notation/engraver.ts";
import { describeGuideError } from "./guideLibrary.ts";

/** A guide on its way to the screen. */
export type GuideLoad<Value> =
  | { readonly status: "opening" }
  | { readonly status: "ready"; readonly value: Value }
  | { readonly status: "unavailable"; readonly message: string };

/**
 * Reads a guide for a screen. `loaded` is what has already been read, so
 * that a guide returned to appears at once; `load` reads it otherwise. The
 * second value fetches it again after a failure.
 */
export function useGuide<Value>(
  loaded: () => Value | null,
  load: () => Promise<Value>,
): [GuideLoad<Value>, () => void] {
  const [state, setState] = useState<GuideLoad<Value>>(() => {
    const value = loaded();
    return value === null ? { status: "opening" } : { status: "ready", value };
  });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setState((current) =>
      current.status === "ready" ? current : { status: "opening" },
    );
    load().then(
      (value) => {
        if (!cancelled) setState({ status: "ready", value });
      },
      (error: unknown) => {
        if (!cancelled) {
          setState({
            status: "unavailable",
            message: describeGuideError(error),
          });
        }
      },
    );
    return () => {
      cancelled = true;
    };
  }, [attempt, load]);

  const retry = useCallback(() => setAttempt((count) => count + 1), []);
  return [state, retry];
}

let notationFontsAreReady = false;

/**
 * Whether the typeface the notation's words are measured in has loaded.
 * Until it has, an example is not engraved: its lines would break in the
 * wrong places.
 */
export function useNotationFonts(): boolean {
  const [ready, setReady] = useState(notationFontsAreReady);
  useEffect(() => {
    if (ready) return;
    let cancelled = false;
    const finish = () => {
      notationFontsAreReady = true;
      if (!cancelled) setReady(true);
    };
    // A typeface that cannot be fetched does not hold the lesson back; the
    // notation is then set in what the browser has.
    void notationFontsReady().then(finish, finish);
    return () => {
      cancelled = true;
    };
  }, [ready]);
  return ready;
}
