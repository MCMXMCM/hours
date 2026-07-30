#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const args = parseArguments(process.argv.slice(2));
const required = ["left-kmp", "right-kmp", "output"];
for (const option of required) {
  if (!args[option]) {
    fail(`Missing required option --${option}`);
  }
}

const instrumentName = args.name ?? "Muted Organ";
const left = readMultisample(args["left-kmp"]);
const right = readMultisample(args["right-kmp"]);
let pairs = pairSamples(left, right);

if (pairs.length === 0) {
  fail("The KMP files do not contain any playable stereo sample pairs.");
}

if (args.step) {
  const step = Number.parseInt(args.step, 10);
  if (!Number.isInteger(step) || step < 1) {
    fail("--step must be a positive integer.");
  }
  const firstRoot = pairs[0].rootKey;
  pairs = pairs.filter(
    (pair, index, allPairs) =>
      (pair.rootKey - firstRoot) % step === 0
      || index === allPairs.length - 1,
  );
  pairs = remapKeyRanges(pairs);
}

if (args.template) {
  const templateKeys = templateRootKeys(args.template);
  const pairByKey = new Map(pairs.map((pair) => [pair.rootKey, pair]));
  pairs = templateKeys.map((key) => {
    const pair = pairByKey.get(key);
    if (!pair) {
      fail(`The source multisample has no pipe for template key MIDI ${key}.`);
    }
    return pair;
  });
}

pairs = normalizePairs(pairs, 0.18, 0.85);

const soundFont = args.template
  ? buildSoundFontFromTemplate(args.template, instrumentName, pairs)
  : buildSoundFont(instrumentName, pairs);
fs.mkdirSync(path.dirname(args.output), { recursive: true });
fs.writeFileSync(args.output, soundFont);

const firstKey = pairs[0].rootKey;
const lastKey = pairs.at(-1).rootKey;
const sourceBytes = pairs.reduce(
  (sum, pair) => sum + pair.left.pcm.byteLength + pair.right.pcm.byteLength,
  0,
);
console.log(
  [
    `Built ${args.output}`,
    `Instrument: ${instrumentName}`,
    `Samples: ${pairs.length} stereo pairs`,
    `Key range: MIDI ${firstKey}...${lastKey}`,
    `Decoded source PCM: ${formatBytes(sourceBytes)}`,
    `SoundFont size: ${formatBytes(soundFont.byteLength)}`,
  ].join("\n"),
);

function parseArguments(tokens) {
  const result = {};
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token.startsWith("--")) {
      fail(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    const value = tokens[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`Missing value for ${token}`);
    }
    result[key] = value;
    index += 1;
  }
  return result;
}

function readMultisample(kmpPath) {
  const kmp = fs.readFileSync(kmpPath);
  const rlpOffset = kmp.indexOf(Buffer.from("RLP1"));
  if (rlpOffset < 0) {
    fail(`${kmpPath} does not contain an RLP1 sample map.`);
  }

  const byteCount = kmp.readUInt32BE(rlpOffset + 4);
  if (byteCount % 18 !== 0) {
    fail(`${kmpPath} has a malformed RLP1 sample map.`);
  }

  const directory = path.join(
    path.dirname(kmpPath),
    path.basename(kmpPath, path.extname(kmpPath)),
  );
  const samples = [];
  for (let index = 0; index < byteCount / 18; index += 1) {
    const offset = rlpOffset + 8 + index * 18;
    const originalKey = kmp[offset] & 0x7f;
    const topKey = kmp[offset + 1];
    const tuneCents = kmp.readInt8(offset + 2);
    const level = kmp.readInt8(offset + 3);
    const filename = cleanASCII(kmp.subarray(offset + 6, offset + 18));
    if (filename === "SKIPPEDSAMPL" || filename.startsWith("INTERNAL")) {
      continue;
    }

    const samplePath = path.join(directory, filename);
    samples.push({
      ...readKSF(samplePath),
      rootKey: originalKey,
      topKey,
      tuneCents,
      level,
      sourcePath: samplePath,
    });
  }
  return { kmpPath, samples };
}

