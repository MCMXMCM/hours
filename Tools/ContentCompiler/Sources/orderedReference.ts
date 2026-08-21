import { parse, type DefaultTreeAdapterTypes } from "parse5";
import {
  officeSectionsFromScoredReference,
  parsePositionedScoredReference,
  type ParseScoredReferenceOptions,
  type ScoredReference
} from "./scoredReference.ts";
import type {
  EveningContext,
  LiturgicalRank,
  OfficeHour,
  OfficeSection
} from "./types.ts";

type Node = DefaultTreeAdapterTypes.Node;
type ParentNode = DefaultTreeAdapterTypes.ParentNode;
type Element = DefaultTreeAdapterTypes.Element;

export type OrderedReferenceRole = "chant" | "prose" | "rubric";

export interface OrderedReferenceSection extends OfficeSection {
  sourceOffset: number;
  sourceRole: OrderedReferenceRole;
}

export interface OrderedReferenceOffice {
  sections: OrderedReferenceSection[];
  sourceSectionCount: number;
  scoreCount: number;
}

export interface ReferenceObservanceMetadata {
  titleLatin: string;
  titleEnglish?: string | null;
  rank?: LiturgicalRank | null;
  eveningContext?: EveningContext | null;
  commemorations: Array<{ titleLatin: string; titleEnglish?: string | null }>;
}

function isElement(node: Node): node is Element {
  return "tagName" in node;
}

function childElements(node: ParentNode): Element[] {
  return node.childNodes.filter(isElement);
}

function descendants(node: ParentNode): Element[] {
  const result: Element[] = [];
  const visit = (parent: ParentNode): void => {
    for (const child of childElements(parent)) {
      result.push(child);
      visit(child);
    }
  };
  visit(node);
  return result;
}

function attribute(element: Element, name: string): string | undefined {
  return element.attrs.find(candidate => candidate.name === name)?.value;
}

function classes(element: Element): Set<string> {
  return new Set((attribute(element, "class") ?? "").split(/\s+/).filter(Boolean));
}

function sourceOffset(element: Element): number {
  const offset = element.sourceCodeLocation?.startOffset;
  if (offset === undefined) {
    throw new Error(`Ordered reference node <${element.tagName}> has no source position`);
  }
  return offset;
}

function textWithBreaks(node: Node): string {
  if ("value" in node) return node.value;
  if (!("childNodes" in node)) return "";
  if (isElement(node)) {
    if (node.tagName === "br") return "\n";
    if (node.tagName === "script" || node.tagName === "style") return "";
  }
  return node.childNodes.map(textWithBreaks).join("");
}

