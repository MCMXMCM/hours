import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

interface MartyrologyReviewMatrix {
  schemaVersion: number;
  englishBase: {
    pdfSHA256: string;
    ocrSHA256: string;
  };
  approval: {
    status: "pendingHumanReview" | "approved";
    reviewedBy: string | null;
    reviewedAt: string | null;
  };
  entries: Array<{
    officeDate: string;
    id: string;
    latinIncipit: string;
    basePages: string;
    variation: string;
  }>;
}

const reviewPath = new URL(
  "../Fixtures/martyrology-exceptional-review.json",
  import.meta.url
);

export const exceptionalMartyrologyEnglish: Readonly<Record<string, string>> = {
  "2026-02-22": `Martyrology {anticipated}

The seventh Kalends of March. The sixth day of the Moon. In the year of our Lord 2026.

Saint Peter Damian, of the Camaldolese Order, Cardinal and Bishop of Ostia, Confessor and Doctor of the Church, who departed for heaven yesterday.

At Smyrna, the birthday of Saint Polycarp, a disciple of the blessed Apostle John, who ordained him Bishop of that city, and who was Primate of all Asia. Afterwards, under Marcus Antoninus and Lucius Aurelius Commodus, while the proconsul sat in judgment and all the people in the amphitheatre clamored against him, he was delivered to the flames. But as he received no injury from them, he was pierced with a sword and thus received the crown of martyrdom. With him, in the same city of Smyrna, twelve others from Philadelphia also consummated their martyrdom. The feast of Saint Polycarp himself is celebrated on the seventh Kalends of February.

At Sirmium, blessed Sirenus, monk and martyr, who by order of the Emperor Maximian was arrested and, after confessing that he was a Christian, was beheaded.

In the same place, the birthday of seventy-two holy martyrs, who finished the combat of martyrdom in that city and received the everlasting kingdom.

In the city of Astorga in Spain, Saint Martha, virgin and martyr, who under the Emperor Decius and the proconsul Paternus was cruelly tortured for the faith of Christ and finally put to the sword.

At Constantinople, Saint Lazarus, monk, who, because he painted sacred images, was subjected to cruel torments by order of the Iconoclast Emperor Theophilus, and whose hand was burned with a hot iron. But, healed by the power of God, he restored the holy images which had been defaced, and at length rested in peace.

At Brescia, Saint Felix, bishop.

At Rome, Saint Polycarp, priest, who with blessed Sebastian converted many to the faith of Christ, and by his exhortations led them to the glory of martyrdom.

At Seville in Spain, Saint Florentius, confessor.

At Todi in Umbria, Saint Romana, virgin, who was baptized by Pope Saint Sylvester, led a heavenly life in caves and dens, and became renowned for glorious miracles.

In England, Saint Milburga, virgin, daughter of the king of Mercia.

In a leap year the sixth Kalends of March and the same lunar day are announced twice, namely on February 24 and 25. On the first day, February 24, it is announced thus: The sixth Kalends of March. The Moon ..., whatever its number may be. Then: The commemoration of many holy martyrs and confessors, and of holy virgins. On the second day, February 25: The sixth Kalends of March. The Moon ... In Judea ..., and the rest, as in the following lesson.

℣. And elsewhere many other holy martyrs and confessors, and holy virgins.

℟. Thanks be to God.`,
  "2026-12-24": `Martyrology {anticipated}

The eighth Kalends of January. The sixteenth day of the Moon. In the year of our Lord 2026.

In the year from the creation of the world, when in the beginning God created heaven and earth, five thousand one hundred and ninety-nine; from the Flood, two thousand nine hundred and fifty-seven; from the birth of Abraham, two thousand and fifteen; from Moses and the coming of the people of Israel out of Egypt, one thousand five hundred and ten; from the anointing of David as king, one thousand and thirty-two; in the sixty-fifth week according to the prophecy of Daniel; in the one hundred and ninety-fourth Olympiad; in the year seven hundred and fifty-two from the founding of the city of Rome; in the forty-second year of the reign of Octavian Augustus, when the whole world was at peace, in the sixth age of the world, Jesus Christ, eternal God and Son of the eternal Father, desiring to sanctify the world by his most merciful coming, having been conceived of the Holy Ghost, and nine months having elapsed since his conception—Here the voice is raised, and all kneel—was born in Bethlehem of Juda, having become man of the Virgin Mary. Here, however, it is said in the former voice and in the Passion tone: The Nativity of our Lord Jesus Christ according to the flesh.

What follows is read in the usual lesson tone, and all stand.

The same day, the birthday of Saint Anastasia, who, in the time of Diocletian, first suffered a severe and harsh imprisonment at the hands of her husband Publius, in which, however, she was greatly consoled and strengthened by Chrysogonus, a confessor of Christ. Afterwards, by order of Florus, prefect of Illyria, she was worn down by a long imprisonment; and finally, with hands and feet stretched out, she was bound to stakes and a fire was kindled about her, in which she consummated her martyrdom on the island of Palmarola. She had been conveyed there with two hundred men and seventy women, who made martyrdom glorious by the various kinds of death which they endured.

At Barcelona in Spain, likewise the birthday of Saint Peter Nolasco, confessor, who was the founder of the Order of Blessed Mary of Mercy for the Redemption of Captives, and was renowned for virtue and miracles. His feast is celebrated on the fifth Kalends of February.

At Rome, in the cemetery of Apronian, Saint Eugenia, virgin, daughter of the blessed martyr Philip. In the time of the Emperor Gallienus, after many illustrious works of virtue, after gathering choirs of holy virgins to Christ, and after long combats under Nicetius, prefect of the city, she was finally put to the sword.

At Nicomedia, the passion of many thousand martyrs, who had assembled in the church for divine service on the Nativity of Christ. The Emperor Diocletian ordered the doors of the church to be closed, fire to be kindled round about, and a tripod with incense to be placed before the entrance; and he caused a herald to cry out in a loud voice that those who wished to escape the conflagration should come forth and offer incense to Jupiter. When all answered with one voice that they preferred to die for Christ, they were consumed in the fire, and thus merited to be born in heaven on the day on which Christ once vouchsafed to be born on earth for the salvation of the world.

℣. And elsewhere many other holy martyrs and confessors, and holy virgins.

℟. Thanks be to God.`
};

