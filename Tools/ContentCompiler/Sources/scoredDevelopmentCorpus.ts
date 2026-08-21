import { createHash } from "node:crypto";
import { normalize, sep } from "node:path";
import {
  loadScoredSnapshotDirectory,
  type LoadedScoredOffice
} from "./breviariumGregorianum.ts";
import { canonicalVisibleContentDigest, compileCorpus } from "./compiler.ts";
import { developmentCorpusFromSnapshots } from "./developmentCorpus.ts";
import { withResolvedEveningContexts } from "./eveningContext.ts";
import { gabcBody } from "./gabc.ts";
import { parenthesizeLiturgicalDirections } from "./inlineRubrics.ts";
import { requireSameLiturgicalIdentity } from "./liturgicalIdentity.ts";
import {
  curatedOfficePromotions,
  curatedPromotionChecksum
} from "./curatedOfficePromotions.ts";
import { exceptionalMartyrologyReview } from "./exceptionalMartyrology.ts";
import type { CorpusInput, OfficeDocument, OfficeSection } from "./types.ts";

function officeKey(value: { date: string; hour: string }): string {
  return `${value.date}:${value.hour}`;
}

function localDateKey(office: OfficeDocument): string {
  const date = office.date;
  return `${String(date.year).padStart(4, "0")}-${String(date.month).padStart(2, "0")}-${String(date.day).padStart(2, "0")}`;
}