function readKSF(samplePath) {
  const data = fs.readFileSync(samplePath);
  const smpOffset = data.indexOf(Buffer.from("SMP1"));
  const smdOffset = data.indexOf(Buffer.from("SMD1"));
  if (smpOffset < 0 || smdOffset < 0) {
    fail(`${samplePath} is missing required KSF chunks.`);
  }

  const sampleName = cleanASCII(data.subarray(smpOffset + 8, smpOffset + 24));
  const startAddress = readUInt24BE(data, smpOffset + 25);
  const secondStartAddress = data.readUInt32BE(smpOffset + 28);
  const loopStart = data.readUInt32BE(smpOffset + 32);
  const declaredLoopEnd = data.readUInt32BE(smpOffset + 36);

  const sampleRate = data.readUInt32BE(smdOffset + 8);
  const attributes = data[smdOffset + 12];
  const loopTuneCents = data.readInt8(smdOffset + 13);
  const channelCount = data[smdOffset + 14];
  const bitDepth = data[smdOffset + 15];
  const frameCount = data.readUInt32BE(smdOffset + 16);
  if ((attributes & 0x10) !== 0 || channelCount !== 1 || bitDepth !== 16) {
    fail(
      `${samplePath} is not an uncompressed, mono, 16-bit KSF sample.`,
    );
  }

  const pcmOffset = smdOffset + 20;
  const pcmBytes = frameCount * 2;
  if (pcmOffset + pcmBytes > data.byteLength) {
    fail(`${samplePath} contains truncated PCM data.`);
  }

  const pcm = new Int16Array(frameCount);
  for (let frame = 0; frame < frameCount; frame += 1) {
    pcm[frame] = data.readInt16BE(pcmOffset + frame * 2);
  }

  return {
    sampleName,
    sampleRate,
    startAddress,
    secondStartAddress,
    loopStart,
    declaredLoopEnd,
    loopTuneCents,
    pcm,
  };
}

function pairSamples(left, right) {
  const rightByKey = new Map(
    right.samples.map((sample) => [sample.rootKey, sample]),
  );
  return left.samples.map((leftSample, pairIndex, allLeft) => {
    const rightSample = rightByKey.get(leftSample.rootKey);
    if (!rightSample) {
      fail(`No right-channel sample exists for MIDI ${leftSample.rootKey}.`);
    }
    if (leftSample.sampleRate !== rightSample.sampleRate) {
      fail(`Stereo sample rates differ at MIDI ${leftSample.rootKey}.`);
    }

    const loopStart = Math.max(
      leftSample.loopStart,
      rightSample.loopStart,
      leftSample.startAddress,
      rightSample.startAddress,
    );
    const loopEnd = chooseExclusiveLoopEnd(
      leftSample,
      rightSample,
      loopStart,
    );
    if (loopEnd <= loopStart + 8) {
      fail(`Invalid sustain loop at MIDI ${leftSample.rootKey}.`);
    }

    const availableFrames = Math.min(
      leftSample.pcm.length,
      rightSample.pcm.length,
    );
    const trimmedEnd = Math.min(availableFrames, loopEnd + 16);
    const lowKey = pairIndex === 0
      ? 0
      : Math.min(
          leftSample.rootKey,
          allLeft[pairIndex - 1].topKey + 1,
        );
    const highKey = pairIndex === allLeft.length - 1
      ? 127
      : Math.max(leftSample.rootKey, leftSample.topKey);

    return {
      rootKey: leftSample.rootKey,
      lowKey,
      highKey,
      sampleRate: leftSample.sampleRate,
      loopStart,
      loopEnd,
      left: {
        ...leftSample,
        pcm: leftSample.pcm.slice(0, trimmedEnd),
      },
      right: {
        ...rightSample,
        pcm: rightSample.pcm.slice(0, trimmedEnd),
      },
    };
  });
}

function remapKeyRanges(pairs) {
  return pairs.map((pair, index) => {
    const previous = pairs[index - 1];
    const next = pairs[index + 1];
    return {
      ...pair,
      lowKey: previous
        ? Math.floor((previous.rootKey + pair.rootKey) / 2) + 1
        : 0,
      highKey: next
        ? Math.floor((pair.rootKey + next.rootKey) / 2)
        : 127,
    };
  });
}

