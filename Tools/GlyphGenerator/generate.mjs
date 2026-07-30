#!/usr/bin/env node

// Converts the pinned Exsurge SVG catalog into a platform-neutral Swift
// display list. Run through `make generate-glyphs`; do not hand-edit output.

import fs from "node:fs";
import path from "node:path";

const [, , inputArgument, outputArgument] = process.argv;
if (!inputArgument || !outputArgument) {
  throw new Error("usage: generate.mjs Exsurge.Glyphs.js GeneratedGregorianGlyphCatalog.swift");
}

const inputPath = path.resolve(inputArgument);
const outputPath = path.resolve(outputArgument);
const source = fs.readFileSync(inputPath, "utf8");
const marker = "export let Glyphs =";
const markerIndex = source.indexOf(marker);
if (markerIndex < 0) throw new Error("Glyphs export not found");
const objectSource = source.slice(markerIndex + marker.length, source.lastIndexOf("};") + 1);
const glyphs = Function(`"use strict"; return (${objectSource});`)();

const commandSizes = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
const numberPattern = "[-+]?(?:(?:\\d*\\.\\d+)|(?:\\d+\\.?))(?:[eE][-+]?\\d+)?";
const tokenPattern = new RegExp(`[AaCcHhLlMmQqSsTtVvZz]|${numberPattern}`, "g");

function point(x, y) {
  return { x, y };
}

function reflect(control, around) {
  return point(2 * around.x - control.x, 2 * around.y - control.y);
}

function vectorAngle(ux, uy, vx, vy) {
  const dot = ux * vx + uy * vy;
  const magnitude = Math.hypot(ux, uy) * Math.hypot(vx, vy);
  const cosine = Math.max(-1, Math.min(1, dot / magnitude));
  const sign = ux * vy - uy * vx < 0 ? -1 : 1;
  return sign * Math.acos(cosine);
}

function arcCubics(start, rxInput, ryInput, rotationDegrees, largeArc, sweep, end) {
  let rx = Math.abs(rxInput);
  let ry = Math.abs(ryInput);
  if (rx === 0 || ry === 0 || (start.x === end.x && start.y === end.y)) return [];

  const rotation = rotationDegrees * Math.PI / 180;
  const cosRotation = Math.cos(rotation);
  const sinRotation = Math.sin(rotation);
  const halfDX = (start.x - end.x) / 2;
  const halfDY = (start.y - end.y) / 2;
  const xPrime = cosRotation * halfDX + sinRotation * halfDY;
  const yPrime = -sinRotation * halfDX + cosRotation * halfDY;

  const lambda = xPrime * xPrime / (rx * rx) + yPrime * yPrime / (ry * ry);
  if (lambda > 1) {
    const scale = Math.sqrt(lambda);
    rx *= scale;
    ry *= scale;
  }

  const rx2 = rx * rx;
  const ry2 = ry * ry;
  const numerator = Math.max(0, rx2 * ry2 - rx2 * yPrime * yPrime - ry2 * xPrime * xPrime);
  const denominator = rx2 * yPrime * yPrime + ry2 * xPrime * xPrime;
  const coefficient = (largeArc === sweep ? -1 : 1) * Math.sqrt(numerator / denominator);
  const centerPrimeX = coefficient * rx * yPrime / ry;
  const centerPrimeY = coefficient * -ry * xPrime / rx;
  const centerX = cosRotation * centerPrimeX - sinRotation * centerPrimeY + (start.x + end.x) / 2;
  const centerY = sinRotation * centerPrimeX + cosRotation * centerPrimeY + (start.y + end.y) / 2;

  const ux = (xPrime - centerPrimeX) / rx;
  const uy = (yPrime - centerPrimeY) / ry;
  const vx = (-xPrime - centerPrimeX) / rx;
  const vy = (-yPrime - centerPrimeY) / ry;
  let theta = vectorAngle(1, 0, ux, uy);
  let delta = vectorAngle(ux, uy, vx, vy);
  if (!sweep && delta > 0) delta -= Math.PI * 2;
  if (sweep && delta < 0) delta += Math.PI * 2;

  const segmentCount = Math.ceil(Math.abs(delta) / (Math.PI / 2));
  const segmentDelta = delta / segmentCount;
  const result = [];
  function transform(x, y) {
    return point(
      centerX + cosRotation * rx * x - sinRotation * ry * y,
      centerY + sinRotation * rx * x + cosRotation * ry * y
    );
  }
  for (let index = 0; index < segmentCount; index += 1) {
    const nextTheta = theta + segmentDelta;
    const alpha = 4 / 3 * Math.tan(segmentDelta / 4);
    const cosTheta = Math.cos(theta);
    const sinTheta = Math.sin(theta);
    const cosNext = Math.cos(nextTheta);
    const sinNext = Math.sin(nextTheta);
    result.push({
      control1: transform(cosTheta - alpha * sinTheta, sinTheta + alpha * cosTheta),
      control2: transform(cosNext + alpha * sinNext, sinNext - alpha * cosNext),
      end: transform(cosNext, sinNext)
    });
    theta = nextTheta;
  }
  return result;
}

