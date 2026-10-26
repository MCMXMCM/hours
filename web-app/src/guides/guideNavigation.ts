// How a guide's pages lead to one another.
//
// On iOS a guide is a stack of pages: its contents, then a lesson or a
// topic, each with a way back to the one before. Here a guide is one route,
// and the page shown within it is named in the address (`?lesson=neumes`),
// so that the browser's own Back, a reload, and a link all find it.

import { useCallback, useLayoutEffect, type RefObject } from "react";
import { useLocation, useNavigate } from "react-router-dom";

/** Marks a page of a guide that was opened from the page above it. */
interface GuideLocationState {
  readonly openedWithinGuide?: boolean;
}

/**
 * How many pages of this visit lie behind the present one. The router keeps
 * the count with each entry of the browser's history.
 */
function pagesBehind(): number {
  const state = window.history.state as { idx?: unknown } | null;
  return typeof state?.idx === "number" ? state.idx : 0;
}

export interface GuideNavigation {
  /** Opens a page of the guide beneath the present one. */
  open(search: string): void;
  /** Returns to the page above the present one, which `search` names. */
  up(search: string): void;
  /** Leaves the guide for where the reader came from, or for Home. */
  leave(): void;
}

export function useGuideNavigation(): GuideNavigation {
  const navigate = useNavigate();
  const location = useLocation();
  const openedWithinGuide =
    (location.state as GuideLocationState | null)?.openedWithinGuide === true;

  const open = useCallback(
    (search: string) => {
      const state: GuideLocationState = { openedWithinGuide: true };
      navigate({ search }, { state });
    },
    [navigate],
  );

  const up = useCallback(
    (search: string) => {
      // A page reached from the one above returns to it; a page a link
      // opened directly has nothing behind it that belongs to the guide.
      if (openedWithinGuide && pagesBehind() > 0) navigate(-1);
      else navigate({ search }, { replace: true });
    },
    [navigate, openedWithinGuide],
  );

  const leave = useCallback(() => {
    if (pagesBehind() > 0) navigate(-1);
    else navigate("/", { replace: true });
  }, [navigate]);

  return { open, up, leave };
}

/**
 * Keeps a page's place while a page beneath it is read. The page opens where
 * `offset` says, and records there how far it has since been scrolled.
 */
export function useRememberedScroll(offset: RefObject<number>): void {
  useLayoutEffect(() => {
    window.scrollTo(0, offset.current);
    const remember = () => {
      offset.current = window.scrollY;
    };
    window.addEventListener("scroll", remember, { passive: true });
    return () => window.removeEventListener("scroll", remember);
  }, [offset]);
}

/** Opens a page at its head, as a lesson or a topic always opens. */
export function useOpensAtTop(): void {
  useLayoutEffect(() => {
    window.scrollTo(0, 0);
  }, []);
}