function visibleText(node: Node): string {
  return textWithBreaks(node)
    .replace(/[\t\f\v ]+/g, " ")
    .replace(/ *\r?\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function parsedRank(value: string): LiturgicalRank | null {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (/^I\.\s*classis$/i.test(normalized)) return "firstClass";
  if (/^II\.\s*classis$/i.test(normalized)) return "secondClass";
  if (/^III\.\s*classis$/i.test(normalized)) return "thirdClass";
  if (/^IV\.\s*classis$/i.test(normalized)) return "fourthClass";
  return null;
}

function englishObservanceTitle(documentTitle: string): string | null {
  const title = documentTitle
    .replace(/\s*-\s*Breviarium Gregorianum\s*$/i, "")
    .trim();
  const withoutHour = title.replace(
    /^(?:Matins|Lauds|Prime|Terce|Sext|None|Vespers|Compline)(?:\s+(?:of|for))?\s*/i,
    ""
  ).trim();
  return withoutHour || null;
}

export function parseReferenceObservance(
  html: string,
  hour: OfficeHour
): ReferenceObservanceMetadata {
  const document = parse(html);
  const elements = descendants(document);
  const heading = elements.find(element => element.tagName === "h1");
  const normalizedTitle = heading ? visibleText(heading) : "";
  if (!normalizedTitle) {
    throw new Error("Reference page has no observance heading");
  }

  const rankText = elements.find(element =>
    element.tagName === "p" && classes(element).has("classis")
  );
  const rank = rankText ? parsedRank(visibleText(rankText)) : null;
  if (rankText && !rank) {
    throw new Error(`Reference page has unknown rank "${visibleText(rankText)}"`);
  }

  const subtitle = elements
    .filter(element => element.tagName === "p" && classes(element).has("subtitle"))
    .map(visibleText)
    .join("\n");
  let eveningContext: EveningContext | null = null;
  if (hour === "vespers") {
    if (/Vespera\s+de\s+sequenti/i.test(subtitle)) {
      eveningContext = "firstVespers";
    } else if (/Vespera\s+de\s+pr(?:ae|æ)cedenti/i.test(subtitle)) {
      eveningContext = "secondVespers";
    }
  }

  const commemorations = elements
    .filter(element =>
      /^h[2-6]$/.test(element.tagName)
      && /^Commemoratio\b/i.test(visibleText(element))
    )
    .map(element => visibleText(element).replace(/^Commemoratio\s*/i, "").trim())
    .filter(Boolean)
    .filter((value, index, values) => values.indexOf(value) === index)
    .map(title => ({ titleLatin: title, titleEnglish: null }));

  const pageTitle = elements.find(element => element.tagName === "title");
  return {
    titleLatin: normalizedTitle,
    titleEnglish: pageTitle ? englishObservanceTitle(visibleText(pageTitle)) : null,
    rank,
    eveningContext,
    commemorations
  };
}

function contentSections(document: ParentNode): Element[] {
  const result: Element[] = [];
  const visit = (node: ParentNode): void => {
    for (const child of childElements(node)) {
      if (classes(child).has("section")) {
        const hasDirectContent = child.childNodes.some(candidate => {
          if (!isElement(candidate)) return visibleText(candidate).length > 0;
          return !classes(candidate).has("section")
            && candidate.tagName !== "script"
            && candidate.tagName !== "style";
        });
        if (hasDirectContent) result.push(child);
      }
      visit(child);
    }
  };
  visit(document);
  return result;
}

function headingKind(heading: string): string {
  const value = heading.toLowerCase();
  if (/invitator/.test(value)) return "invitatory";
  if (/absolut/.test(value)) return "absolution";
  if (/benedict|blessing/.test(value)) return "blessing";
  if (/psalm/.test(value)) return "psalm";
  if (/hymn/.test(value)) return "hymn";
  if (/cant/.test(value)) return "canticle";
  if (/responsor/.test(value)) return "responsory";
  if (/antiphon/.test(value)) return "antiphon";
  if (/capit|chapter/.test(value)) return "chapter";
  if (/lectio|reading|lesson|homil/.test(value)) return "reading";
  if (/orat|collect/.test(value)) return "collect";
  return "prayer";
}

function numberedLatin(element: Element, ordinal: number): string {
  const text = visibleText(element);
  return text ? `${ordinal}. ${text}` : "";
}

function isTranslation(element: Element): boolean {
  return classes(element).has("tr");
}

function isGeneratedFrame(element: Element): boolean {
  if (element.tagName !== "iframe") return false;
  const source = attribute(element, "src");
  if (!source) return false;
  let url: URL;
  try {
    url = new URL(source, "https://breviariumgregorianum.com/");
  } catch {
    return false;
  }
  return /\/(?:lesson_ordinary_tone|readings)\/readings\.html$/i.test(url.pathname)
    || /\/tones-api\/readings\/readings\.html$/i.test(url.pathname);
}

export function parseOrderedReferenceOffice(
  html: string,
  options: ParseScoredReferenceOptions = {}
): OrderedReferenceOffice {
  const document = parse(html, { sourceCodeLocationInfo: true });
  const sourceSections = contentSections(document);
  if (sourceSections.length === 0) {
    throw new Error("Ordered reference contains no office sections");
  }

  const positionedScores = parsePositionedScoredReference(html, options);
  const scoreByOffset = new Map<number, ScoredReference>();
  for (const positioned of positionedScores) {
    if (scoreByOffset.has(positioned.anchorPosition)) {
      throw new Error(
        `Ordered reference has multiple scores anchored at byte ${positioned.anchorPosition}`
      );
    }
    scoreByOffset.set(positioned.anchorPosition, positioned.score);
  }

  const consumedScores = new Set<number>();
  const sections: OrderedReferenceSection[] = [];
  let heading = "Office";
  let lastTranslatableIndex: number | undefined;

  const appendProse = (
    latin: string,
    offset: number,
    english?: string
  ): void => {
    const normalized = latin.trim();
    if (!normalized) return;
    const index = sections.length;
    sections.push({
      id: `ordered-reference-${index}`,
      kind: headingKind(heading),
      title: heading,
      latin: normalized,
      english: english?.trim() || null,
      rubric: null,
      chant: null,
      sourceOffset: offset,
      sourceRole: "prose"
    });
    lastTranslatableIndex = index;
  };

  const appendRubric = (latin: string, offset: number): void => {
    const normalized = latin.trim();
    if (!normalized) return;
    const index = sections.length;
    sections.push({
      id: `ordered-reference-${index}`,
      kind: "rubric",
      title: heading,
      latin: normalized,
      english: null,
      rubric: null,
      chant: null,
      sourceOffset: offset,
      sourceRole: "rubric"
    });
    lastTranslatableIndex = undefined;
  };

  const appendScore = (score: ScoredReference, offset: number): void => {
    const index = sections.length;
    const [section] = officeSectionsFromScoredReference(
      [score],
      `ordered-reference-${index}`
    );
    sections.push({
      ...section,
      id: `ordered-reference-${index}`,
      title: heading,
      sourceOffset: offset,
      sourceRole: "chant"
    });
    lastTranslatableIndex = index;
  };

  const attachTranslation = (english: string, offset: number): void => {
    const normalized = english.trim();
    if (!normalized) return;
    if (lastTranslatableIndex === undefined) {
      throw new Error(
        `Translation at byte ${offset} has no adjacent Latin or chant block`
      );
    }
    const target = sections[lastTranslatableIndex];
    if (target.english) {
      throw new Error(
        `Block at byte ${target.sourceOffset} has more than one translation`
      );
    }
    target.english = normalized;
    lastTranslatableIndex = undefined;
  };

  const visitOrderedList = (list: Element): void => {
    let ordinal = Number.parseInt(attribute(list, "start") ?? "1", 10);
    if (!Number.isFinite(ordinal)) ordinal = 1;
    for (const child of childElements(list)) {
      if (child.tagName === "li") {
        appendProse(numberedLatin(child, ordinal), sourceOffset(child));
        ordinal += 1;
        continue;
      }
      if (child.tagName === "p" && isTranslation(child)) {
        attachTranslation(visibleText(child), sourceOffset(child));
        continue;
      }
      const text = visibleText(child);
      if (text) {
        throw new Error(
          `Unsupported <${child.tagName}> in translated list at byte ${sourceOffset(child)}`
        );
      }
    }
  };

  const visitReadingText = (container: Element): void => {
    let segment = "";
    let segmentOffset = sourceOffset(container);
    const flush = (): void => {
      const text = segment
        .replace(/\s+/g, " ")
        .trim();
      if (text) appendProse(text, segmentOffset);
      segment = "";
    };

    for (const child of container.childNodes) {
      if (
        isElement(child)
        && child.sourceCodeLocation
        && scoreByOffset.has(sourceOffset(child))
      ) {
        flush();
        visit(child);
        continue;
      }
      if (isElement(child) && child.tagName === "p") {
        flush();
        visit(child);
        continue;
      }
      if (isElement(child) && child.tagName === "br") {
        flush();
        continue;
      }
      if (!segment) {
        segmentOffset = child.sourceCodeLocation?.startOffset
          ?? sourceOffset(container);
      }
      segment += textWithBreaks(child);
    }
    flush();
  };

  const visitChildren = (
    container: ParentNode,
    skipNestedSections = false
  ): void => {
    let directText = "";
    let directTextOffset = sourceOffset(container as Element);
    const flush = (): void => {
      const normalized = directText
        .replace(/[\t\f\v ]+/g, " ")
        .replace(/ *\r?\n */g, "\n")
        .replace(/\n{3,}/g, "\n\n")
        .trim();
      if (normalized) appendProse(normalized, directTextOffset);
      directText = "";
    };
    for (const child of container.childNodes) {
      if (isElement(child)) {
        if (skipNestedSections && classes(child).has("section")) {
          flush();
          return;
        }
        if (child.tagName === "br") {
          directText += "\n";
          continue;
        }
        flush();
        visit(child);
      } else {
        if (!directText) {
          directTextOffset = child.sourceCodeLocation?.startOffset
            ?? sourceOffset(container as Element);
        }
        directText += textWithBreaks(child);
      }
    }
    flush();
  };

  const visit = (element: Element): void => {
    if (!element.sourceCodeLocation && !visibleText(element)) {
      // parse5 may synthesize empty recovery nodes for malformed upstream
      // paragraph markup. They have no source occurrence and no content.
      return;
    }
    const offset = sourceOffset(element);
    const anchoredScore = scoreByOffset.get(offset);
    if (anchoredScore) {
      appendScore(anchoredScore, offset);
      consumedScores.add(offset);
      return;
    }

    if (/^h[1-6]$/.test(element.tagName)) {
      const text = visibleText(element);
      if (text) heading = text;
      lastTranslatableIndex = undefined;
      return;
    }

    if (element.tagName === "script" || element.tagName === "style") return;
    if (
      element.tagName === "br"
      || element.tagName === "hr"
      || element.tagName === "button"
      || element.tagName === "audio"
    ) {
      return;
    }

    if (element.tagName === "iframe") {
      const label = isGeneratedFrame(element) ? "generated chant" : "unknown content";
      throw new Error(
        `Unconsumed ${label} frame at byte ${offset}; web content cannot enter the native corpus`
      );
    }

    const elementClasses = classes(element);
    if (elementClasses.has("chant-btn-row")) return;

    if (elementClasses.has("reading_text")) {
      visitReadingText(element);
      return;
    }

    if (element.tagName === "ol" || element.tagName === "ul") {
      visitOrderedList(element);
      return;
    }

    if (element.tagName === "p") {
      if (isTranslation(element)) {
        attachTranslation(visibleText(element), offset);
      } else {
        appendProse(visibleText(element), offset);
      }
      return;
    }

    if (
      element.tagName === "span"
      && (
        elementClasses.has("rubrics")
        || elementClasses.has("red")
        || elementClasses.has("reading_id")
      )
    ) {
      appendRubric(visibleText(element), offset);
      return;
    }
    if (element.tagName === "span" && childElements(element).length === 0) {
      // Matins uses an unclassed direct span for lesson source titles.
      // Inline spans are consumed with their parent paragraph and never visit
      // this branch.
      appendRubric(visibleText(element), offset);
      return;
    }

    const children = childElements(element);
    if (children.length > 0) {
      visitChildren(element);
      return;
    }

    const text = visibleText(element);
    if (text) {
      throw new Error(
        `Unsupported visible <${element.tagName}> at byte ${offset}: ${text.slice(0, 80)}`
      );
    }
  };

  for (const sourceSection of sourceSections) {
    visitChildren(sourceSection, true);
  }

  if (consumedScores.size !== positionedScores.length) {
    const unresolved = positionedScores
      .filter(score => !consumedScores.has(score.anchorPosition))
      .map(score => score.anchorPosition);
    throw new Error(
      `Ordered reference left ${unresolved.length} score anchors unconsumed`
      + `; first at byte ${unresolved[0]}`
    );
  }
  if (sections.length === 0) {
    throw new Error("Ordered reference produced no native office blocks");
  }

  return {
    sections,
    sourceSectionCount: sourceSections.length,
    scoreCount: positionedScores.length
  };
}
