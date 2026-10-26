// What the cantor guide's bar is called, parallel to `CantorGuideTitle` in
// `HoursApp/PlaybackControlsView.swift`. The web bar is put away by its
// close button or Escape, not by the native app's downward drag.

import type { ChantScore } from "@/core/models.ts";
import { GregorianScoreParser } from "@/core/notation/index.ts";
import { trimmingWhitespaceAndNewlines } from "@/core/swiftString.ts";

function isStandaloneVersicleOrResponse(value: string): boolean {
  const marker = trimmingWhitespaceAndNewlines(value);
  return [
    "V/",
    "V/.",
    "R/",
    "R/.",
    "\u{2123}",
    "\u{2123}.",
    "\u{211F}",
    "\u{211F}.",
  ].includes(marker);
}

function append(text: string, startsWord: boolean, line: string): string {
  if (text.length === 0) return line;
  return startsWord && line.length > 0 ? `${line} ${text}` : line + text;
}

export const CantorGuideTitle = {
  /**
   * A score whose incipit is only the versicle or response sign is named by
   * the line it sets instead.
   */
  text(score: ChantScore): string {
    if (!isStandaloneVersicleOrResponse(score.incipit)) return score.incipit;
    let parsedScore;
    try {
      parsedScore = GregorianScoreParser.parse(score.gabc, score.timeline);
    } catch {
      return score.incipit;
    }

    let line = "";
    for (const element of parsedScore.elements) {
      switch (element.type) {
        case "lyricMark":
          if (isStandaloneVersicleOrResponse(element.lyricMark.text)) continue;
          line = append(
            element.lyricMark.text,
            element.lyricMark.startsWord,
            line,
          );
          break;
        case "neume":
          line = append(element.neume.lyric, element.neume.startsWord, line);
          break;
        default:
          continue;
      }
    }
    return line.length === 0 ? score.incipit : line;
  },
};
