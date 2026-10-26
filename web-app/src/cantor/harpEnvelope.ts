// What is pure in the sampled harp, parallel to `HarpSoundBank` and to the
// arithmetic of `SampledHarpRenderer` in
// `HoursApp/ChantPlaybackController.swift`.
//
// The harp itself is a sound bank played by two alternating sampler voices,
// which belong to whoever plays the samples. What is here is the rest: how
// many frames a note and its silence occupy, which key is struck, how one
// voice gives way to the next, and the articulation and limiting applied to
// the finished note.
//
// A buffer is the samples of one channel, or one `Float32Array` for each
// channel of an `AVAudioPCMBuffer`, all of one length; it is altered in
// place. Swift takes the peak across every channel and scales them alike, so
// a harp of several channels should be passed whole.
//
// `Float` arithmetic is reproduced with `Math.fround` and by storing into a
// `Float32Array`. `sin` and `cos` are the platform's on either side, and the
// two may differ in the last place of a `Double`.

import type { ChantEvent } from "@/core/models.ts";
import {
  CantorGuideSynthesizer,
  secondsPerBeat,
  type CantorGuidePerformanceEvent,
  type GABCClef,
} from "./performance.ts";
import { int, max, min } from "./swiftNumerics.ts";

export const HarpSoundBank = {
  resourceName: "ConcertHarp",
  program: 0,
  /** The samplers' global tuning, in cents. */
  tuningCorrection: 7,
  /** The reverb's wet/dry mix while the harp sounds, as a percentage. */
  reverbWetDryMix: 10,
  sha256: "ac8aeee47a423c3cfaa3ccc17cca2eef1ca0dc86a7c3a1cfd4334f1afe4c4c37",
};

/** The samples of one channel, or of each channel in turn. */
export type SampledHarpBuffer = Float32Array | readonly Float32Array[];

/** The frames `SampledHarpRenderer.render` allots to a note. */
export interface SampledHarpFrames {
  readonly noteFrames: number;
  readonly silenceFrames: number;
  readonly totalFrames: number;
}

/** One step of the crossfade, across which each voice holds one volume. */
export interface SampledHarpCrossfadeStep {
  readonly writeOffset: number;
  readonly frameCount: number;
  /** The `Float` volume of the voice that gives way. */
  readonly oldVoiceVolume: number;
  /** The `Float` volume of the voice that enters. */
  readonly newVoiceVolume: number;
}

const transitionSeconds = 0.018;
const phraseAttackSeconds = 0.006;
const phraseReleaseSeconds = 0.08;
const syllablePulseSeconds = 0.006;
const outputGain = 2.4;
const peakLimit = Math.fround(0.9);

function channels(buffer: SampledHarpBuffer): readonly Float32Array[] {
  return buffer instanceof Float32Array ? [buffer] : buffer;
}

function frameLength(buffer: readonly Float32Array[]): number {
  return buffer.length === 0 ? 0 : buffer[0].length;
}

function smoothTransition(
  start: number,
  end: number,
  progress: number,
): number {
  const clamped = min(1, max(0, progress));
  const eased = 0.5 - 0.5 * Math.cos(Math.PI * clamped);
  return start + (end - start) * eased;
}

function limitPeak(buffer: SampledHarpBuffer): void {
  const all = channels(buffer);
  const length = frameLength(all);
  let peak = 0;
  for (const samples of all) {
    for (let frame = 0; frame < length; frame += 1) {
      peak = max(peak, Math.abs(samples[frame]));
    }
  }
  if (!(peak > peakLimit)) return;
  const gain = Math.fround(peakLimit / peak);
  for (const samples of all) {
    for (let frame = 0; frame < length; frame += 1) {
      samples[frame] *= gain;
    }
  }
}

function crossfadeSteps(
  requestedFrames: number,
  sampleRate: number,
): SampledHarpCrossfadeStep[] {
  const steps: SampledHarpCrossfadeStep[] = [];
  if (!(requestedFrames > 0)) return steps;
  const rampStepFrames = max(1, min(requestedFrames, int(sampleRate * 0.001)));
  let writeOffset = 0;
  while (writeOffset < requestedFrames) {
    const frameCount = min(rampStepFrames, requestedFrames - writeOffset);
    const midpoint = writeOffset + frameCount * 0.5;
    const progress = min(1, midpoint / requestedFrames);
    steps.push({
      writeOffset,
      frameCount,
      oldVoiceVolume: Math.fround(Math.cos(progress * Math.PI * 0.5)),
      newVoiceVolume: Math.fround(Math.sin(progress * Math.PI * 0.5)),
    });
    writeOffset += frameCount;
  }
  return steps;
}