function normalizePairs(pairs, targetRMS, maximumPeak) {
  return pairs.map((pair) => {
    let sumOfSquares = 0;
    let frameCount = 0;
    let peak = 0;
    for (const sample of [pair.left, pair.right]) {
      for (
        let frame = pair.loopStart;
        frame < Math.min(pair.loopEnd, sample.pcm.length);
        frame += 1
      ) {
        const normalized = sample.pcm[frame] / 32768;
        sumOfSquares += normalized * normalized;
        peak = Math.max(peak, Math.abs(normalized));
        frameCount += 1;
      }
    }
    const rms = Math.sqrt(sumOfSquares / Math.max(1, frameCount));
    const gain = Math.min(
      targetRMS / Math.max(rms, 0.000_001),
      maximumPeak / Math.max(peak, 0.000_001),
    );
    const scale = (sample) => ({
      ...sample,
      pcm: Int16Array.from(
        sample.pcm,
        (value) => Math.max(-32768, Math.min(32767, Math.round(value * gain))),
      ),
    });
    return {
      ...pair,
      left: scale(pair.left),
      right: scale(pair.right),
    };
  });
}

function chooseExclusiveLoopEnd(left, right, loopStart) {
  const declared = Math.min(left.declaredLoopEnd, right.declaredLoopEnd);
  const candidates = [declared, declared + 1].filter(
    (candidate) =>
      candidate > loopStart + 8
      && candidate < left.pcm.length
      && candidate < right.pcm.length,
  );
  if (candidates.length === 0) {
    return declared;
  }
  return candidates.reduce((best, candidate) => {
    const score = loopBoundaryScore(left.pcm, candidate, loopStart)
      + loopBoundaryScore(right.pcm, candidate, loopStart);
    return score < best.score ? { candidate, score } : best;
  }, { candidate: candidates[0], score: Number.POSITIVE_INFINITY }).candidate;
}

function loopBoundaryScore(pcm, exclusiveEnd, loopStart) {
  let score = 0;
  for (let offset = 0; offset < 8; offset += 1) {
    const beforeEnd = pcm[exclusiveEnd - 1 - offset];
    const beforeStart = pcm[loopStart - 1 - offset];
    const difference = beforeEnd - beforeStart;
    score += difference * difference;
  }
  return score;
}

function buildSoundFont(name, pairs) {
  const sampleDataParts = [];
  const sampleHeaders = [];
  let sampleCursor = 0;

  for (const pair of pairs) {
    const leftIndex = sampleHeaders.length;
    const rightIndex = leftIndex + 1;
    const left = appendSample(
      pair,
      pair.left,
      "L",
      rightIndex,
      4,
      sampleCursor,
    );
    sampleDataParts.push(left.data);
    sampleHeaders.push(left.header);
    sampleCursor = left.nextCursor;

    const right = appendSample(
      pair,
      pair.right,
      "R",
      leftIndex,
      2,
      sampleCursor,
    );
    sampleDataParts.push(right.data);
    sampleHeaders.push(right.header);
    sampleCursor = right.nextCursor;
  }

  const info = buildInfoList(name);
  const sdta = listChunk("sdta", [
    chunk("smpl", Buffer.concat(sampleDataParts)),
  ]);
  const pdta = buildPresetData(name, pairs, sampleHeaders);
  return riff("sfbk", [info, sdta, pdta]);
}

function templateRootKeys(templatePath) {
  const template = fs.readFileSync(templatePath);
  const shdr = findSubchunk(template, "pdta", "shdr");
  const recordCount = shdr.body.byteLength / 46;
  if (!Number.isInteger(recordCount) || recordCount < 2) {
    fail(`${templatePath} has a malformed SoundFont sample-header table.`);
  }

  const keys = [];
  for (let index = 0; index < recordCount - 1; index += 2) {
    const leftOffset = index * 46;
    const rightOffset = leftOffset + 46;
    const leftKey = shdr.body[leftOffset + 40];
    const rightKey = shdr.body[rightOffset + 40];
    if (leftKey !== rightKey) {
      fail(`${templatePath} has mismatched stereo root keys.`);
    }
    keys.push(leftKey);
  }
  return keys;
}

