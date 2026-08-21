import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { officeHours, type OfficeHour } from "./types.ts";

interface SnapshotOptions {
  sourceRoot: string;
  outputRoot: string;
  from: string;
  to: string;
  expectedRevision: string;
}

interface SnapshotRecord {
  date: string;
  hour: OfficeHour;
  file: string;
  sha256: string;
}

const commandByHour: Record<OfficeHour, string> = {
  matins: "prayMatutinum",
  lauds: "prayLaudes",
  prime: "prayPrima",
  terce: "prayTertia",
  sext: "praySexta",
  none: "prayNona",
  vespers: "prayVespera",
  compline: "prayCompletorium"
};

function civilDates(from: string, to: string): string[] {
  const first = new Date(`${from}T12:00:00Z`);
  const last = new Date(`${to}T12:00:00Z`);
  if (Number.isNaN(first.valueOf()) || Number.isNaN(last.valueOf()) || first > last) {
    throw new Error("Invalid Divinum Officium snapshot date range");
  }
  const dates: string[] = [];
  for (const cursor = new Date(first); cursor <= last; cursor.setUTCDate(cursor.getUTCDate() + 1)) {
    dates.push(cursor.toISOString().slice(0, 10));
  }
  return dates;
}

function generatorDate(isoDate: string): string {
  const [year, month, day] = isoDate.split("-");
  return `${month}-${day}-${year}`;
}

export function renderDivinumOffice(options: {
  sourceRoot: string;
  date: string;
  hour: OfficeHour;
  latinLanguage?: "Latin" | "Latin-gabc";
}): string {
  const sourceRoot = resolve(options.sourceRoot);
  const generatorDirectory = join(sourceRoot, "standalone", "tools", "epubgen2");
  const generator = join(generatorDirectory, "EofficiumXhtml.pl");
  const query = new URLSearchParams({
    date1: generatorDate(options.date),
    command: commandByHour[options.hour],
    version: "Rubrics 1960 - 1960",
    testmode: "regular",
    lang1: options.latinLanguage ?? "Latin",
    lang2: "English",
    votive: "",
    nofancychars: "1"
  }).toString();
  let html: string;
  try {
    html = execFileSync("perl", [generator, query], {
      cwd: generatorDirectory,
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["ignore", "pipe", "ignore"]
    });
  } catch (error) {
    throw new Error(
      `Divinum Officium failed for ${options.date} ${options.hour}. `
      + "Use its documented generator container when local Perl modules are unavailable.",
      { cause: error }
    );
  }
  if (!html.includes("<html") && !html.includes("<!DOCTYPE")) {
    throw new Error(`Divinum Officium returned invalid HTML for ${options.date} ${options.hour}`);
  }
  return html;
}

export function assertPinnedCheckout(sourceRoot: string, expectedRevision: string): void {
  const actual = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: sourceRoot,
    encoding: "utf8"
  }).trim();
  if (actual !== expectedRevision) {
    throw new Error(`Divinum Officium checkout is ${actual}; expected pinned ${expectedRevision}`);
  }
}

export function snapshotDivinumOfficium(options: SnapshotOptions): SnapshotRecord[] {
  const sourceRoot = resolve(options.sourceRoot);
  const outputRoot = resolve(options.outputRoot);
  assertPinnedCheckout(sourceRoot, options.expectedRevision);
  const records: SnapshotRecord[] = [];
  mkdirSync(outputRoot, { recursive: true });

  for (const date of civilDates(options.from, options.to)) {
    for (const hour of officeHours) {
      const html = renderDivinumOffice({ sourceRoot, date, hour });
      const file = `${date}-${hour}.html`;
      writeFileSync(join(outputRoot, file), html);
      records.push({
        date,
        hour,
        file,
        sha256: createHash("sha256").update(html).digest("hex")
      });
    }
  }

  writeFileSync(
    join(outputRoot, "snapshot-manifest.json"),
    `${JSON.stringify({
      generator: "Divinum Officium EofficiumXhtml.pl",
      revision: options.expectedRevision,
      rubrics: "Rubrics 1960 - 1960",
      records
    }, null, 2)}\n`
  );
  return records;
}

export function revisionFromLock(lockPath: string, sourceName: string): string {
  const lock = JSON.parse(readFileSync(lockPath, "utf8")) as {
    sources: Array<{ name: string; revision: string }>;
  };
  const source = lock.sources.find(item => item.name === sourceName);
  if (!source || !/^[0-9a-f]{40}$/.test(source.revision)) {
    throw new Error(`${sourceName} does not have a full pinned revision in ${lockPath}`);
  }
  return source.revision;
}
