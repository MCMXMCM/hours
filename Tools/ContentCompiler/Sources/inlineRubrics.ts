const liturgicalDirectionPatterns: RegExp[] = [
  /during the following verse,? by local custom,? all make a profound bow\.?/gi,
  /during the following verse all make a profound bow:?/gi,
  /the first verse of the following hymn is said genuflecting\.?/gi,
  /kneel for the following verse/gi,
  /strikes his breast/gi,
  /all kneel down/gi,
  /bow head/gi,
  /prima stropha (?:hymni )?sequentis dicitur flex(?:is|ibus) genibus\.?/gi,
  /sequens versus dicitur flexis genibus/gi,
  /fit reverentia(?:, secundum consuetudinem)?(?::)?/gi,
  /percutit sibi pectus/gi,
  /quod sequitur, legitur in tono lectionis consueto; et surgunt omnes\.?/gi
];

function parenthesizedAt(value: string, offset: number, length: number): boolean {
  const before = value.slice(0, offset).trimEnd().at(-1);
  const after = value.slice(offset + length).trimStart().at(0);
  return before === "(" && after === ")";
}

function insideParenthesesAt(value: string, offset: number): boolean {
  let depth = 0;
  for (const character of value.slice(0, offset)) {
    if (character === "(") depth += 1;
    if (character === ")") depth = Math.max(0, depth - 1);
  }
  return depth > 0;
}

/**
 * The upstream Office sources mark short ceremonial directions with inline
 * typography. The native corpus currently stores plain text, so retain the
 * spoken-text boundary with parentheses instead of silently flattening the
 * direction into the prayer.
 */
export function parenthesizeLiturgicalDirections(value: string): string {
  let result = value;
  for (const pattern of liturgicalDirectionPatterns) {
    result = result.replace(pattern, (match, offset: number, input: string) =>
      parenthesizedAt(input, offset, match.length)
        || insideParenthesesAt(input, offset)
        ? match
        : `(${match})`
    );
  }
  return result;
}