function buildSoundFontFromTemplate(templatePath, name, pairs) {
  const template = fs.readFileSync(templatePath);
  const sampleDataParts = [];
  const sampleHeaders = [];
  let sampleCursor = 0;
  for (const pair of pairs) {
    const leftIndex = sampleHeaders.length;
    const rightIndex = leftIndex + 1;
    const left = appendSample(
      pair,
      pair.left,
      "L",
      rightIndex,
      4,
      sampleCursor,
    );
    sampleDataParts.push(left.data);
    sampleHeaders.push(left.header);
    sampleCursor = left.nextCursor;

    const right = appendSample(
      pair,
      pair.right,
      "R",
      leftIndex,
      2,
      sampleCursor,
    );
    sampleDataParts.push(right.data);
    sampleHeaders.push(right.header);
    sampleCursor = right.nextCursor;
  }

  const terminalSample = sampleHeader({
    name: "EOS",
    start: 0,
    end: 0,
    loopStart: 0,
    loopEnd: 0,
    sampleRate: 0,
    originalPitch: 0,
    pitchCorrection: 0,
    sampleLink: 0,
    sampleType: 0,
  });
  const renamedTemplate = Buffer.from(template);
  for (const chunkID of ["phdr", "inst"]) {
    const table = findSubchunk(renamedTemplate, "pdta", chunkID);
    table.body.fill(0, 0, 20);
    fitASCII(name, 20).copy(table.body, 0);
  }
  const info = buildInfoList(name);
  const sdta = listChunk("sdta", [
    chunk("smpl", Buffer.concat(sampleDataParts)),
  ]);
  const pdta = replaceListSubchunk(
    renamedTemplate,
    "pdta",
    "shdr",
    chunk("shdr", Buffer.concat([...sampleHeaders, terminalSample])),
  );
  return riff("sfbk", [info, sdta, pdta]);
}

function buildInfoList(name) {
  return listChunk("INFO", [
    chunk("ifil", uint16s([2, 1])),
    chunk("isng", asciiZ("EMU8000")),
    chunk("INAM", asciiZ(name)),
    chunk("ICRD", asciiZ(new Date().toISOString().slice(0, 10))),
    chunk(
      "ICMT",
      asciiZ(
        "Lars Palo organ samples; converted for Hours under CC BY-SA 2.5",
      ),
    ),
    chunk("ISFT", asciiZ("Hours KSF-to-SF2 builder")),
  ]);
}

function appendSample(
  pair,
  sample,
  channelLabel,
  linkedSampleIndex,
  sampleType,
  start,
) {
  const pcm = int16LE(sample.pcm);
  const guardFrames = 46;
  const guard = Buffer.alloc(guardFrames * 2);
  const data = Buffer.concat([pcm, guard]);
  const end = start + sample.pcm.length;
  const loopStart = start + pair.loopStart;
  const loopEnd = start + pair.loopEnd;
  const nextCursor = end + guardFrames;
  const fineTune = clampInt8(sample.tuneCents + sample.loopTuneCents);
  const sampleName = `${midiName(pair.rootKey)} ${channelLabel}`;

  return {
    data,
    nextCursor,
    header: sampleHeader({
      name: sampleName,
      start,
      end,
      loopStart,
      loopEnd,
      sampleRate: pair.sampleRate,
      originalPitch: pair.rootKey,
      pitchCorrection: fineTune,
      sampleLink: linkedSampleIndex,
      sampleType,
    }),
  };
}

