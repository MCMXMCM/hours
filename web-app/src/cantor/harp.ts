// The sampled harp, parallel to `SampledHarpRenderer` in
// `HoursApp/ChantPlaybackController.swift`.
//
// Natively two sampler voices play a sound bank, each note struck on the
// voice the last one left free, and the engine is rendered offline into the
// note's buffer. A browser has no sampler, so the bank is rendered ahead of
// time, by the same sampler at the same velocity and tuning, into one
// recording for each key: the key struck and left to ring. A voice here is a
// place in such a recording, and everything done to the rendered frames (the
// crossfade between voices, the articulation, the limiting) is the native
// arithmetic in `harpEnvelope.ts`.

import { retryingFetch } from "@/data/retryingFetch.ts";
import { SampledHarp } from "./harpEnvelope.ts";
import type { ChantRegister } from "./options.ts";
import type { CantorGuidePerformanceEvent, GABCClef } from "./performance.ts";

/** The recordings of the harp's keys. */
export interface HarpBank {
  /**
   * Makes ready the recording of each key, at the context's sample rate.
   * Rejects when a key cannot be had.
   */
  prepare(
    midiNotes: readonly number[],
    context: BaseAudioContext,
  ): Promise<void>;
  /** A key's recording, or `null` if it has not been made ready. */
  note(midiNote: number): Float32Array | null;
}

/** A sounding sampler voice: a recording, and how far into it the voice is. */
interface Voice {
  readonly recording: Float32Array;
  position: number;
}

/** Copies frames of a recording, which is silent beyond its end. */
function frames(
  recording: Float32Array,
  start: number,
  count: number,
): Float32Array {
  const copied = new Float32Array(count);
  if (start < recording.length) {
    copied.set(
      recording.subarray(start, Math.min(recording.length, start + count)),
    );
  }
  return copied;
}

export class SampledHarpRenderer {
  private readonly sampleRate: number;
  private readonly recording: (midiNote: number) => Float32Array | null;
  private currentVoice: Voice | null = null;

  constructor(
    sampleRate: number,
    recording: (midiNote: number) => Float32Array | null,
  ) {
    this.sampleRate = sampleRate;
    this.recording = recording;
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
    const { noteFrames, silenceFrames, totalFrames } = SampledHarp.frames(
      performanceEvent,
      tempo,
      sampleRate,
    );
    const output = new Float32Array(totalFrames);

    if (performanceEvent.startsPhrase) {
      this.currentVoice = null;
    }

    const midiNote = SampledHarp.midiNote(
      performanceEvent.event,
      transposition,
      clef,
    );
    const recording = this.recording(midiNote);
    if (recording === null) {
      throw new Error(`The harp has no recording of key ${midiNote}.`);
    }
    let writeOffset = 0;

    const oldVoice = this.currentVoice;
    const newVoice: Voice = { recording, position: 0 };
    this.currentVoice = newVoice;

    if (oldVoice !== null) {
      const transitionFrames = SampledHarp.transitionFrames(
        noteFrames,
        sampleRate,
      );
      SampledHarp.renderCrossfade(
        transitionFrames,
        frames(oldVoice.recording, oldVoice.position, transitionFrames),
        frames(recording, 0, transitionFrames),
        output,
        sampleRate,
      );
      writeOffset = transitionFrames;
    }

    if (writeOffset < recording.length) {
      output.set(
        recording.subarray(writeOffset, Math.min(recording.length, noteFrames)),
        writeOffset,
      );
    }
    newVoice.position = noteFrames;

    // A released voice is silent, so the frames after the note stay empty.
    const shouldRelease = SampledHarp.shouldRelease(
      performanceEvent,
      silenceFrames,
    );
    if (shouldRelease) {
      this.currentVoice = null;
    }

    SampledHarp.applyArticulationEnvelope(
      output,
      noteFrames,
      performanceEvent,
      shouldRelease,
      sampleRate,
    );
    return output;
  }
}

/** What `harp/manifest.json` says of the recordings beside it. */
export interface HarpManifest {
  readonly schema: 1;
  /**
   * The directory, beside the manifest, that holds the recordings. It is
   * named for what they were rendered from, so a recording never changes.
   */
  readonly directory: string;
  /** The file extension of each recording. */
  readonly format: string;
  /** The lowest and highest key recorded; every key between them is. */
  readonly lowestNote: number;
  readonly highestNote: number;
  /** The sound bank the recordings were rendered from. */
  readonly soundBankSHA256: string;
}

