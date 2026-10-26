// The modeled organ, parallel to `ModeledOrgan` and `ModeledOrganRenderer` in
// `HoursApp/ChantPlaybackController.swift`: additive synthesis of one note
// and the silence that follows it.
//
// Swift fills an `AVAudioPCMBuffer` in the engine's format; `render` here
// returns the samples of a format of one channel, which Swift computes in
// `Double` and stores as `Float`, as storing into a `Float32Array` does. On a
// format of more than one channel Swift does not write the same sample to
// every channel: it scales the first by 0.995. That factor is `perspective`
// below, for a caller that fills more than one channel.
//
// `sin` and `cos` are the platform's on either side, and the two may differ
// in the last place of a `Double`.

import type { ChantRegister } from "./options.ts";
import {
  CantorGuideSynthesizer,
  secondsPerBeat,
  type CantorGuidePerformanceEvent,
  type GABCClef,
} from "./performance.ts";
import { int, max, min } from "./swiftNumerics.ts";

const harmonicAmplitudes: readonly number[] = [
  1.0, 0.62, 0.2, 0.077, 0.019, 0.016, 0.024, 0.006, 0.001,
];

export const ModeledOrgan = {
  /** The reverb's wet/dry mix while the organ sounds, as a percentage. */
  reverbWetDryMix: 4,
  harmonicAmplitudes,
};

const attackSeconds = 0.022;
const releaseSeconds = 0.085;
const harmonicPhaseOffset = 0.417;
const outputGain = 0.575_8;

export class ModeledOrganRenderer {
  private readonly sampleRate: number;

  /** `sampleRate` stands for the `AVAudioFormat` Swift is given. */
  constructor(sampleRate: number) {
    this.sampleRate = sampleRate;
  }

  /**
   * The `Float` by which Swift scales a sample as it writes it to `channel`
   * of a buffer of `channelCount` channels: 0.995 for the first channel of
   * several, and otherwise 1. `render` returns the samples before scaling,
   * which are those of a single channel; each written sample is
   * `Math.fround(sample * perspective)`.
   */
  static perspective(channel: number, channelCount: number): number {
    return channelCount > 1 && channel === 0 ? Math.fround(0.995) : 1;
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

    const frequency = CantorGuideSynthesizer.frequency(
      performanceEvent.event,
      transposition,
      clef,
    );
    const attackFrames = max(
      1,
      min(noteFrames, int(attackSeconds * sampleRate)),
    );
    const releaseFrames = max(
      1,
      min(noteFrames, int(releaseSeconds * sampleRate)),
    );

    for (let frame = 0; frame < noteFrames; frame += 1) {
      const time = frame / sampleRate;
      let tone = 0.0;
      for (const [
        index,
        amplitude,
      ] of ModeledOrgan.harmonicAmplitudes.entries()) {
        const harmonic = index + 1;
        const harmonicFrequency = harmonic * frequency;
        if (!(harmonicFrequency < sampleRate * 0.45)) {
          continue;
        }
        const phase =
          2 * Math.PI * harmonicFrequency * time +
          harmonic * harmonicPhaseOffset;
        tone += amplitude * Math.sin(phase);
      }

      const attackProgress = min(1.0, frame / attackFrames);
      const releaseProgress = min(
        1.0,
        (noteFrames - frame - 1) / releaseFrames,
      );
      const attack = 0.5 - 0.5 * Math.cos(Math.PI * attackProgress);
      const release = 0.5 - 0.5 * Math.cos(Math.PI * releaseProgress);
      output[frame] = tone * min(attack, release) * outputGain;
    }
    return output;
  }
}