function parsePath(data) {
  if (!data) return [];
  const tokens = data.match(tokenPattern) ?? [];
  const output = [];
  let tokenIndex = 0;
  let command = "";
  let current = point(0, 0);
  let subpathStart = current;
  let previousCubicControl = null;
  let previousQuadraticControl = null;

  while (tokenIndex < tokens.length) {
    if (/^[A-Za-z]$/.test(tokens[tokenIndex])) command = tokens[tokenIndex++];
    if (!command) throw new Error(`Path begins without command: ${data}`);
    const upper = command.toUpperCase();
    if (upper === "Z") {
      output.push({ type: "close" });
      current = subpathStart;
      previousCubicControl = null;
      previousQuadraticControl = null;
      command = "";
      continue;
    }

    const arity = commandSizes[upper];
    if (tokenIndex + arity > tokens.length) throw new Error(`Incomplete ${command} command`);
    const values = tokens.slice(tokenIndex, tokenIndex + arity).map(Number);
    tokenIndex += arity;
    const relative = command === command.toLowerCase();
    const absolutePoint = (x, y) => point(
      relative ? current.x + x : x,
      relative ? current.y + y : y
    );

    if (upper === "M") {
      current = absolutePoint(values[0], values[1]);
      output.push({ type: "move", end: current });
      subpathStart = current;
      command = relative ? "l" : "L";
    } else if (upper === "L") {
      current = absolutePoint(values[0], values[1]);
      output.push({ type: "line", end: current });
    } else if (upper === "H") {
      current = point(relative ? current.x + values[0] : values[0], current.y);
      output.push({ type: "line", end: current });
    } else if (upper === "V") {
      current = point(current.x, relative ? current.y + values[0] : values[0]);
      output.push({ type: "line", end: current });
    } else if (upper === "C") {
      const control1 = absolutePoint(values[0], values[1]);
      const control2 = absolutePoint(values[2], values[3]);
      const end = absolutePoint(values[4], values[5]);
      output.push({ type: "cubic", control1, control2, end });
      current = end;
      previousCubicControl = control2;
    } else if (upper === "S") {
      const control1 = previousCubicControl ? reflect(previousCubicControl, current) : current;
      const control2 = absolutePoint(values[0], values[1]);
      const end = absolutePoint(values[2], values[3]);
      output.push({ type: "cubic", control1, control2, end });
      current = end;
      previousCubicControl = control2;
    } else if (upper === "Q") {
      const control = absolutePoint(values[0], values[1]);
      const end = absolutePoint(values[2], values[3]);
      output.push({ type: "quadratic", control, end });
      current = end;
      previousQuadraticControl = control;
    } else if (upper === "T") {
      const control = previousQuadraticControl ? reflect(previousQuadraticControl, current) : current;
      const end = absolutePoint(values[0], values[1]);
      output.push({ type: "quadratic", control, end });
      current = end;
      previousQuadraticControl = control;
    } else if (upper === "A") {
      const end = absolutePoint(values[5], values[6]);
      const cubics = arcCubics(current, values[0], values[1], values[2], values[3] !== 0, values[4] !== 0, end);
      if (cubics.length === 0) output.push({ type: "line", end });
      else for (const cubic of cubics) output.push({ type: "cubic", ...cubic });
      current = end;
      previousCubicControl = cubics.at(-1)?.control2 ?? null;
    }

    if (upper !== "C" && upper !== "S" && upper !== "A") previousCubicControl = null;
    if (upper !== "Q" && upper !== "T") previousQuadraticControl = null;
  }
  return output;
}

function swiftNumber(value) {
  if (!Number.isFinite(value)) throw new Error(`Non-finite value ${value}`);
  const normalized = Math.abs(value) < 1e-10 ? 0 : value;
  return Number(normalized.toFixed(6)).toString();
}

function swiftPoint(value) {
  return `CGPoint(x: ${swiftNumber(value.x)}, y: ${swiftNumber(value.y)})`;
}

function swiftCommand(command) {
  switch (command.type) {
    case "move": return `.move(${swiftPoint(command.end)})`;
    case "line": return `.line(${swiftPoint(command.end)})`;
    case "quadratic":
      return `.quadratic(control: ${swiftPoint(command.control)}, end: ${swiftPoint(command.end)})`;
    case "cubic":
      return `.cubic(control1: ${swiftPoint(command.control1)}, control2: ${swiftPoint(command.control2)}, end: ${swiftPoint(command.end)})`;
    case "close": return ".close";
    default: throw new Error(`Unknown command ${command.type}`);
  }
}

function swiftCase(name) {
  return name[0].toLowerCase() + name.slice(1);
}

const definitions = Object.entries(glyphs).map(([name, glyph]) => {
  const paths = glyph.paths.map(pathDefinition => parsePath(pathDefinition.data));
  const renderedPaths = paths.map(commands =>
    `[\n${commands.map(command => `                    ${swiftCommand(command)}`).join(",\n")}\n                ]`
  ).join(",\n                ");
  return `        .${swiftCase(name)}: GregorianGlyphDefinition(
            paths: [
                ${renderedPaths}
            ],
            bounds: CGRect(x: ${swiftNumber(glyph.bounds.x)}, y: ${swiftNumber(glyph.bounds.y)}, width: ${swiftNumber(glyph.bounds.width)}, height: ${swiftNumber(glyph.bounds.height)}),
            origin: ${swiftPoint(glyph.origin)},
            alignment: .${glyph.align}
        )`;
});

const output = `// Generated by Tools/GlyphGenerator/generate.mjs from Exsurge.Glyphs.js.
// Source revision: 0c39f61df0e7c843f467250976338cac62f94e62
// Exsurge is Copyright (c) 2008-2016 Fr. Matthew Spencer, OSJ, MIT License.
// Do not hand-edit.

import CoreGraphics

extension GregorianGlyphCatalog {
    static let definitions: [GregorianGlyphName: GregorianGlyphDefinition] = [
${definitions.join(",\n")}
    ]
}
`;

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, output);
console.log(`Generated ${Object.keys(glyphs).length} glyphs at ${outputPath}`);