function stableID(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

function withoutLeakedGABCCommentMarker(value: string): string {
  return value
    .replace(/^\s*%\s*/, "")
    // A small run of Easter Nunc dimittis captures leaked the source-book
    // selector into the visible antiphon incipit.
    .replace(/(?:,|\s)\s*Solesmes\s+1961,\s*100%\s*$/i, "");
}

function normalizedText(value: string): string {
  return value
    .replace(/(?:℟|R\/)\.?\s*br\.?/gi, " ")
    .replace(/(?:℣|℟|[VR]\/)\.?/gi, " ")
    .replace(/\bAnt\.?\s*/gi, " ")
    .replace(/[æǽ]/gi, "ae")
    .replace(/œ/gi, "oe")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/j/g, "i")
    .replace(/v/g, "u")
    // Divinum Officium prefixes printed scripture verses with their verse
    // numbers, while the scored sidecar normally omits those numbers.
    .replace(/\b\d+\b/g, " ")
    .replace(/[^\p{Letter}\p{Number}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function paragraphs(value: string): string[] {
  return value
    .split(/\n\s*\n+/)
    .map(paragraph => paragraph.trim())
    .filter(Boolean);
}

interface BilingualTextLookup {
  exact: Map<string, string>;
  compactExact: Map<string, string>;
  paragraphs: Array<{ latin: string; english: string }>;
  directParagraphs: Array<{ latin: string; english: string }>;
}

const sourceBackedCommonEnglish = new Map<string, string>([
  [normalizedText("Benedictio:"), "Blessing:"],
  [normalizedText("Orémus."), "Let us pray."],
  [normalizedText("Gloria adduntur:"), "The Glory be is added:"],
  [normalizedText("Gloria omittitur:"), "The Glory be is omitted:"],
  [
    normalizedText("Evangélica léctio sit nobis salus et protéctio"),
    "Benediction. May the Gospel's holy lection Be our safety and protection."
  ],
  [
    normalizedText("Homilía sancti Gregórii Papæ"),
    "Homily by Pope St. Gregory the Great"
  ],
  [normalizedText("Homilia 2 in Evangelia"), "Homily 2 on the Gospels"],
  [normalizedText("Homilia 8 in Evangelia"), "Homily 8 on the Gospels"],
  [
    normalizedText("secunda 'Domine, exaudi' omittitur"),
    "The second ‘O Lord, hear my prayer’ is omitted."
  ],
  [
    normalizedText("Convérte nos Deus salutáris noster"),
    "℣. Turn us then, ✙ O God, our saviour:"
  ],
  [
    normalizedText("Et avérte iram tuam a nobis"),
    "℟. And let thy anger cease from us."
  ],
  [
    normalizedText(
      "Réquiem ætérnam dono eis Dómine et lux perpétua lúceat eis"
    ),
    "Eternal rest grant unto them, O Lord, and let perpetual light shine upon them."
  ],
  [
    normalizedText("Divínum auxílium máneat semper nobíscum"),
    "Benediction. May the divine assistance remain with us always."
  ],
  [
    normalizedText("Per evangélica dicta deleántur nostra delícta"),
    "Benediction. May the Gospel's glorious word Cleansing to our souls afford."
  ],
  [
    normalizedText("Ignem sui amóris accéndat Deus in córdibus nostris"),
    "Benediction. May the Spirit's fire Divine in our hearts enkindled shine."
  ],
  [
    normalizedText(
      "Ad societátem cívium supernórum perdúcat nos Rex Angelórum"
    ),
    "Benediction. May He that is the Angels' King to that high realm His people bring."
  ],
  [
    normalizedText("Benedicámus Dómino Deo grátias"),
    "℣. Let us bless the Lord.\n\n℟. Thanks be to God."
  ],
  [
    normalizedText(
      "Ego autem mendícus sum et pauper Dóminus sollícitus est mei "
      + "Labóres mánuum tuárum quia manducábis beátus es et bene tibi erit "
      + "Dóminus"
    ),
    "℟. As for me, I am poor and needy:\n\n"
      + "* But the Lord careth for me.\n\n"
      + "℣. Thou shalt eat the labours of thine hands; blessed art thou, "
      + "and happy shalt thou be.\n\n"
      + "℟. But the Lord careth for me."
  ],
  [
    normalizedText(
      "Simus ergo imitatóres Dei Et ambulémus in dilectióne "
      + "Sicut et Christus diléxit nos et trádidit semetípsum pro nobis Et "
      + "Glória Patri et Fílio et Spirítui Sancto Et"
    ),
    "℟. Be ye therefore followers of God;\n\n"
      + "* And walk ye therefore in love.\n\n"
      + "℣. For Christ also hath loved us and hath given himself for us.\n\n"
      + "℟. And walk ye therefore in love.\n\n"
      + "℣. Glory be to the Father, and to the Son, * and to the Holy Ghost.\n\n"
      + "℟. And walk ye therefore in love."
  ],
  [
    normalizedText(
      "Quadragínta dies et noctes apérti sunt cæli et ex omni carne "
      + "habéntem spíritum vitæ ingréssi sunt in arcam Et clausit a foris "
      + "óstium Dóminus In artículo diéi illíus ingréssus est Noë in arcam "
      + "et fílii eius et uxóres filiórum eius Et clausit "
      + "Glória Patri et Fílio et Spirítui Sancto Et clausit"
    ),
    "℟. Forty days and forty nights were the heavens opened; and there "
      + "went into the ark two and two of all flesh wherein is the breath of life.\n\n"
      + "* And the Lord shut them in.\n\n"
      + "℣. In the self-same day entered Noah into the ark, and his sons, "
      + "and his wife, and the wives of his sons.\n\n"
      + "℟. And the Lord shut them in.\n\n"
      + "℣. Glory be to the Father, and to the Son, * and to the Holy Ghost.\n\n"
      + "℟. And the Lord shut them in."
  ],
  [
    normalizedText(
      "Dum iret Iacob de Bersabée et pérgeret Haran locútus est ei Deus "
      + "dicens Terram in qua dormis tibi dabo et sémini tuo Ædificávit "
      + "Iacob ex lapídibus altáre in honórem Dómini fundens óleum désuper "
      + "et benedíxit eum Deus dicens"
    ),
    "℟. While as Jacob went from Beersheba, and hasted unto Haran, the Lord "
      + "spake unto him, saying:\n\n"
      + "* The land whereon thou sleepest, to thee will I give it, and to thy seed.\n\n"
      + "℣. He built an altar of stones unto the Name of the Lord, and poured "
      + "oil upon the top of it; and God blessed him and said:\n\n"
      + "℟. The land whereon thou sleepest, to thee will I give it, and to thy seed."
  ],
  [
    normalizedText("Quæ non repetitur in Psalmo"),
    "It is not repeated in the psalm."
  ]
]);

const compactSourceBackedCommonEnglish = new Map(
  [...sourceBackedCommonEnglish].map(([latin, english]) => [
    latin.replaceAll(" ", ""),
    english
  ])
);

function bilingualTextLookup(sourceSections: OfficeSection[]): BilingualTextLookup {
  const exact = new Map<string, string>();
  const compactExact = new Map<string, string>();
  const aligned: Array<{ latin: string; english: string }> = [];
  const directParagraphs: Array<{ latin: string; english: string }> = [];
  const directKeys = new Set<string>();
  const addAligned = (
    latinValue: string,
    englishValue: string,
    isDirectParagraph = false,
    isContainmentCandidate = true
  ) => {
    const latin = normalizedText(latinValue);
    const english = englishValue.trim();
    if (!latin || !english) return;
    exact.set(latin, english);
    compactExact.set(latin.replaceAll(" ", ""), english);
    if (isContainmentCandidate) aligned.push({ latin, english });
    const directKey = `${latin}\u0000${english}`;
    if (isDirectParagraph && !directKeys.has(directKey)) {
      directParagraphs.push({ latin, english });
      directKeys.add(directKey);
    }
  };
  for (const source of sourceSections) {
    if (!source.english?.trim()) continue;
    // Whole source sections remain valid exact matches, but must not win an
    // incipit containment search and attach an entire lesson wrapper to one
    // chant nested inside it.
    addAligned(source.latin, source.english, false, false);
    const latinParagraphs = paragraphs(source.latin);
    const englishParagraphs = paragraphs(source.english);

    // Preserve obvious bilingual structure even when a source-side line wrap
    // makes the total paragraph counts differ. These anchors recover complete
    // hymns, antiphons, chapter prose, lessons, and their trailing versicles.
    const addOrdinalPairs = (
      latinPredicate: (value: string) => boolean,
      englishPredicate: (value: string) => boolean
    ) => {
      const latinMatches = latinParagraphs.filter(latinPredicate);
      const englishMatches = englishParagraphs.filter(englishPredicate);
      if (latinMatches.length !== englishMatches.length) return;
      for (const [index, latin] of latinMatches.entries()) {
        addAligned(latin, englishMatches[index], true);
      }
    };
    addOrdinalPairs(
      value => /^(?:℣|℟)\./.test(value),
      value => /^(?:℣|℟)\./.test(value)
    );
    addOrdinalPairs(
      value => /^Ant\./i.test(value),
      value => /^Ant\./i.test(value)
    );
    addOrdinalPairs(
      value => /^\*/.test(value),
      value => /^\*/.test(value)
    );
    addOrdinalPairs(
      value => /^In illo témpore\b/i.test(value),
      value => /^(?:In|At) that time\b/i.test(value)
    );

    const latinHymnStart = latinParagraphs.findIndex(value => /^Hymnus$/i.test(value));
    const englishHymnStart = englishParagraphs.findIndex(value => /^Hymn$/i.test(value));
    const latinHymnEnd = latinParagraphs.findIndex(
      (value, index) => index > latinHymnStart && /^Amen\.$/i.test(value)
    );
    const englishAmenIndex = englishParagraphs.findIndex(
      (value, index) => index > englishHymnStart && /^Amen\.$/i.test(value)
    );
    const englishFollowingRole = englishParagraphs.findIndex(
      (value, index) => index > englishHymnStart && /^(?:℣|℟)\./.test(value)
    );
    const englishHymnEnd = englishAmenIndex >= 0
      ? englishAmenIndex + 1
      : englishFollowingRole;
    if (
      latinHymnStart >= 0
      && englishHymnStart >= 0
      && latinHymnEnd > latinHymnStart
      && englishHymnEnd > englishHymnStart + 1
    ) {
      addAligned(
        latinParagraphs.slice(latinHymnStart + 1, latinHymnEnd + 1).join(" "),
        englishParagraphs.slice(englishHymnStart + 1, englishHymnEnd).join("\n\n"),
        true
      );
    }

    const latinTeDeumStart = latinParagraphs.findIndex(value => /^Te Deum$/i.test(value));
    const englishTeDeumStart = englishParagraphs.findIndex(value => /^Te Deum$/i.test(value));
    if (latinTeDeumStart >= 0 && englishTeDeumStart >= 0) {
      addAligned(
        latinParagraphs.slice(latinTeDeumStart + 1).join(" "),
        englishParagraphs.slice(englishTeDeumStart + 1).join("\n\n"),
        true
      );
    }

    const addParagraphsBesideAnchors = (
      latinAnchor: RegExp,
      englishAnchor: RegExp,
      offset: -1 | 1
    ) => {
      const latinAnchors = latinParagraphs
        .map((value, index) => latinAnchor.test(value) ? index : -1)
        .filter(index => index >= 0);
      const englishAnchors = englishParagraphs
        .map((value, index) => englishAnchor.test(value) ? index : -1)
        .filter(index => index >= 0);
      if (latinAnchors.length !== englishAnchors.length) return;
      for (const [index, latinIndex] of latinAnchors.entries()) {
        const englishIndex = englishAnchors[index];
        const latin = latinParagraphs[latinIndex + offset];
        const english = englishParagraphs[englishIndex + offset];
        if (latin && english) addAligned(latin, english, true);
      }
    };
    addParagraphsBesideAnchors(
      /^℟\. Deo grátias\.?$/i,
      /^℟\. Thanks be to God\.?$/i,
      -1
    );
    addParagraphsBesideAnchors(/^Lectio \d+$/i, /^Reading \d+$/i, 1);
    addParagraphsBesideAnchors(
      /^℣\. Tu autem, Dómine/i,
      /^℣\. But thou, O Lord/i,
      -1
    );

    const latinThanks = latinParagraphs
      .map((value, index) => /^℟\. Deo grátias\.?$/i.test(value) ? index : -1)
      .filter(index => index >= 0);
    const englishThanks = englishParagraphs
      .map((value, index) => /^℟\. Thanks be to God\.?$/i.test(value) ? index : -1)
      .filter(index => index >= 0);
    if (latinThanks.length === englishThanks.length) {
      for (const [index, latinStart] of latinThanks.entries()) {
        const englishStart = englishThanks[index];
        const latinEnd = latinParagraphs.findIndex(
          (value, paragraphIndex) => paragraphIndex > latinStart && /^℣\. Iube,/i.test(value)
        );
        const englishEnd = englishParagraphs.findIndex(
          (value, paragraphIndex) => paragraphIndex > englishStart
            && /^℣\. Grant, Lord, a blessing/i.test(value)
        );
        const latinBlock = latinParagraphs.slice(
          latinStart + 1,
          latinEnd >= 0 ? latinEnd : latinParagraphs.length
        );
        const englishBlock = englishParagraphs.slice(
          englishStart + 1,
          englishEnd >= 0 ? englishEnd : englishParagraphs.length
        );
        if (latinBlock.length > 0 && englishBlock.length > 0) {
          addAligned(latinBlock.join(" "), englishBlock.join("\n\n"), true);
        }
      }
    }

    if (latinParagraphs.length === englishParagraphs.length) {
      for (const [index, paragraph] of latinParagraphs.entries()) {
        addAligned(paragraph, englishParagraphs[index], true);

        // The scored reference may combine several adjacent printed lines
        // into one chant occurrence (hymns and Marian antiphons do this
        // frequently).
        for (
          let end = index + 2;
          end <= Math.min(latinParagraphs.length, index + 8);
          end += 1
        ) {
          addAligned(
            latinParagraphs.slice(index, end).join(" "),
            englishParagraphs.slice(index, end).join("\n\n")
          );
        }
      }
      continue;
    }

    // Scripture translations sometimes combine two numbered verses into one
    // English paragraph. Align the unnumbered framing before and after that
    // block, then group Latin verses using the next printed English number as
    // the boundary. This retains the checked-in translation without guessing
    // across languages.
    const numbered = (value: string) => /^\s*(\d+)\s+/.exec(value)?.[1];
    const firstLatinNumber = latinParagraphs.findIndex(numbered);
    const firstEnglishNumber = englishParagraphs.findIndex(numbered);
    if (firstLatinNumber >= 0 && firstEnglishNumber >= 0) {
      const prefixCount = Math.min(firstLatinNumber, firstEnglishNumber);
      for (let index = 0; index < prefixCount; index += 1) {
        addAligned(latinParagraphs[index], englishParagraphs[index], true);
      }

      const latinNumbered = latinParagraphs
        .map((value, index) => ({ value, index, number: Number(numbered(value)) }))
        .filter(item => Number.isFinite(item.number));
      const englishNumbered = englishParagraphs
        .map((value, index) => ({ value, index, number: Number(numbered(value)) }))
        .filter(item => Number.isFinite(item.number));
      for (const [index, english] of englishNumbered.entries()) {
        const nextNumber = englishNumbered[index + 1]?.number ?? Number.POSITIVE_INFINITY;
        const latinGroup = latinNumbered.filter(item =>
          item.number >= english.number && item.number < nextNumber
        );
        if (latinGroup.length > 0) {
          addAligned(
            latinGroup.map(item => item.value).join(" "),
            english.value,
            true
          );
        }
      }

      const lastLatinNumber = latinNumbered.at(-1)!.index;
      const lastEnglishNumber = englishNumbered.at(-1)!.index;
      const latinSuffix = latinParagraphs.slice(lastLatinNumber + 1);
      const englishSuffix = englishParagraphs.slice(lastEnglishNumber + 1);
      const suffixCount = Math.min(latinSuffix.length, englishSuffix.length);
      for (let offset = 1; offset <= suffixCount; offset += 1) {
        addAligned(
          latinSuffix.at(-offset)!,
          englishSuffix.at(-offset)!,
          true
        );
      }
    }
  }
  return { exact, compactExact, paragraphs: aligned, directParagraphs };
}

export function latinLyricsFromGABC(gabc: string): string {
  const body = gabcBody(gabc);
  const groupPattern = /([^()]*)\(([^)]*)\)/g;
  let lyrics = "";
  let match: RegExpExecArray | null;
  while ((match = groupPattern.exec(body)) !== null) {
    lyrics += match[1];
  }
  return lyrics
    .replace(/<[^>]+>/g, "")
    .replace(/[{}]/g, "")
    .replace(/_([^_]+)_/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function occurrenceCount(haystack: string, needle: string): number {
  if (!needle) return 0;
  return (` ${haystack} `).split(` ${needle} `).length - 1;
}

function occurrenceIndex(
  haystack: string,
  needle: string,
  ordinal: number
): number {
  let fromIndex = 0;
  for (let occurrence = 0; occurrence <= ordinal; occurrence += 1) {
    const index = haystack.indexOf(needle, fromIndex);
    if (index < 0) return -1;
    if (occurrence === ordinal) return index;
    fromIndex = index + needle.length;
  }
  return -1;
}

function compactOccurrenceCount(haystack: string, needle: string): number {
  if (!needle) return 0;
  return haystack.split(needle).length - 1;
}

function longestSharedWordRun(left: string[], right: string[]): number {
  let previous = new Array<number>(right.length + 1).fill(0);
  let longest = 0;
  for (const leftWord of left) {
    const current = new Array<number>(right.length + 1).fill(0);
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      if (leftWord !== right[rightIndex - 1]) continue;
      current[rightIndex] = previous[rightIndex - 1] + 1;
      longest = Math.max(longest, current[rightIndex]);
    }
    previous = current;
  }
  return longest;
}

function sharedWordRunPosition(left: string[], right: string[]): number {
  let previous = new Array<number>(right.length + 1).fill(0);
  let longest = 0;
  let leftEnd = -1;
  for (const [leftIndex, leftWord] of left.entries()) {
    const current = new Array<number>(right.length + 1).fill(0);
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      if (leftWord !== right[rightIndex - 1]) continue;
      current[rightIndex] = previous[rightIndex - 1] + 1;
      if (current[rightIndex] > longest) {
        longest = current[rightIndex];
        leftEnd = leftIndex;
      }
    }
    previous = current;
  }
  return leftEnd >= 0 ? leftEnd - longest + 1 : -1;
}

function sharedWordSubsequenceLength(left: string[], right: string[]): number {
  let previous = new Array<number>(right.length + 1).fill(0);
  for (const leftWord of left) {
    const current = new Array<number>(right.length + 1).fill(0);
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      current[rightIndex] = leftWord === right[rightIndex - 1]
        ? previous[rightIndex - 1] + 1
        : Math.max(previous[rightIndex], current[rightIndex - 1]);
    }
    previous = current;
  }
  return previous[right.length];
}

function alignedEnglishForChant(
  section: OfficeSection,
  lookup: BilingualTextLookup
): string | null {
  if (!section.chant) return null;
  const target = normalizedText(latinLyricsFromGABC(section.chant.gabc));
  if (!target) return null;
  const common = sourceBackedCommonEnglish.get(target)
    ?? compactSourceBackedCommonEnglish.get(target.replaceAll(" ", ""));
  if (common) return common;
  const targetWords = target.split(" ");
  const compactTarget = target.replaceAll(" ", "");

  const used = new Map<string, number>();
  const sourceFrequency = new Map<string, number>();
  for (const candidate of lookup.directParagraphs) {
    sourceFrequency.set(
      candidate.latin,
      (sourceFrequency.get(candidate.latin) ?? 0) + 1
    );
  }
  const translations: Array<{
    english: string;
    position: number;
    wordCount: number;
  }> = [];
  for (const candidate of lookup.directParagraphs) {
    const words = candidate.latin.split(" ");
    const compactCandidate = candidate.latin.replaceAll(" ", "");
    let available = Math.max(
      occurrenceCount(target, candidate.latin),
      compactOccurrenceCount(compactTarget, compactCandidate)
    );
    if ((sourceFrequency.get(candidate.latin) ?? 0) > 1 && words.length >= 4) {
      // Printed responsories repeat the complete response while compact GABC
      // commonly abbreviates subsequent repetitions with an ellipsis.
      available = Math.max(
        available,
        occurrenceCount(target, words.slice(0, 2).join(" "))
      );
    }
    if (available === 0 && words.length >= 4) {
      // The two checked-in sources differ occasionally in orthography,
      // punctuation, or one omitted word. Accept a paragraph only when one
      // long run, or an order-preserving match with a small number of source
      // typos, accounts for most of that source paragraph.
      const sharedRun = longestSharedWordRun(targetWords, words);
      const sharedSubsequence = sharedRun >= 4 && sharedRun / words.length >= 0.72
        ? sharedRun
        : sharedWordSubsequenceLength(targetWords, words);
      if (
        (sharedRun >= 4 && sharedRun / words.length >= 0.72)
        || (
          words.length >= 6
          && sharedSubsequence >= 5
          && Math.max(words.length, targetWords.length)
            / Math.min(words.length, targetWords.length) <= 1.6
          && sharedSubsequence
            / Math.min(words.length, targetWords.length) >= 0.8
        )
      ) {
        available = 1;
      }
    }
    const consumed = used.get(candidate.latin) ?? 0;
    if (available <= consumed) continue;
    let characterPosition = occurrenceIndex(target, candidate.latin, consumed);
    if (characterPosition < 0 && words.length >= 2) {
      characterPosition = occurrenceIndex(
        target,
        words.slice(0, 2).join(" "),
        consumed
      );
    }
    let compactPosition = -1;
    if (characterPosition < 0) {
      compactPosition = occurrenceIndex(
        compactTarget,
        compactCandidate,
        consumed
      );
    }
    let position = characterPosition >= 0
      ? target.slice(0, characterPosition).split(" ").filter(Boolean).length
      : compactPosition >= 0
        ? Math.round(compactPosition / compactTarget.length * targetWords.length)
        : -1;
    if (position < 0) {
      position = sharedWordRunPosition(targetWords, words);
    }
    if (position < 0) {
      position = targetWords.length;
    }
    translations.push({
      english: candidate.english,
      position,
      wordCount: words.length
    });
    used.set(candidate.latin, consumed + 1);
  }
  // A complete bilingual paragraph and one or more of its shorter phrases
  // can all match the same score. Keep the complete translation and discard
  // the nested phrase translations; otherwise a scored chapter is rendered
  // as "versicle + chapter + response" even though the phrases are already
  // present in the chapter. Separate responsory phrases still survive when
  // they occupy their own non-overlapping spans.
  const nonNestedTranslations = translations.filter((candidate, index) =>
    !translations.some((covering, coveringIndex) =>
      coveringIndex !== index
      && covering.wordCount > candidate.wordCount
      && covering.position <= candidate.position
      && covering.position + covering.wordCount
        >= candidate.position + candidate.wordCount
    )
  );
  return nonNestedTranslations.length > 0
    ? nonNestedTranslations
      .sort((left, right) => left.position - right.position)
      .map(item => item.english)
      .join("\n\n")
    : null;
}

function englishWordCount(value: string): number {
  return value.split(/\s+/).filter(Boolean).length;
}

function preferredEnglish(
  ordered: string | null | undefined,
  aligned: string | null
): string | null {
  if (!ordered?.trim()) return aligned;
  if (!aligned?.trim()) return ordered.trim();
  return englishWordCount(ordered) > englishWordCount(aligned) * 1.35
    ? ordered.trim()
    : aligned.trim();
}

function translationSectionsFor(
  section: OfficeSection,
  sourceSections: OfficeSection[]
): OfficeSection[] {
  if (section.kind === "psalm") {
    const psalmNumber = /Psalmus\s+(\d+)/i.exec(section.title)?.[1];
    if (psalmNumber) {
      const numbered = sourceSections.filter(source =>
        source.kind === "psalm"
        && new RegExp(`\\bPsalmus\\s+${psalmNumber}\\b`, "i").test(source.latin)
      );
      if (numbered.length > 0) return numbered;
    }
  }

  const title = normalizedText(section.title);
  const titled = sourceSections.filter(source =>
    normalizedText(source.title) === title
  );
  if (titled.length > 0) return titled;
  return sourceSections.filter(source => source.kind === section.kind);
}

function alignedEnglishText(latin: string, lookup: BilingualTextLookup): string | null {
  const target = normalizedText(latin);
  if (!target) return null;
  const common = sourceBackedCommonEnglish.get(target);
  if (common) return common;
  const exact = lookup.exact.get(target);
  if (exact) return exact;
  const compactExact = lookup.compactExact.get(target.replaceAll(" ", ""));
  if (compactExact) return compactExact;

  // Scored sections are often an incipit or a pointed fragment of a complete
  // bilingual paragraph. A same-office containment match is safe when it has
  // at least two words; choose the tightest source paragraph to avoid broad
  // wrappers winning over their actual line.
  if (target.split(" ").length < 2) return null;
  const targetWords = target.split(" ");
  return lookup.paragraphs
    .filter(candidate => {
      if (
        candidate.latin.includes(target)
        || (
          candidate.latin.split(" ").length >= 4
          && target.includes(candidate.latin)
        )
      ) return true;
      const candidateWords = candidate.latin.split(" ");
      if (targetWords.length < 6 || candidateWords.length < 6) return false;
      const shared = sharedWordSubsequenceLength(targetWords, candidateWords);
      return shared / Math.max(targetWords.length, candidateWords.length) >= 0.85;
    })
    .sort((left, right) => {
      const leftDelta = Math.abs(left.latin.length - target.length);
      const rightDelta = Math.abs(right.latin.length - target.length);
      return leftDelta - rightDelta;
    })[0]
    ?.english ?? null;
}

function englishSectionTitle(
  title: string,
  sourceSections: OfficeSection[]
): string | null {
  const target = normalizedText(title);
  const match = sourceSections.find(section =>
    normalizedText(section.title) === target
    && section.titleEnglish?.trim()
    && !/^Section \d+$/i.test(section.titleEnglish)
  );
  return match?.titleEnglish?.trim() ?? null;
}

function englishRubric(
  rubric: string | null | undefined,
  sourceSections: OfficeSection[]
): string | null {
  if (!rubric) return null;
  const target = normalizedText(rubric);
  const match = sourceSections.find(section =>
    section.rubricEnglish?.trim()
    && normalizedText(section.rubric ?? "") === target
  );
  return match?.rubricEnglish?.trim() ?? null;
}

export function sectionsWithBilingualSource(
  sections: OfficeSection[],
  sourceSections: OfficeSection[]
): OfficeSection[] {
  const translationLookup = bilingualTextLookup(sourceSections);
  const chantLookupCache = new Map<string, BilingualTextLookup>();
  return sections.map(section => {
    const aligned = alignedEnglishText(section.latin, translationLookup);
    const chantSources = translationSectionsFor(section, sourceSections);
    const chantLookupKey = chantSources.map(item => item.id).join("\u0000");
    let chantLookup = chantLookupCache.get(chantLookupKey);
    if (!chantLookup) {
      chantLookup = bilingualTextLookup(chantSources);
      chantLookupCache.set(chantLookupKey, chantLookup);
    }
    const specificallyAlignedChant = alignedEnglishForChant(section, chantLookup);
    const generallyAlignedChant = alignedEnglishForChant(
      section,
      translationLookup
    );
    // Some scored Matins responsories inherit the surrounding "Pater" title.
    // A title-scoped lookup can therefore find only a shared Amen, Alleluia,
    // or doxology. Prefer the more complete same-office alignment when it
    // recovers the actual responsory text.
    const chantEnglish = preferredEnglish(
      specificallyAlignedChant,
      generallyAlignedChant
    );
    const preferredChantEnglish = section.chant
      ? preferredEnglish(section.english, chantEnglish)
      : null;
    return {
      ...section,
      titleEnglish: section.titleEnglish
        ?? englishSectionTitle(section.title, sourceSections),
      rubricEnglish: section.rubricEnglish
        ?? englishRubric(section.rubric, sourceSections),
      english: preferredChantEnglish
        ?? preferredEnglish(section.english, aligned)
    };
  });
}

function assertCalendarConcordance(
  office: OfficeDocument,
  source: LoadedScoredOffice
): string {
  const identity = requireSameLiturgicalIdentity(
    office.contextLabel,
    source.observance.titleLatin,
    `Calendar disagreement for ${source.date}:${source.hour}`
  );
  const divinumRank = office.observance?.rank ?? null;
  const referenceRank = source.observance.rank ?? null;
  if (divinumRank !== referenceRank) {
    throw new Error(
      `Rank disagreement for ${source.date}:${source.hour}: `
      + `${divinumRank} versus ${referenceRank}`
    );
  }
  return identity;
}

export function officeWithScoredReference(
  office: OfficeDocument,
  source: LoadedScoredOffice
): OfficeDocument {
  if (!source.orderedSections) {
    throw new Error(
      `Scored snapshot ${source.date}:${source.hour} has no ordered sidecar; recapture it`
    );
  }
  const observanceIdentity = assertCalendarConcordance(office, source);
  const sourceVisibleContentDigest = canonicalVisibleContentDigest(
    source.orderedSections
  );
  if (
    !source.visibleContentDigest
    || source.visibleContentDigest !== sourceVisibleContentDigest
  ) {
    throw new Error(
      `Visible-content golden mismatch for ${source.date}:${source.hour}`
    );
  }
  const orderedSections = source.orderedSections.map((ordered, index) => {
    const {
      sourceOffset: _sourceOffset,
      sourceRole,
      ...section
    } = ordered;
    if (sourceRole !== "chant" || !section.chant) {
      return {
        ...section,
        latin: parenthesizeLiturgicalDirections(section.latin),
        english: section.english
          ? parenthesizeLiturgicalDirections(section.english)
          : section.english,
        id: `${source.hour}-ordered-${index}`
      };
    }
    return {
      ...section,
      latin: parenthesizeLiturgicalDirections(
        withoutLeakedGABCCommentMarker(section.latin)
      ),
      english: section.english
        ? parenthesizeLiturgicalDirections(section.english)
        : section.english,
      chant: {
        ...section.chant,
        incipit: withoutLeakedGABCCommentMarker(section.chant.incipit)
      },
      id: `${source.hour}-ordered-${index}`
    };
  }).filter(section => section.latin !== "Special Oratio mortuorum");
  const sections = sectionsWithBilingualSource(orderedSections, office.sections);
  const visibleContentDigest = canonicalVisibleContentDigest(sections);
  return {
    ...office,
    contextLabel: source.observance.titleLatin,
    format: "authoritativeOrdered",
    visibleContentDigest,
    observance: {
      observanceID:
        `breviarium-gregorianum/${observanceIdentity}`,
      titleLatin: source.observance.titleLatin,
      titleEnglish: source.observance.titleEnglish,
      rank: source.observance.rank,
      color: null,
      season: office.observance?.season,
      eveningContext: source.observance.eveningContext,
      commemorations: source.observance.commemorations.map(commemoration => ({
        id:
          "breviarium-gregorianum/commemoration/"
          + stableID(commemoration.titleLatin),
        ...commemoration
      }))
    },
    sections
  };
}

function scoreCounts(offices: OfficeDocument[]): { unresolved: number; ambiguous: number } {
  const scores = offices.flatMap(office =>
    office.sections.flatMap(section => section.chant ? [section.chant] : [])
  );
  return {
    unresolved: scores.filter(score =>
      score.reviewStatus === "ambiguous" || score.reviewStatus === "missing"
    ).length,
    ambiguous: scores.filter(score => score.reviewStatus === "ambiguous").length
  };
}

function scoredSnapshotChecksum(
  scored: LoadedScoredOffice[],
  missingOfficeKeys: string[]
): string {
  return createHash("sha256")
    .update(scored.map(record =>
      `${record.sha256}:${record.scoresSHA256 ?? "legacy-inline"}:`
      + `${record.orderedSHA256 ?? "legacy-unordered"}:`
      + `${record.visibleContentDigest ?? "legacy-undigested"}:`
      + `${record.orderedParserVersion ?? "legacy-parser"}`
    ).join("\n"))
    .update(`\nmissing:${missingOfficeKeys.slice().sort().join(",")}`)
    .digest("hex");
}

export function authoritativeOfficesOnly(
  offices: OfficeDocument[],
  authoritativeByOffice: ReadonlyMap<string, OfficeDocument>
): OfficeDocument[] {
  return offices.flatMap(office => {
    const authoritative = authoritativeByOffice.get(
      `${localDateKey(office)}:${office.hour}`
    );
    return authoritative ? [authoritative] : [];
  });
}

export function officesWithUnavailablePlaceholders(
  offices: OfficeDocument[],
  authoritativeByOffice: ReadonlyMap<string, OfficeDocument>
): OfficeDocument[] {
  return offices.map(office => {
    const authoritative = authoritativeByOffice.get(
      `${localDateKey(office)}:${office.hour}`
    );
    if (authoritative) return authoritative;
    return {
      ...office,
      format: "contentUnavailable",
      visibleContentDigest: null,
      observance: office.observance ?? {
        observanceID:
          `unavailable/${localDateKey(office)}/${stableID(office.contextLabel)}`,
        titleLatin: office.contextLabel,
        titleEnglish: null,
        rank: null,
        color: null,
        season: null,
        eveningContext: null,
        commemorations: []
      },
      sections: []
    };
  });
}

export function scoredDevelopmentCorpusFromSnapshots(options: {
  divinumSnapshots: string;
  scoredSnapshots: string;
  requireComplete?: boolean;
}): CorpusInput {
  const corpus = developmentCorpusFromSnapshots({
    snapshots: options.divinumSnapshots
  });
  const scored = loadScoredSnapshotDirectory(options.scoredSnapshots);
  const byOffice = new Map(scored.map(record => [officeKey(record), record]));
  const curated = curatedOfficePromotions(
    corpus.offices,
    scored,
    (sections, office) => sectionsWithBilingualSource(sections, office.sections)
  );
  const missing = corpus.offices
    .map(office => `${localDateKey(office)}:${office.hour}`)
    .filter(key => !byOffice.has(key));
  const unpromotedMissing = missing.filter(key => !curated.has(key));
  const empty = scored.filter(record => record.scores.length === 0);
  const unordered = scored.filter(record => !record.orderedSections);
  if (
    (options.requireComplete ?? true)
    && (unpromotedMissing.length > 0 || empty.length > 0 || unordered.length > 0)
  ) {
    const first = unpromotedMissing[0]
      ?? `${empty[0]?.date ?? unordered[0].date}:${empty[0]?.hour ?? unordered[0].hour}`;
    throw new Error(
      `Scored coverage is incomplete: ${unpromotedMissing.length} unpromoted missing pages and `
      + `${empty.length} zero-score offices and ${unordered.length} unordered offices; `
      + `first gap ${first}`
    );
  }

  const authoritativeByOffice = new Map<string, OfficeDocument>(curated);
  const concordanceIssues: string[] = [];
  for (const office of corpus.offices) {
    const key = `${localDateKey(office)}:${office.hour}`;
    const source = byOffice.get(key);
    if (!source) continue;
    try {
      authoritativeByOffice.set(key, officeWithScoredReference(office, source));
    } catch (error) {
      concordanceIssues.push(
        error instanceof Error ? error.message : `${key}: ${String(error)}`
      );
    }
  }
  if (concordanceIssues.length > 0) {
    const detail = concordanceIssues.slice(0, 25).join("\n- ");
    const remainder = concordanceIssues.length > 25
      ? `\n- …and ${concordanceIssues.length - 25} more`
      : "";
    throw new Error(
      `Calendar/content concordance failed for ${concordanceIssues.length} offices:\n`
      + `- ${detail}${remainder}`
    );
  }
  // A missing ordered reference is represented by metadata-only content. It
  // must never inherit the legacy Divinum prayer sections.
  const offices = officesWithUnavailablePlaceholders(
    corpus.offices,
    authoritativeByOffice
  );
  const counts = scoreCounts(offices);
  const sections: OfficeSection[] = offices.flatMap(office => office.sections);
  if (sections.every(section => !section.chant)) {
    throw new Error("Scored development corpus contains no chant");
  }
  const officesByKey = new Map(
    offices.map(office => [`${localDateKey(office)}:${office.hour}`, office])
  );
  const days = corpus.days.map(day => {
    const date = `${String(day.date.year).padStart(4, "0")}-`
      + `${String(day.date.month).padStart(2, "0")}-`
      + String(day.date.day).padStart(2, "0");
    const daytime = officesByKey.get(`${date}:matins`)?.observance
      ?? officesByKey.get(`${date}:lauds`)?.observance;
    const evening = officesByKey.get(`${date}:vespers`)?.observance;
    if (!daytime) {
      throw new Error(`No authoritative daytime observance metadata for ${date}`);
    }
    return {
      ...day,
      observanceID: daytime.observanceID,
      titleLatin: daytime.titleLatin,
      titleEnglish: daytime.titleEnglish,
      rank: daytime.rank,
      color: daytime.color,
      season: daytime.season ?? day.season,
      eveningContext: evening?.eveningContext,
      commemorations: daytime.commemorations
    };
  });
  return withResolvedEveningContexts({
    ...corpus,
    manifest: {
      ...corpus.manifest,
      corpusVersion: `${corpus.manifest.corpusVersion}-scored-reference`,
      sources: [
        ...corpus.manifest.sources,
        {
          name: "Breviarium Gregorianum concordance",
          revision: "snapshot",
          license: "reference-only; score licenses are recorded per chant",
          url: "https://breviariumgregorianum.com/about.php",
          checksum: scoredSnapshotChecksum(scored, missing)
        },
        ...(curated.size > 0 ? [{
          name: "Curated 2026 source-gap promotions",
          revision: "easter-octave-and-martyrology-v1",
          license: "development assembly; payload licenses recorded per source",
          url: "Docs/MISSING_OFFICE_SOURCES.md",
          checksum: curatedPromotionChecksum()
        }, {
          name: "The Roman Martyrology, revised English edition (1916)",
          revision: "1916-revised-edition",
          license: "Public domain",
          url: "https://archive.org/details/romanmartyrology00cathuoft",
          checksum: "688cfa7b85d8a686a4fde9877cfa133550fef8fce8cf46c6c433abf88983042d",
          notice: "Wording base transcribed from the scan; OCR used only as a locator.",
          modifications: "Revised against the 1956 Latin and official 1960 variations."
        }, {
          name: "Exceptional Martyrology English review matrix",
          revision: exceptionalMartyrologyReview().matrix.approval.status,
          license: "GPL-3.0-only",
          url: "Tools/ContentCompiler/Fixtures/martyrology-exceptional-review.json",
          checksum: exceptionalMartyrologyReview().checksum,
          notice: "Release compilation requires recorded human approval.",
          correspondingSource: "https://github.com/MCMXMCM/hours"
        }] : [])
      ],
      coverage: {
        ...corpus.manifest.coverage,
        generatedOfficeCount: offices.length,
        authoritativeOfficeCount:
          offices.filter(office => office.format === "authoritativeOrdered").length,
        unresolvedScoreCount: counts.unresolved,
        ambiguousScoreCount: counts.ambiguous
      }
    },
    days,
    offices
  });
}

export function compileScoredDevelopmentSnapshots(options: {
  divinumSnapshots: string;
  scoredSnapshots: string;
  output: string;
  requireComplete?: boolean;
  allowBundledDevelopmentOutput?: boolean;
}): string[] {
  const bundledSuffix = ["HoursApp", "Resources", "base-office.sqlite"].join(sep);
  if (
    normalize(options.output).endsWith(bundledSuffix)
    && !options.allowBundledDevelopmentOutput
  ) {
    throw new Error(
      "The scored reference corpus includes GPL/reference material; pass "
      + "--allow-reference-bundle only for an explicitly development-only test bundle"
    );
  }
  const corpus = scoredDevelopmentCorpusFromSnapshots(options);
  return compileCorpus(corpus, options.output, true);
}
