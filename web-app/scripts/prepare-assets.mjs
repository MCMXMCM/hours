#!/usr/bin/env node
// Copies the artwork and typeface the web app shares with the iOS app and
// the public site into `public/`. These files are generated here, never
// committed twice: the originals remain the single source.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import wawoff2 from "wawoff2";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const repository = join(root, "..");
const publicDirectory = join(root, "public");
const site = join(repository, "web", "local-site");
const resources = join(repository, "HoursApp", "Resources");

function copy(from, to) {
  mkdirSync(dirname(to), { recursive: true });
  copyFileSync(from, to);
}

function resize(from, to, pixels) {
  mkdirSync(dirname(to), { recursive: true });
  execFileSync(
    "sips",
    ["-z", String(pixels), String(pixels), from, "--out", to],
    {
      stdio: "ignore",
    },
  );
}

// EB Garamond, as WOFF2. The variable weight axis is preserved.
const font = readFileSync(join(resources, "EBGaramond-VariableFont_wght.ttf"));
mkdirSync(join(publicDirectory, "fonts"), { recursive: true });
writeFileSync(
  join(publicDirectory, "fonts", "EBGaramond-VariableFont_wght.woff2"),
  await wawoff2.compress(font),
);
copy(
  join(resources, "EBGaramond-OFL.txt"),
  join(publicDirectory, "fonts", "EBGaramond-OFL.txt"),
);

// The hour wheel's tapestry and pointer, and the icons, are the publisher's
// artwork, kept with the public site; a checkout of the published source
// does not carry them, and the app is then built without them.
const artwork = existsSync(join(site, "hours-app-icon.png"));
if (artwork) {
  // The hour wheel's tapestry and pointer.
  copy(
    join(site, "hour-wheel", "tapestry-20260907.webp"),
    join(publicDirectory, "wheel", "tapestry.webp"),
  );
  copy(
    join(site, "hour-wheel", "hour-dial-pointer.svg"),
    join(publicDirectory, "wheel", "pointer.svg"),
  );

  // Icons.
  copy(
    join(site, "favicon.ico"),
    join(publicDirectory, "icons", "favicon.ico"),
  );
  copy(
    join(site, "favicon-32x32.png"),
    join(publicDirectory, "icons", "favicon-32x32.png"),
  );
  copy(
    join(site, "apple-touch-icon.png"),
    join(publicDirectory, "icons", "apple-touch-icon.png"),
  );
  const icon = join(site, "hours-app-icon.png");
  resize(icon, join(publicDirectory, "icons", "icon-192.png"), 192);
  resize(icon, join(publicDirectory, "icons", "icon-512.png"), 512);
  // A maskable icon keeps its artwork inside the central safe zone.
  const padded = join(publicDirectory, "icons", "maskable-512.png");
  resize(icon, padded, 400);
  execFileSync(
    "sips",
    [
      "--padToHeightWidth",
      "512",
      "512",
      "--padColor",
      "FFFFFF",
      padded,
      "--out",
      padded,
    ],
    { stdio: "ignore" },
  );
}

// The cantor guide's harp: one recording for each key, rendered from the
// app's sound bank by the sampler the app itself plays it with. Rendering is
// skipped while the recordings on hand are those this bank and script make.
const harpKeys = { lowest: 33, highest: 96 };
// `HarpSoundBank.sha256`, in ChantPlaybackController.swift and harpEnvelope.ts.
const harpBankSHA256 =
  "ac8aeee47a423c3cfaa3ccc17cca2eef1ca0dc86a7c3a1cfd4334f1afe4c4c37";
const harpBank = join(resources, "ConcertHarp.sf2");
const harpScript = join(root, "scripts", "render-harp.swift");
const harpDirectory = join(publicDirectory, "harp");
const sha256 = (...parts) => {
  const hash = createHash("sha256");
  for (const part of parts) hash.update(part);
  return hash.digest("hex");
};

function prepareHarp() {
  const bankSHA256 = sha256(readFileSync(harpBank));
  if (bankSHA256 !== harpBankSHA256) {
    throw new Error(
      `ConcertHarp.sf2 is not the bank the app names (${bankSHA256}). ` +
        "Update HarpSoundBank.sha256 in both apps with the bank.",
    );
  }
  const signature = sha256(
    bankSHA256,
    readFileSync(harpScript),
    JSON.stringify(harpKeys),
  ).slice(0, 16);
  const manifestPath = join(harpDirectory, "manifest.json");
  const recordings = join(harpDirectory, signature);
  if (existsSync(manifestPath)) {
    const existing = JSON.parse(readFileSync(manifestPath, "utf8"));
    let complete = existing.directory === signature;
    for (
      let key = harpKeys.lowest;
      complete && key <= harpKeys.highest;
      key += 1
    ) {
      complete = existsSync(join(recordings, `${key}.flac`));
    }
    if (complete) return false;
  }

  const work = mkdtempSync(join(tmpdir(), "hours-harp-"));
  try {
    const tool = join(work, "render-harp");
    execFileSync("swiftc", ["-O", harpScript, "-o", tool], {
      stdio: ["ignore", "ignore", "inherit"],
    });
    rmSync(harpDirectory, { recursive: true, force: true });
    mkdirSync(recordings, { recursive: true });
    const report = JSON.parse(
      execFileSync(
        tool,
        [
          harpBank,
          recordings,
          String(harpKeys.lowest),
          String(harpKeys.highest),
        ],
        {
          encoding: "utf8",
          stdio: ["ignore", "pipe", "inherit"],
          maxBuffer: 1 << 24,
        },
      ),
    );
    writeFileSync(
      manifestPath,
      `${JSON.stringify({
        schema: 1,
        directory: signature,
        format: "flac",
        lowestNote: harpKeys.lowest,
        highestNote: harpKeys.highest,
        sampleRate: report.sampleRate,
        seconds: report.seconds,
        soundBankSHA256: bankSHA256,
      })}\n`,
    );
    copy(
      join(resources, "ConcertHarp-LICENSE.txt"),
      join(harpDirectory, "LICENSE.txt"),
    );
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  return true;
}

const renderedHarp = prepareHarp();

// The Guide to Chant, as the native app bundles it, and the Rubrics, whose
// prose is written as Swift values: a small Swift program built from those
// two files, unmodified, writes them out. No sentence of either guide is
// retyped on its way to the browser.
copy(
  join(resources, "chant-guide.json"),
  join(publicDirectory, "guides", "chant-guide.json"),
);
execFileSync(
  process.execPath,
  [join(root, "scripts", "export-rubrics-guides.mjs")],
  { stdio: ["ignore", "ignore", "inherit"] },
);

// The notices of the software the bundle carries.
execFileSync("node", [join(root, "scripts", "third-party-licenses.mjs")], {
  stdio: ["ignore", "ignore", "inherit"],
});

console.log(
  `Prepared fonts, ${artwork ? "wheel artwork, icons, " : "(without the site's artwork) "}the harp${renderedHarp ? "" : " (unchanged)"}, the guides, and third-party notices in public/.`,
);