function buildPresetData(name, pairs, sampleHeaders) {
  const presetName = fitASCII(name, 20);
  const instrumentName = fitASCII(name, 20);
  const phdr = Buffer.concat([
    presetHeader(presetName, 0, 0, 0),
    presetHeader("EOP", 0, 0, 1),
  ]);
  const pbag = Buffer.concat([
    bagRecord(0, 0),
    bagRecord(2, 0),
  ]);
  const pmod = Buffer.alloc(10);
  const pgen = Buffer.concat([
    generatorRangeRecord(43, 0, 127),
    generatorRecord(41, 0),
    generatorRecord(0, 0),
  ]);

  const instrumentBags = [bagRecord(0, 0)];
  const instrumentGenerators = [generatorSignedRecord(38, -4300)];
  let generatorIndex = instrumentGenerators.length;
  for (let pairIndex = 0; pairIndex < pairs.length; pairIndex += 1) {
    const pair = pairs[pairIndex];
    for (const channel of [
      { pan: -500, sampleID: pairIndex * 2 },
      { pan: 500, sampleID: pairIndex * 2 + 1 },
    ]) {
      instrumentBags.push(bagRecord(generatorIndex, 0));
      const generators = [
        generatorRangeRecord(43, pair.lowKey, pair.highKey),
        generatorSignedRecord(17, channel.pan),
        generatorRecord(54, 1),
        generatorRecord(53, channel.sampleID),
      ];
      instrumentGenerators.push(...generators);
      generatorIndex += generators.length;
    }
  }
  instrumentBags.push(bagRecord(generatorIndex, 0));

  const inst = Buffer.concat([
    instrumentHeader(instrumentName, 0),
    instrumentHeader("EOI", instrumentBags.length - 1),
  ]);
  const ibag = Buffer.concat(instrumentBags);
  const imod = Buffer.alloc(10);
  const igen = Buffer.concat([
    ...instrumentGenerators,
    generatorRecord(0, 0),
  ]);
  const terminalSample = sampleHeader({
    name: "EOS",
    start: 0,
    end: 0,
    loopStart: 0,
    loopEnd: 0,
    sampleRate: 0,
    originalPitch: 0,
    pitchCorrection: 0,
    sampleLink: 0,
    sampleType: 0,
  });
  const shdr = Buffer.concat([...sampleHeaders, terminalSample]);

  return listChunk("pdta", [
    chunk("phdr", phdr),
    chunk("pbag", pbag),
    chunk("pmod", pmod),
    chunk("pgen", pgen),
    chunk("inst", inst),
    chunk("ibag", ibag),
    chunk("imod", imod),
    chunk("igen", igen),
    chunk("shdr", shdr),
  ]);
}

function presetHeader(name, preset, bank, bagIndex) {
  const output = Buffer.alloc(38);
  fitASCII(name, 20).copy(output, 0);
  output.writeUInt16LE(preset, 20);
  output.writeUInt16LE(bank, 22);
  output.writeUInt16LE(bagIndex, 24);
  return output;
}

function instrumentHeader(name, bagIndex) {
  const output = Buffer.alloc(22);
  fitASCII(name, 20).copy(output, 0);
  output.writeUInt16LE(bagIndex, 20);
  return output;
}

function bagRecord(generatorIndex, modulatorIndex) {
  const output = Buffer.alloc(4);
  output.writeUInt16LE(generatorIndex, 0);
  output.writeUInt16LE(modulatorIndex, 2);
  return output;
}

function generatorRecord(operator, amount) {
  const output = Buffer.alloc(4);
  output.writeUInt16LE(operator, 0);
  output.writeUInt16LE(amount, 2);
  return output;
}

function generatorSignedRecord(operator, amount) {
  const output = Buffer.alloc(4);
  output.writeUInt16LE(operator, 0);
  output.writeInt16LE(amount, 2);
  return output;
}

function generatorRangeRecord(operator, low, high) {
  const output = Buffer.alloc(4);
  output.writeUInt16LE(operator, 0);
  output[2] = low;
  output[3] = high;
  return output;
}

function sampleHeader({
  name,
  start,
  end,
  loopStart,
  loopEnd,
  sampleRate,
  originalPitch,
  pitchCorrection,
  sampleLink,
  sampleType,
}) {
  const output = Buffer.alloc(46);
  fitASCII(name, 20).copy(output, 0);
  output.writeUInt32LE(start, 20);
  output.writeUInt32LE(end, 24);
  output.writeUInt32LE(loopStart, 28);
  output.writeUInt32LE(loopEnd, 32);
  output.writeUInt32LE(sampleRate, 36);
  output[40] = originalPitch;
  output.writeInt8(pitchCorrection, 41);
  output.writeUInt16LE(sampleLink, 42);
  output.writeUInt16LE(sampleType, 44);
  return output;
}

function riff(type, children) {
  return containerChunk("RIFF", type, children);
}

function listChunk(type, children) {
  return containerChunk("LIST", type, children);
}

