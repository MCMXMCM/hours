import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { createContext, Script } from "node:vm";

export type ReadingToneName = "Lesson Ordinary Tone" | "Chapter";
export type ReadingToneGenerator = (
  text: string,
  tone: ReadingToneName
) => string;

interface ToneDefinition {
  clef: string;
  recitingTone: string;
  flexTone?: string;
  mediant: string;
  fullStop: string;
  question: string;
  conclusion: string;
}

interface ChantToolsExports {
  applyPsalmTone(options: Record<string, unknown>): string;
  bi_formats: Record<string, unknown>;
  getGabcTones(gabc: string, prefix?: string): unknown;
}

const tones: Record<ReadingToneName, ToneDefinition> = {
  "Lesson Ordinary Tone": {
    clef: "c3",
    recitingTone: "h",
    mediant: "((t[0].word&&t[0].word.length==1)||t[0].accent)?f hg..:'h hr g.",
    fullStop: "((t[0].word&&t[0].word.length==1)||t[0].accent)?f g.:(t[1]&&t[1].accent)?h. d.:'h dr d.",
    question: "h. , gr f g gh..",
    conclusion: "g f 'h hr h. , (t[1]&&t[1].accent)?hr h. d.:hr 'h dr d."
  },
  Chapter: {
    clef: "c3",
    recitingTone: "h",
    mediant: "((t[0].word&&t[0].word.length==1)||t[0].accent)?g f h.:g f 'h hr h.",
    fullStop: "'f er ef..",
    question: "h. , gr f g gh..",
    conclusion: "'f er ef.."
  }
};

function jqueryShim(): string {
  return `
var $ = function() {};
$.fn = {};
$.extend = function() {
    var args = Array.prototype.slice.call(arguments);
    var deep = typeof args[0] === "boolean" ? args.shift() : false;
    var target = args.shift() || {};
    args.forEach(function(source) {
      if (!source) return;
      Object.keys(source).forEach(function(key) {
        var value = source[key];
        if (deep && value && typeof value === "object") {
          var base = Array.isArray(value) ? [] : {};
          target[key] = $.extend(true, base, value);
        } else {
          target[key] = value;
        }
      });
    });
    return target;
  };
$.ajax = function() {
    throw new Error("Chant Tools attempted an unexpected network request");
  };
var jQuery = $;
var regexTag = /<(\\/?)(b|i|sc|v|span|font)>/i;
function getTagsFrom(txt) {
  var match, result = [];
  while ((match = regexTag.exec(txt))) {
    result.push(match[2]);
    var end = match.index + match[0].length;
    txt = match.index === 0
      ? txt.slice(match[0].length)
      : txt.slice(0, match.index) + txt.slice(end);
  }
  return result;
}`;
}

function loadRuntime(sourceRoot: string, expectedRevision: string): ChantToolsExports {
  const root = resolve(sourceRoot);
  const actual = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: root,
    encoding: "utf8"
  }).trim();
  if (actual !== expectedRevision) {
    throw new Error(`Chant Tools checkout is ${actual}; expected pinned ${expectedRevision}`);
  }

  const path = join(root, "psalmtone.js");
  const source = [
    jqueryShim(),
    readFileSync(join(root, "jquery.hypher.js"), "utf8"),
    readFileSync(join(root, "patterns", "la-hypher.js"), "utf8"),
    readFileSync(path, "utf8"),
    "exports.applyPsalmTone = applyPsalmTone;",
    "exports.bi_formats = bi_formats;",
    "exports.getGabcTones = getGabcTones;"
  ].join("\n");
  const exports: Record<string, unknown> = {};
  const localStorage: Record<string, string> = {};
  const sandbox: Record<string, unknown> = {
    exports,
    localStorage,
    location: { search: "" },
    _clef: "c3",
    URLSearchParams,
    setTimeout: () => 0,
    clearTimeout: () => undefined
  };
  sandbox.window = sandbox;
  const context = createContext(sandbox);
  new Script(source, { filename: path }).runInContext(context);
  return exports as unknown as ChantToolsExports;
}