export const SampledHarp = {
  secondsPerBeat,
  /** How long one voice takes to give way to the next. */
  transitionSeconds,
  phraseAttackSeconds,
  phraseReleaseSeconds,
  syllablePulseSeconds,
  outputGain,
  /** A `Float`. */
  peakLimit,
  /** The velocity with which every note is struck. */
  noteVelocity: 58,

  /**
   * The frames of a note and of the silence after it, as `render` first
   * computes them. Every guide sound allots a note the same frames.
   */
  frames(
    performanceEvent: CantorGuidePerformanceEvent,
    tempo: number,
    sampleRate: number,
  ): SampledHarpFrames {
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
    return { noteFrames, silenceFrames, totalFrames };
  },

  /** The MIDI key `render` strikes for an event: G4, 67, at no offset. */
  midiNote(event: ChantEvent, transposition: number, clef: GABCClef): number {
    const semitoneOffset = CantorGuideSynthesizer.semitoneOffset(event, clef);
    return min(127, max(0, 67 + semitoneOffset + transposition));
  },

  /** The frames across which the voice of the preceding note gives way. */
  transitionFrames(noteFrames: number, sampleRate: number): number {
    return min(noteFrames, max(1, int(transitionSeconds * sampleRate)));
  },

  /**
   * Whether the note's voice is silenced when the note ends, rather than
   * left sounding to be crossfaded into the next.
   */
  shouldRelease(
    performanceEvent: CantorGuidePerformanceEvent,
    silenceFrames: number,
  ): boolean {
    return performanceEvent.endsPhrase || silenceFrames > 0;
  },

  /**
   * The volumes `renderCrossfade` gives the two voices: an equal-power curve
   * held in steps of a millisecond, each at the value of its midpoint.
   */
  crossfadeSteps,

  /**
   * Mixes the first `requestedFrames` frames of two voices into `output`,
   * the old voice giving way to the new. Swift sets the volume of each
   * voice's mixer for a step and has the engine render it; here each voice
   * is given as the samples it would have rendered at full volume, and the
   * mixers' work is done in `Float`.
   */
  renderCrossfade(
    requestedFrames: number,
    oldVoice: Float32Array,
    newVoice: Float32Array,
    output: Float32Array,
    sampleRate: number,
  ): void {
    for (const step of crossfadeSteps(requestedFrames, sampleRate)) {
      const end = step.writeOffset + step.frameCount;
      for (let frame = step.writeOffset; frame < end; frame += 1) {
        output[frame] =
          Math.fround(oldVoice[frame] * step.oldVoiceVolume) +
          Math.fround(newVoice[frame] * step.newVoiceVolume);
      }
    }
  },

  /**
   * Shapes a rendered note: the attack and release of a phrase, the lighter
   * pulse of a syllable, silence after the note, the output gain, and then
   * `limitPeak`.
   */
  applyArticulationEnvelope(
    buffer: SampledHarpBuffer,
    noteFrames: number,
    performanceEvent: CantorGuidePerformanceEvent,
    shouldRelease: boolean,
    sampleRate: number,
  ): void {
    const all = channels(buffer);
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

    const length = frameLength(all);
    for (let frame = 0; frame < length; frame += 1) {
      let envelope: number;
      if (frame < noteFrames) {
        const attackProgress = min(1.0, frame / attackFrames);
        const releaseProgress = min(
          1.0,
          (noteFrames - frame - 1) / releaseFrames,
        );
        const attack = smoothTransition(startLevel, 1, attackProgress);
        const release = smoothTransition(endLevel, 1, releaseProgress);
        envelope = min(attack, release);
      } else {
        envelope = 0;
      }
      const gain = Math.fround(envelope * outputGain);
      for (const samples of all) {
        samples[frame] *= gain;
      }
    }
    limitPeak(all);
  },

  limitPeak,

  smoothTransition,
};
