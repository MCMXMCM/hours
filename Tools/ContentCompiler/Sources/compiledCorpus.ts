import { DatabaseSync } from "node:sqlite";
import { decodeContentPayload } from "./contentPayload.ts";
import type {
  ChantScore,
  CorpusInput,
  LiturgicalDay,
  Manifest,
  OfficeDocument,
  OfficeHour,
  OfficeSection
} from "./types.ts";

function decodedJSON<T>(value: string | Uint8Array): T {
  return JSON.parse(decodeContentPayload(value)) as T;
}

function localDay(value: string): { year: number; month: number; day: number } {
  const [year, month, day] = value.split("-").map(Number);
  return { year, month, day };
}

interface StoredSection extends OfficeSection {
  scoreID?: string | null;
}

interface StoredDocument extends Omit<OfficeDocument, "sections"> {
  sections: StoredSection[];
}

export function loadCompiledCorpus(path: string): CorpusInput {
  const database = new DatabaseSync(path, { readOnly: true });
  try {
    const manifestRow = database.prepare(
      "SELECT value FROM meta WHERE key = ?"
    ).get("manifest") as { value: string };
    const manifest = decodedJSON<Manifest>(manifestRow.value);
    const days = database.prepare(
      "SELECT payload FROM days ORDER BY date"
    ).all() as Array<{ payload: Uint8Array }>;
    const scoreRows = database.prepare(
      "SELECT id, payload FROM scores"
    ).all() as Array<{ id: string; payload: Uint8Array }>;
    const scores = new Map(
      scoreRows.map(row => [row.id, decodedJSON<ChantScore>(row.payload)])
    );
    const officeRows = database.prepare(`
      SELECT office_index.date, office_index.hour, documents.payload
      FROM office_index
      JOIN documents ON documents.id = office_index.document_id
      ORDER BY office_index.date, office_index.hour
    `).all() as Array<{
      date: string;
      hour: OfficeHour;
      payload: Uint8Array;
    }>;

    const offices = officeRows.map(row => {
      const stored = decodedJSON<StoredDocument>(row.payload);
      return {
        ...stored,
        id: `${row.date}-${row.hour}`,
        date: localDay(row.date),
        hour: row.hour,
        sections: stored.sections.map(section => {
          const { scoreID, ...plain } = section;
          if (scoreID && !scores.has(scoreID)) {
            throw new Error(
              `Compiled section ${section.id} references missing score ${scoreID}`
            );
          }
          return {
            ...plain,
            chant: scoreID ? scores.get(scoreID)! : null
          };
        })
      };
    });

    return {
      manifest,
      days: days.map(row => decodedJSON<LiturgicalDay>(row.payload)),
      offices
    };
  } finally {
    database.close();
  }
}
