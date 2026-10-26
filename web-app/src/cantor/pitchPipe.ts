// The simple tone, parallel to `PitchPipeRenderer` in
// `HoursApp/ChantPlaybackController.swift`: a few harmonics of one
// oscillator, whose phase and frequency pass from each note to the next so
// that a phrase is one unbroken sound.
//
// Swift writes the same sample to every channel of its buffer, so the single
// channel `render` returns is the faithful equivalent. Each sample is
// computed in `Double` and stored as `Float`, as storing into a
// `Float32Array` does.
//
// The renderer is stateful. Its notes must be rendered in the order in which
// they sound, and a renderer must not be shared between two performances.
//
// `sin`, `cos`, and `pow` are the platform's on either side, and the two may
// differ in the last place of a `Double`.

import type { ChantRegister } from "./options.ts";
import {
  CantorGuideSynthesizer,
  secondsPerBeat,
  type CantorGuidePerformanceEvent,
  type GABCClef,
} from "./performance.ts";
import { int, max, min } from "./swiftNumerics.ts";

const transitionSeconds = 0.018;
const phraseAttackSeconds = 0.045;
const phraseReleaseSeconds = 0.08;
const syllablePulseSeconds = 0.018;
const harmonicAmplitudes: readonly number[] = [1.0, 0.22, 0.1, 0.045, 0.02];
const harmonicAmplitudeTotal = harmonicAmplitudes.reduce(
  (total, amplitude) => total + amplitude,
  0,
);
const outputGain = 0.62 / harmonicAmplitudeTotal;

function smoothTransition(
  start: number,
  end: number,
  progress: number,
): number {
  const clamped = min(1, max(0, progress));
  const eased = 0.5 - 0.5 * Math.cos(Math.PI * clamped);
  return start + (end - start) * eased;
}

export class PitchPipeRenderer {
  private readonly sampleRate: number;
  private phase = 0.0;
  private previousFrequency: number | null = null;

  /** `sampleRate` stands for the `AVAudioFormat` Swift is given. */
  constructor(sampleRate: number) {
    this.sampleRate = sampleRate;
  }

  /** The note followed by its silence, as the samples of one channel. */
  render(
    performanceEvent: CantorGuidePerformanceEvent,
    tempo: number,
    transposition: number,
    clef: GABCClef,
    _register: ChantRegister,
  ): Float32Array<ArrayBuffer> {
    const sampleRate = this.sampleRate;
    const safeTempo = max(0.1, tempo);
    const noteSeconds = max(
      0.09,
      (secondsPerBeat * performanceEvent.durationWeight) / safeTempo,
    );
    const silenceSeconds =
      (secondsPerBeat * performanceEvent.followingSilenceWeight) / safeTempo;
    const noteFrames = max(1, int(noteSeconds * sampleRate));
    const silenceFrames = max(0, int(silenceSeconds * sampleRate));
    const totalFrames = max(1, noteFrames + silenceFrames);
    // A new array is silent, so the frames after the note need no writing.
    const output = new Float32Array(totalFrames);

    if (performanceEvent.startsPhrase) {
      this.phase = 0;
      this.previousFrequency = null;
    }
    const targetFrequency = CantorGuideSynthesizer.frequency(
      performanceEvent.event,
      transposition,
      clef,
    );
    const startingFrequency = this.previousFrequency ?? targetFrequency;
    const transitionFrames =
      startingFrequency === targetFrequency
        ? 0
        : min(noteFrames, max(1, int(transitionSeconds * sampleRate)));
    const shouldRelease = performanceEvent.endsPhrase || silenceFrames > 0;
    const startLevel = performanceEvent.startsPhrase
      ? 0.0
      : performanceEvent.startsSyllable
        ? 0.88
        : 1.0;
    const endLevel = shouldRelease
      ? 0.0
      : performanceEvent.endsSyllable
        ? 0.88
        : 1.0;
    const attackSeconds =
      startLevel === 0 ? phraseAttackSeconds : syllablePulseSeconds;
    const releaseSeconds =
      endLevel === 0 ? phraseReleaseSeconds : syllablePulseSeconds;
    const attackFrames = max(
      1,
      min(int(noteFrames / 3), int(attackSeconds * sampleRate)),
    );
    const releaseFrames = max(
      1,
      min(int(noteFrames / 3), int(releaseSeconds * sampleRate)),
    );

    for (let frame = 0; frame < noteFrames; frame += 1) {
      const transitionProgress =
        transitionFrames === 0 ? 1.0 : min(1.0, frame / transitionFrames);
      const frequency = smoothTransition(
        startingFrequency,
        targetFrequency,
        transitionProgress,
      );
      this.phase += (2 * Math.PI * frequency) / sampleRate;
      if (this.phase >= 2 * Math.PI) {
        // `formTruncatingRemainder(dividingBy:)`.
        this.phase %= 2 * Math.PI;
      }

      let tone = 0.0;
      for (const [index, amplitude] of harmonicAmplitudes.entries()) {
        const harmonic = index + 1;
        if (!(harmonic * frequency < sampleRate * 0.48)) {
          continue;
        }
        tone += amplitude * Math.sin(harmonic * this.phase);
      }

      const attackProgress = min(1.0, frame / attackFrames);
      const releaseProgress = min(
        1.0,
        (noteFrames - frame - 1) / releaseFrames,
      );
      const attack = smoothTransition(startLevel, 1, attackProgress);
      const release = smoothTransition(endLevel, 1, releaseProgress);
      output[frame] = tone * min(attack, release) * outputGain;
    }

    this.previousFrequency = shouldRelease ? null : targetFrequency;
    return output;
  }
}
