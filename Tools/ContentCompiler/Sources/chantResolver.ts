export interface ChantCandidate {
  id: string;
  latin: string;
  incipit: string;
  officePart: string;
  mode?: string | null;
  source: string;
}

export interface ChantQuery {
  sectionID: string;
  latin: string;
  incipit: string;
  officePart: string;
  mode?: string | null;
  preferredSources: string[];
}

export type ChantResolution =
  | { status: "exact"; candidate: ChantCandidate }
  | { status: "override"; candidate: ChantCandidate }
  | { status: "missing"; reason: string }
  | { status: "ambiguous"; candidateIDs: string[] };

export function normalizeLatin(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/[æœ]/gi, match => match.toLowerCase() === "æ" ? "ae" : "oe")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .toLowerCase();
}

export function resolveChant(
  query: ChantQuery,
  candidates: ChantCandidate[],
  curatedOverrides: Record<string, string>
): ChantResolution {
  const overrideID = curatedOverrides[query.sectionID];
  if (overrideID) {
    const candidate = candidates.find(item => item.id === overrideID);
    if (!candidate) return { status: "missing", reason: `Override ${overrideID} does not exist` };
    return { status: "override", candidate };
  }

  const fullLatin = normalizeLatin(query.latin);
  const incipit = normalizeLatin(query.incipit);
  let matches = candidates.filter(candidate =>
    normalizeLatin(candidate.latin) === fullLatin
    && normalizeLatin(candidate.officePart) === normalizeLatin(query.officePart)
  );
  if (query.mode) {
    const modeMatches = matches.filter(candidate => candidate.mode === query.mode);
    if (modeMatches.length > 0) matches = modeMatches;
  }
  if (matches.length === 0) {
    matches = candidates.filter(candidate =>
      normalizeLatin(candidate.incipit) === incipit
      && normalizeLatin(candidate.officePart) === normalizeLatin(query.officePart)
    );
  }
  if (matches.length === 0) return { status: "missing", reason: "No exact Latin or incipit match" };

  matches.sort((left, right) => {
    const leftIndex = query.preferredSources.indexOf(left.source);
    const rightIndex = query.preferredSources.indexOf(right.source);
    const leftRank = leftIndex < 0 ? Number.MAX_SAFE_INTEGER : leftIndex;
    const rightRank = rightIndex < 0 ? Number.MAX_SAFE_INTEGER : rightIndex;
    return leftRank - rightRank || left.id.localeCompare(right.id);
  });
  const bestRank = query.preferredSources.indexOf(matches[0].source);
  const equallyPreferred = matches.filter(candidate =>
    query.preferredSources.indexOf(candidate.source) === bestRank
  );
  if (equallyPreferred.length > 1) {
    return { status: "ambiguous", candidateIDs: equallyPreferred.map(candidate => candidate.id) };
  }
  return { status: "exact", candidate: matches[0] };
}
