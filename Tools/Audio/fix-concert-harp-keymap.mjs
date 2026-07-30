#!/usr/bin/env node

import fs from "node:fs";

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  console.error(
    "Usage: fix-concert-harp-keymap.mjs INPUT.sf2 OUTPUT.sf2",
  );
  process.exit(1);
}

const soundFont = fs.readFileSync(inputPath);
const instrumentGeneratorsOffset = soundFont.indexOf(Buffer.from("igen"));
if (instrumentGeneratorsOffset < 0) {
  throw new Error("SoundFont is missing its instrument-generator table.");
}

const byteCount = soundFont.readUInt32LE(instrumentGeneratorsOffset + 4);
const firstRecord = instrumentGeneratorsOffset + 8;
const end = firstRecord + byteCount;
const matchingRanges = [];
for (let offset = firstRecord; offset < end; offset += 4) {
  const generator = soundFont.readUInt16LE(offset);
  const lowKey = soundFont[offset + 2];
  const highKey = soundFont[offset + 3];
  if (generator === 43 && lowKey === 64 && highKey === 67) {
    matchingRanges.push(offset);
  }
}

if (matchingRanges.length !== 1) {
  throw new Error(
    `Expected one low-velocity MIDI 64...67 range; found ${matchingRanges.length}.`,
  );
}

// The upstream medium-force F4 zone stops at MIDI 67 while the next
// low-velocity zone starts at MIDI 69, leaving A-flat 4 silent. The forte
// layer already covers MIDI 68 from the same F4 sample. Extend the
// medium-force zone by one semitone to match it.
soundFont[matchingRanges[0] + 3] = 68;
fs.writeFileSync(outputPath, soundFont);
