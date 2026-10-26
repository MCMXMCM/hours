#!/usr/bin/env node
// Writes the Rubrics guides the web app shows: `public/guides/rubrics-roman1960.json`
// and `public/guides/rubrics-roman1954.json`.
//
// The guides are written as Swift values in the iOS app. They are not copied
// out by hand: `export-rubrics-guides.swift` is compiled together with the
// two files that hold them, unmodified, and the program that results writes
// what those files say. The export is skipped while the guides on hand are
// those the present sources make.
//
//   node scripts/export-rubrics-guides.mjs

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(import.meta.url);
const root = join(dirname(script), "..");
const repository = join(root, "..");
const outputDirectory = join(root, "public", "guides");

/** The guides, as the iOS app holds them. They are compiled as they stand. */
const contents = [
  join(repository, "HoursApp", "RubricsGuideContent.swift"),
  join(repository, "HoursApp", "Rubrics1954GuideContent.swift"),
];
const exporter = join(root, "scripts", "export-rubrics-guides.swift");

/** The files the web app fetches: one for each edition it offers. */
const guides = {
  roman1960: "rubrics-roman1960.json",
  roman1954: "rubrics-roman1954.json",
};

/** The format `export-rubrics-guides.swift` writes. */
const schema = 1;

class ExportError extends Error {}

function named(path) {
  return relative(repository, path);
}

/** Names the sources a guide was made from, so a current one is not remade. */
function sourceSignature() {
  const hash = createHash("sha256");
  hash.update(`schema ${schema}\n`);
  for (const path of [...contents, exporter, script]) {
    if (!existsSync(path)) {
      throw new ExportError(`${named(path)} is missing.`);
    }
    const bytes = readFileSync(path);
    hash.update(`${named(path)} ${bytes.length}\n`);
    hash.update(bytes);
  }
  return hash.digest("hex").slice(0, 16);
}

/** The guide in a file, or null when the file is absent or cannot be read. */
function guideAt(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function isCurrent(signature) {
  return Object.entries(guides).every(([id, file]) => {
    const guide = guideAt(join(outputDirectory, file));
    return (
      guide !== null &&
      guide.schema === schema &&
      guide.signature === signature &&
      guide.edition?.id === id
    );
  });
}

function compile(tool) {
  try {
    execFileSync("swiftc", [...contents, exporter, "-o", tool], {
      stdio: ["ignore", "ignore", "inherit"],
    });
  } catch (error) {
    if (error?.code === "ENOENT") {
      throw new ExportError(
        "swiftc was not found. The Swift toolchain (Xcode, or its command-line tools) is needed to read the guides.",
      );
    }
    throw new ExportError(
      "swiftc could not compile the guides; its report is above.",
    );
  }
}

function run(tool, directory, signature) {
  let output;
  try {
    output = execFileSync(tool, [directory, signature], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "inherit"],
      maxBuffer: 1 << 24,
    });
  } catch {
    throw new ExportError("The exporter did not finish; its report is above.");
  }
  try {
    return JSON.parse(output);
  } catch {
    throw new ExportError("The exporter's report could not be read.");
  }
}

/** Confirms that what was written is what the web app expects to fetch. */
function verify(directory, report, signature) {
  const written = readdirSync(directory).sort();
  const expected = Object.values(guides).sort();
  if (written.join("\n") !== expected.join("\n")) {
    throw new ExportError(
      `The Swift guides are ${written.join(", ") || "none"}, but the web app offers ${expected.join(", ")}. ` +
        "An edition added to RubricsEdition must be added here and to the web app's Rubrics screen.",
    );
  }
  for (const [id, file] of Object.entries(guides)) {
    const guide = guideAt(join(directory, file));
    const counted = report.guides?.find((entry) => entry.id === id);
    if (
      guide === null ||
      guide.schema !== schema ||
      guide.signature !== signature ||
      guide.edition?.id !== id ||
      !Number.isInteger(guide.order) ||
      !Array.isArray(guide.edition.topics) ||
      guide.edition.topics.length === 0 ||
      counted?.file !== file ||
      counted.topics !== guide.edition.topics.length
    ) {
      throw new ExportError(`${file} was not written as expected.`);
    }
  }
}

function summary(report) {
  return report.guides
    .map(
      (guide) =>
        `${guide.id}: ${guide.topics} topics, ${guide.rules} rules, ` +
        `${guide.paragraphs} paragraphs, ${guide.citations} citations`,
    )
    .join("; ");
}

function exportGuides() {
  const signature = sourceSignature();
  if (isCurrent(signature)) {
    console.log("The Rubrics guides in public/guides/ are current.");
    return;
  }

  const work = mkdtempSync(join(tmpdir(), "hours-rubrics-"));
  try {
    const tool = join(work, "export-rubrics-guides");
    const written = join(work, "guides");
    mkdirSync(written);
    compile(tool);
    const report = run(tool, written, signature);
    verify(written, report, signature);

    // Only a complete export replaces what is there.
    mkdirSync(outputDirectory, { recursive: true });
    for (const file of Object.values(guides)) {
      const staged = join(outputDirectory, `.${file}.${process.pid}`);
      copyFileSync(join(written, file), staged);
      renameSync(staged, join(outputDirectory, file));
    }
    console.log(
      `Exported the Rubrics guides to public/guides/ (${summary(report)}).`,
    );
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

try {
  exportGuides();
} catch (error) {
  if (!(error instanceof ExportError)) throw error;
  console.error(`export-rubrics-guides: ${error.message}`);
  process.exit(1);
}