export function exceptionalMartyrologyReview(): {
  matrix: MartyrologyReviewMatrix;
  checksum: string;
} {
  const bytes = readFileSync(reviewPath);
  const matrix = JSON.parse(bytes.toString("utf8")) as MartyrologyReviewMatrix;
  if (matrix.schemaVersion !== 1) {
    throw new Error("Unsupported exceptional Martyrology review schema");
  }
  if (
    matrix.englishBase.pdfSHA256
      !== "688cfa7b85d8a686a4fde9877cfa133550fef8fce8cf46c6c433abf88983042d"
    || matrix.englishBase.ocrSHA256
      !== "7131b487ca60c9b9d938a3875e877ba62b1bd1e879dc7f484c0df0309cde2ed6"
  ) {
    throw new Error("Exceptional Martyrology source checksums are not pinned correctly");
  }
  for (const date of Object.keys(exceptionalMartyrologyEnglish)) {
    if (!matrix.entries.some(entry => entry.officeDate === date)) {
      throw new Error(`${date} lacks an exceptional Martyrology review matrix`);
    }
  }
  return {
    matrix,
    checksum: createHash("sha256").update(bytes).digest("hex")
  };
}

export function requireApprovedExceptionalMartyrology(): void {
  const { matrix } = exceptionalMartyrologyReview();
  if (
    matrix.approval.status !== "approved"
    || !matrix.approval.reviewedBy?.trim()
    || !matrix.approval.reviewedAt?.trim()
  ) {
    throw new Error(
      "Exceptional English Martyrology requires recorded human approval before release"
    );
  }
}
