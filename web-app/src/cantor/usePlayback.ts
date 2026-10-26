// The cantor guide as the reader's views reach it. There is one guide for
// the app, made when a view first asks for it, so that the home screen need
// not carry the guide's code.

import { useServices } from "@/app/context.tsx";
import { useStore } from "@/app/store.ts";
import {
  ChantPlaybackController,
  type ChantPlaybackState,
} from "./controller.ts";
import { FetchedHarpBank } from "./harp.ts";
import { WebAudioCantorPlayer } from "./webAudioPlayer.ts";

/** Where the harp's recordings are served, beside the app. */
export const harpBaseURL = `${import.meta.env.BASE_URL}harp/`;

let shared: ChantPlaybackController | null = null;
let harp: FetchedHarpBank | null = null;

export function sharedHarpBank(): FetchedHarpBank {
  const connection = (
    navigator as Navigator & { connection?: { saveData?: boolean } }
  ).connection;
  // The service worker keeps what is fetched; a development server has none.
  harp ??= new FetchedHarpBank(harpBaseURL, {
    keepsAtHand: import.meta.env.PROD && connection?.saveData !== true,
  });
  return harp;
}

export function usePlayback(): ChantPlaybackController {
  const { preferences } = useServices();
  shared ??= new ChantPlaybackController(
    new WebAudioCantorPlayer(sharedHarpBank()),
    preferences,
  );
  return shared;
}

export function usePlaybackState(): ChantPlaybackState {
  return useStore(usePlayback().store);
}
