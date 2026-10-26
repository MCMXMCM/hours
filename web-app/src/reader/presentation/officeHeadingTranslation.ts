// The English of the headings the Roman 1960 edition prints in Latin alone,
// for a reader that shows the English: the web counterpart of
// `OfficeHeadingTranslation` in `HoursApp/OfficeTextWithoutChant.swift`.

const named: Readonly<Record<string, string>> = {
  Absolutio: "Absolution",
  "Antiphona finalis B.M.V.": "Final Antiphon of the Blessed Virgin Mary",
  Benedictio: "Blessing",
  Capitulum: "Chapter",
  "Capitulum Hymnus Versus": "Chapter Hymn Verse",
  "Capitulum Responsorium Versus": "Chapter Responsory Verse",
  Conclusio: "Conclusion",
  Hymnus: "Hymn",
  Incipit: "Beginning",
  Invitatorium: "Invitatory",
  "Lectio brevis": "Short reading",
  Martyrologium: "Martyrology",
  Oratio: "Prayer",
  Pater: "Our Father",
  "Prex poenitentialis": "Penitential Prayer",
  Psalmi: "Psalms",
  "Psalmi cum lectionibus": "Psalms with lections",
  Psalmus: "Psalm",
  "Te Deum": "Te Deum",
  Versus: "Versicle",
};

/** The Gospel canticles, by the names the 1954 edition gives them. */
const canticles: Readonly<Record<string, string>> = {
  "B. Mariæ Virginis": "Canticle: Magnificat",
  Zachariæ: "Canticle: Benedictus",
  Simeonis: "Canticle: Nunc dimittis",
  Quicumque: "Athanasian Creed",
};

const canticleAuthors: Readonly<Record<string, string>> = {
  Annæ: "Anna",
  David: "David",
  Ecclesiastici: "Ecclesiasticus",
  Ezechiæ: "Ezechias",
  Habacuc: "Habacuc",
  Ieremiæ: "Jeremias",
  Isaiæ: "Isaias",
  Iudith: "Judith",
  Moysis: "Moses",
  Tobiæ: "Tobias",
  "Trium Puerorum": "the Three Children",
};

function english(title: string): string | null {
  const value = title.trim();
  if (Object.hasOwn(named, value)) return named[value];
  let match = /^Psalmus (.+)$/u.exec(value);
  if (match) return `Psalm ${match[1]}`;
  match = /^Lectio (\d+)$/u.exec(value);
  if (match) return `Reading ${match[1]}`;
  match = /^Responsorium (\d+)$/u.exec(value);
  if (match) return `Responsory ${match[1]}`;
  match = /^Canticum: Canticum (.+?)(?: \[\d+\])?$/u.exec(value);
  if (match) {
    const name = match[1];
    if (Object.hasOwn(canticles, name)) return canticles[name];
    return `Canticle of ${Object.hasOwn(canticleAuthors, name) ? canticleAuthors[name] : name}`;
  }
  match = /^Canticum: (.+)$/u.exec(value);
  if (match) return `Canticle: ${match[1]}`;
  match = /^Commemoratio (.+)$/u.exec(value);
  if (match) return `Commemoration: ${match[1]}`;
  return null;
}

export const OfficeHeadingTranslation = { english };