type Fetcher = (input: string) => Promise<Response>;

/** The harp's recordings, fetched as they are first needed. */
export class FetchedHarpBank implements HarpBank {
  private readonly baseURL: string;
  private readonly fetcher: Fetcher;
  private manifest: Promise<HarpManifest> | null = null;
  private sampleRate = 0;
  private readonly recordings = new Map<number, Float32Array>();
  private readonly pending = new Map<number, Promise<void>>();

  private readonly keepsAtHand: boolean;
  private isKeeping = false;

  /**
   * `keepsAtHand` has the bank fetch every recording once the harp has first
   * been played, so that it can be played afterwards without a connection.
   */
  constructor(
    baseURL: string,
    options: { fetcher?: Fetcher; keepsAtHand?: boolean } = {},
  ) {
    this.baseURL = baseURL.endsWith("/") ? baseURL : `${baseURL}/`;
    this.fetcher = options.fetcher ?? retryingFetch;
    this.keepsAtHand = options.keepsAtHand ?? false;
  }

  note(midiNote: number): Float32Array | null {
    return this.recordings.get(midiNote) ?? null;
  }

  async prepare(
    midiNotes: readonly number[],
    context: BaseAudioContext,
  ): Promise<void> {
    if (context.sampleRate !== this.sampleRate) {
      // Recordings are decoded at the output's rate; another output needs its own.
      this.recordings.clear();
      this.pending.clear();
      this.sampleRate = context.sampleRate;
    }
    const manifest = await this.loadManifest();
    await Promise.all(
      midiNotes.map((midiNote) => this.load(midiNote, manifest, context)),
    );
    if (this.keepsAtHand && !this.isKeeping) {
      this.isKeeping = true;
      void this.keepAtHand().catch(() => {
        this.isKeeping = false;
      });
    }
  }

  /** Fetches every recording, so the harp can be played without a connection. */
  async keepAtHand(): Promise<void> {
    const manifest = await this.loadManifest();
    for (
      let midiNote = manifest.lowestNote;
      midiNote <= manifest.highestNote;
      midiNote += 1
    ) {
      if (this.recordings.has(midiNote)) continue;
      const response = await this.fetcher(this.url(midiNote, manifest));
      // The service worker keeps what was fetched; the bytes are not needed yet.
      await response.arrayBuffer();
    }
  }

  private loadManifest(): Promise<HarpManifest> {
    this.manifest ??= this.fetcher(`${this.baseURL}manifest.json`)
      .then((response) => {
        if (!response.ok)
          throw new Error(`The harp's manifest answered ${response.status}.`);
        return response.json() as Promise<HarpManifest>;
      })
      .catch((error: unknown) => {
        this.manifest = null;
        throw error;
      });
    return this.manifest;
  }

  private url(midiNote: number, manifest: HarpManifest): string {
    return `${this.baseURL}${manifest.directory}/${midiNote}.${manifest.format}`;
  }

  private load(
    midiNote: number,
    manifest: HarpManifest,
    context: BaseAudioContext,
  ): Promise<void> {
    if (this.recordings.has(midiNote)) return Promise.resolve();
    const existing = this.pending.get(midiNote);
    if (existing) return existing;
    if (midiNote < manifest.lowestNote || midiNote > manifest.highestNote) {
      return Promise.reject(
        new Error(`The harp has no recording of key ${midiNote}.`),
      );
    }
    const sampleRate = context.sampleRate;
    const loading = this.fetcher(this.url(midiNote, manifest))
      .then((response) => {
        if (!response.ok)
          throw new Error(`Key ${midiNote} answered ${response.status}.`);
        return response.arrayBuffer();
      })
      .then((bytes) => context.decodeAudioData(bytes))
      .then((decoded) => {
        if (sampleRate !== this.sampleRate) return;
        this.recordings.set(midiNote, decoded.getChannelData(0).slice());
      })
      .finally(() => {
        this.pending.delete(midiNote);
      });
    this.pending.set(midiNote, loading);
    return loading;
  }
}
