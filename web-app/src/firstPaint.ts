// Gives the page the appearance of its hour before it is first painted.
//
// The app settles its appearance as it starts, but a browser does not wait
// for the app before it paints: at a night hour the page was shown light,
// and darkened only when the app had arrived. This is therefore built apart
// from the app (see `firstPaint` in `vite.config.ts`), as a script the
// browser runs before it paints anything, and it settles what the app will
// settle, by the same rules.

import { applyMobileWheelBrowserClass } from "@site/mobile-browser-layout.js";
import {
  openingHour,
  savedAppearance,
  showAppearance,
} from "./app/appearanceState.ts";
import { launch } from "./app/launch.ts";
import { Preferences } from "./app/preferences.ts";
import {
  homeShowsSky,
  openingWheelRotation,
  showHomeSky,
} from "./home/ambientSky.ts";

const root = document.documentElement;
const preferences = new Preferences();
const opening = launch(preferences, new Date(), location.pathname);
const appearance = savedAppearance(
  preferences,
  openingHour(location.pathname, opening.selectedHour),
  matchMedia("(prefers-color-scheme: dark)").matches,
);
showAppearance(root, appearance);

// Home's wheel lies under a sky of its own, and stands where the bars of
// the browser it is shown in leave it room (see `.home--wheel`).
if (location.pathname === "/" && homeShowsSky(appearance)) {
  showHomeSky(
    root,
    openingWheelRotation(
      opening.selectedHour,
      opening.automaticallySelectsCurrentOffice,
      matchMedia("(prefers-reduced-motion: reduce)").matches,
      new Date(),
    ),
  );
}
void applyMobileWheelBrowserClass();
