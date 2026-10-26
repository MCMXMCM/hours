// Keeping Hours usable without a connection, and up to date with one.
//
// The service worker holds the app itself and every office it has served.
// This module registers it, says when a newer copy of the app is waiting,
// and quietly fetches the coming days so they are at hand offline.

import { LocalDays, officeHours } from "@/core/models.ts";
import type { AppModel } from "./appModel.ts";
import { Store } from "./store.ts";

export interface UpdateState {
  /** A newer copy of the app has been downloaded and waits to take over. */
  readonly isWaiting: boolean;
}

export const updateStore = new Store<UpdateState>({ isWaiting: false });

let applyUpdate: (() => Promise<void>) | null = null;

/** Registers the service worker. A development server has none. */
export async function registerServiceWorker(): Promise<void> {
  if (!import.meta.env.PROD || !("serviceWorker" in navigator)) return;
  const { registerSW } = await import("virtual:pwa-register");
  const update = registerSW({
    onNeedRefresh() {
      updateStore.set({ isWaiting: true });
    },
  });
  applyUpdate = () => update(true);
}

/** Reloads into the waiting copy of the app. */
export async function reloadIntoUpdate(): Promise<void> {
  updateStore.set({ isWaiting: false });
  if (applyUpdate) await applyUpdate();
  else location.reload();
}

/** How many days beyond today are fetched ahead for use offline. */
export const offlineDays = 7;

/**
 * Fetches today's remaining offices and the coming week's, and each day's
 * Masses, one at a time and only while the browser is idle and the
 * connection is not metered-saving. Each is cached by the service worker as
 * it arrives.
 */
export function keepComingDaysAtHand(model: AppModel): () => void {
  if (!import.meta.env.PROD) return () => undefined;
  const connection = (
    navigator as Navigator & { connection?: { saveData?: boolean } }
  ).connection;
  if (connection?.saveData) return () => undefined;

  let cancelled = false;
  const today = LocalDays.fromDate(new Date());
  const pending: Array<() => void> = [];
  for (let offset = 0; offset <= offlineDays; offset += 1) {
    const day = LocalDays.adding(today, offset);
    for (const hour of officeHours) {
      pending.push(() => model.prefetch(day, hour));
    }
    pending.push(() => model.prefetchMasses(day));
  }
  const idle =
    window.requestIdleCallback?.bind(window) ??
    ((callback: () => void) => window.setTimeout(callback, 400));
  const next = () => {
    if (cancelled || !navigator.onLine) return;
    const fetchOne = pending.shift();
    if (!fetchOne) return;
    fetchOne();
    window.setTimeout(() => idle(next), 150);
  };
  const timer = window.setTimeout(() => idle(next), 4000);
  return () => {
    cancelled = true;
    window.clearTimeout(timer);
  };
}