function accentCount(gabc: string): number {
  const finalPhrase = (gabc || "")
    .replace(/^([,;:])/, " $1")
    .split(/\s*(?=[,;:])/)
    .at(-1) ?? "";
  return (finalPhrase.match(/'[a-m]/gi) ?? [""]).length;
}

function splitSentences(
  text: string,
  tone: ToneDefinition
): Array<{ line: string; punctuation: string }> {
  const accents = {
    question: accentCount(tone.question),
    mediant: accentCount(tone.mediant),
    fullStop: accentCount(tone.fullStop),
    flex: accentCount(tone.flexTone ?? "")
  };
  const pattern =
    /((?:,(?![,\r\n])["'“”‘’«»‹›]?|[^\^`~+.?!;:,])+($|,(?=[,\r\n])|[+^`~.?!;:](?:\s*[:+^`])?["'“”‘’«»‹›]*)),?\s*/gi;
  const result: Array<{ line: string; punctuation: string }> = [];
  for (const match of text.matchAll(pattern)) {
    // Keep the accent calculation in lockstep with the pinned implementation.
    // applyPsalmTone evaluates the actual accent requirements from the tone.
    switch (match[2]) {
    case ".":
    case "!": void accents.fullStop; break;
    case "?": void accents.question; break;
    case "+": void accents.flex; break;
    case ",":
    case ":": void accents.mediant; break;
    }
    result.push({ line: match[1], punctuation: match[2] ?? "" });
  }
  return result;
}

function generate(
  runtime: ChantToolsExports,
  text: string,
  toneName: ReadingToneName
): string {
  const tone = tones[toneName];
  const lines = splitSentences(text, tone);
  const prefix = `${tone.recitingTone}r `;
  const recitingTone = tone.recitingTone.replace(/^.+\s(\S+)$/, "$1");
  const pause = `${prefix}${recitingTone}.`;
  const flexTone = tone.flexTone ?? "";
  const flex = `t[0].accent?${prefix}${flexTone}:${prefix}'${recitingTone} ${flexTone}r ${flexTone}`;

  const splitTone = (gabc: string): unknown[] => {
    const parts = gabc.replace(/^([,;])/, " $1").split(/\s*(?=[,;])/);
    const result: unknown[] = [
      runtime.getGabcTones(parts[0] || tone.mediant, prefix)
    ];
    for (const part of parts.slice(1)) {
      result.push(part.slice(0, 1));
      result.push(runtime.getGabcTones(part.slice(1).trim()));
    }
    return result;
  };

  const mediant = runtime.getGabcTones(tone.mediant, prefix);
  const fullStop = splitTone(tone.fullStop);
  const question = splitTone(tone.question);
  const conclusion = splitTone(tone.conclusion || tone.fullStop);
  let gabc = " (::)";
  let toneStack = conclusion.slice();

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    let { line } = lines[index];
    const rawPunctuation = lines[index].punctuation;
    const punctuation = rawPunctuation.match(/[+^`]/)?.[0] ?? rawPunctuation[0];
    let psalmTone: unknown;
    let loop: boolean;
    do {
      psalmTone = toneStack.pop();
      loop = typeof psalmTone === "string";
      if (loop) {
        let separator = psalmTone as string;
        switch (punctuation) {
        case ".":
        case "!":
        case "?":
          separator = ":";
          break;
        case ":":
          if (!/^[;:,]$/.test(separator)) separator = line.slice(-2, -1) === ":" ? ":" : ";";
          break;
        case "+":
        case "^":
        case ",":
        case "`":
          if (!/^[;:,]$/.test(separator)) separator = ",";
          break;
        default:
          if (!/^[;:,]$/.test(separator)) separator = /[a-z]$/i.test(line) ? "," : ";";
        }
        gabc = ` (${separator}) ${gabc}`;
      }
    } while (loop);

    if (!psalmTone) {
      switch (punctuation) {
      case ".":
      case "!":
        toneStack = fullStop.slice();
        psalmTone = toneStack.pop();
        gabc = ` (:) ${gabc}`;
        break;
      case ":":
        if (line.slice(-2, -1) === ":") {
          line = line.slice(0, -1);
          toneStack = fullStop.slice();
          psalmTone = toneStack.pop();
          gabc = ` (:) ${gabc}`;
        } else {
          psalmTone = mediant;
          gabc = ` (;) ${gabc}`;
        }
        break;
      case "?":
        toneStack = question.slice();
        psalmTone = toneStack.pop();
        gabc = ` (:) ${gabc}`;
        break;
      case "+":
        if (flexTone) {
          psalmTone = flex;
          gabc = ` †(,) ${gabc}`;
          break;
        }
        psalmTone = pause;
        gabc = ` (,) ${gabc}`;
        break;
      case "^":
        psalmTone = pause;
        gabc = ` (,) ${gabc}`;
        break;
      case "`":
        psalmTone = pause.slice(0, -1);
        gabc = ` (,) ${gabc}`;
        break;
      case "~":
        line = line.slice(0, -1);
        psalmTone = mediant;
        gabc = ` (;) ${gabc}`;
        break;
      default:
        psalmTone = mediant;
        gabc = ` (;) ${gabc}`;
      }
    }

    gabc = runtime.applyPsalmTone({
      text: line,
      gabc: psalmTone,
      useOpenNotes: false,
      useBoldItalic: true,
      onlyVowel: false,
      format: runtime.bi_formats["gabc-plain"],
      verseNumber: "",
      prefix: false,
      suffix: false,
      italicizeIntonation: false,
      favor: "termination"
    }) + gabc;
  }

  return `centering-scheme: latin;\n%%\n(${tone.clef}) ${gabc}`;
}

export function pinnedReadingToneGenerator(
  sourceRoot: string,
  expectedRevision: string
): ReadingToneGenerator {
  const runtime = loadRuntime(sourceRoot, expectedRevision);
  return (text, tone) => generate(runtime, text, tone);
}