function containerChunk(id, type, children) {
  const body = Buffer.concat([Buffer.from(type, "ascii"), ...children]);
  return chunk(id, body);
}

function chunk(id, body) {
  const padding = body.byteLength % 2 === 0 ? Buffer.alloc(0) : Buffer.alloc(1);
  const header = Buffer.alloc(8);
  header.write(id, 0, 4, "ascii");
  header.writeUInt32LE(body.byteLength, 4);
  return Buffer.concat([header, body, padding]);
}

function findTopLevelList(buffer, type) {
  let offset = 12;
  while (offset + 12 <= buffer.byteLength) {
    const id = buffer.subarray(offset, offset + 4).toString("ascii");
    const byteCount = buffer.readUInt32LE(offset + 4);
    const chunkEnd = offset + 8 + byteCount + (byteCount & 1);
    if (
      id === "LIST"
      && buffer.subarray(offset + 8, offset + 12).toString("ascii") === type
    ) {
      return {
        offset,
        byteCount,
        raw: buffer.subarray(offset, chunkEnd),
      };
    }
    offset = chunkEnd;
  }
  fail(`SoundFont is missing its ${type} LIST.`);
}

function findSubchunk(buffer, listType, chunkID) {
  const list = findTopLevelList(buffer, listType);
  let offset = list.offset + 12;
  const listEnd = list.offset + 8 + list.byteCount;
  while (offset + 8 <= listEnd) {
    const id = buffer.subarray(offset, offset + 4).toString("ascii");
    const byteCount = buffer.readUInt32LE(offset + 4);
    const chunkEnd = offset + 8 + byteCount + (byteCount & 1);
    if (id === chunkID) {
      return {
        offset,
        byteCount,
        body: buffer.subarray(offset + 8, offset + 8 + byteCount),
        raw: buffer.subarray(offset, chunkEnd),
      };
    }
    offset = chunkEnd;
  }
  fail(`SoundFont ${listType} LIST is missing its ${chunkID} chunk.`);
}

function replaceListSubchunk(buffer, listType, chunkID, replacement) {
  const list = findTopLevelList(buffer, listType);
  const children = [];
  let offset = list.offset + 12;
  const listEnd = list.offset + 8 + list.byteCount;
  let didReplace = false;
  while (offset + 8 <= listEnd) {
    const id = buffer.subarray(offset, offset + 4).toString("ascii");
    const byteCount = buffer.readUInt32LE(offset + 4);
    const chunkEnd = offset + 8 + byteCount + (byteCount & 1);
    if (id === chunkID) {
      children.push(replacement);
      didReplace = true;
    } else {
      children.push(buffer.subarray(offset, chunkEnd));
    }
    offset = chunkEnd;
  }
  if (!didReplace) {
    fail(`SoundFont ${listType} LIST is missing its ${chunkID} chunk.`);
  }
  return listChunk(listType, children);
}

function int16LE(values) {
  const output = Buffer.alloc(values.length * 2);
  for (let index = 0; index < values.length; index += 1) {
    output.writeInt16LE(values[index], index * 2);
  }
  return output;
}

function uint16s(values) {
  const output = Buffer.alloc(values.length * 2);
  values.forEach((value, index) => output.writeUInt16LE(value, index * 2));
  return output;
}

function asciiZ(value) {
  const terminated = Buffer.from(`${value}\0`, "ascii");
  return terminated.byteLength % 2 === 0
    ? terminated
    : Buffer.concat([terminated, Buffer.alloc(1)]);
}

function fitASCII(value, length) {
  const output = Buffer.alloc(length);
  Buffer.from(value, "ascii").copy(output, 0, 0, length);
  return output;
}

function cleanASCII(buffer) {
  return buffer.toString("ascii").replace(/\0.*$/s, "").trimEnd();
}

function readUInt24BE(buffer, offset) {
  return (
    buffer[offset] * 0x10000
    + buffer[offset + 1] * 0x100
    + buffer[offset + 2]
  );
}

function clampInt8(value) {
  return Math.max(-128, Math.min(127, value));
}

function midiName(note) {
  const names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  return `${names[note % 12]}${Math.floor(note / 12) - 1}`;
}

function formatBytes(bytes) {
  return `${(bytes / 1024 / 1024).toFixed(1)} MiB`;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
