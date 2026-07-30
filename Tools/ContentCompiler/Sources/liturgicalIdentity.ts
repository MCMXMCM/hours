export function canonicalLiturgicalIdentity(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/æ/giu, "ae")
    .replace(/œ/giu, "oe")
    .toLowerCase()
    .replace(/j/g, "i")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

export function requireSameLiturgicalIdentity(
  left: string,
  right: string,
  label: string
): string {
  const leftIdentity = canonicalLiturgicalIdentity(left);
  const rightIdentity = canonicalLiturgicalIdentity(right);
  if (!leftIdentity || !rightIdentity || leftIdentity !== rightIdentity) {
    throw new Error(
      `${label} differs exactly after canonical normalization: `
      + `"${left}" (${leftIdentity || "empty"}) versus `
      + `"${right}" (${rightIdentity || "empty"})`
    );
  }
  return leftIdentity.replace(/ /g, "-");
}
