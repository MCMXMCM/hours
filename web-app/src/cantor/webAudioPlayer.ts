// The cantor guide's sound, made with the Web Audio API. It stands where
// `ChantAudioPlayer` does in `HoursApp/ChantPlaybackController.swift`: each
// note is rendered to a buffer of its own and the buffers are played end to
// end, a few of them always scheduled ahead of the note being heard.
//
// What the native player does to avoid a click is kept: a start fades in and
// a stop fades out over a fiftieth of a second, a new start lets the old
// sound fade before it speaks, and the output is put to rest while idle.

import type {
  CantorAudioEvent,
  CantorAudioPlayer,
  CantorAudioSettings,
  CantorAudioStart,
} from "./controller.ts";
import { HarpSoundBank, SampledHarp } from "./harpEnvelope.ts";
import type { HarpBank } from "./harp.ts";
import { SampledHarpRenderer } from "./harp.ts";
import type { CantorGuideSound } from "./options.ts";
import { ModeledOrgan, ModeledOrganRenderer } from "./organ.ts";
import type { CantorGuidePerformanceEvent } from "./performance.ts";
import { PitchPipeRenderer } from "./pitchPipe.ts";
import { mediumRoomImpulse } from "./reverb.ts";

/** `ChantPlaybackFade`: the length of a fade in or out. */
const fadeSeconds = 0.02;
/** An approach to the new level that has all but arrived when the fade ends. */
const fadeTimeConstant = fadeSeconds / 4;
/** How far ahead the first note is placed when the output was at rest. */
const wakingLeadSeconds = 0.06;
/** `drainSilentOutput`: a cycle of silence between a fade out and the next note. */
const drainSeconds = 0.012;
/** A note that could not be scheduled in time is placed this far ahead. */
const lateLeadSeconds = 0.03;
/** How long the output is left running after a stop, in milliseconds. */
const restDelay = 120;
/** How long a browser is given to start its output, in milliseconds. */
const resumeTimeout = 4_000;

/** The errors `CantorGuideAudioError` names, in the same words. */
export class CantorGuideAudioError extends Error {
  static outputUnavailable(): CantorGuideAudioError {
    return new CantorGuideAudioError("No audio output is currently available.");
  }

  static soundBankUnavailable(): CantorGuideAudioError {
    return new CantorGuideAudioError(
      "The harp sound bank could not be loaded.",
    );
  }
}

interface GuideRenderer {
  render(
    performanceEvent: CantorGuidePerformanceEvent,
    tempo: number,
    transposition: number,
    clef: CantorAudioSettings["clef"],
    register: CantorAudioSettings["register"],
  ): Float32Array<ArrayBuffer>;
}

/** One performance's own path to the output, so that it can fade alone. */
interface Run {
  readonly generation: number;
  readonly input: GainNode;
  readonly gate: GainNode;
  readonly sources: Set<AudioBufferSourceNode>;
  readonly renderer: GuideRenderer;
  /** When the run's first frame sounds, on the context's clock. */
  origin: number;
  /** The frames scheduled since `origin`. */
  frames: number;
}

type AudioContextConstructor = new (
  options?: AudioContextOptions,
) => AudioContext;

function audioContextConstructor(): AudioContextConstructor | null {
  const scope = globalThis as unknown as {
    AudioContext?: AudioContextConstructor;
    webkitAudioContext?: AudioContextConstructor;
  };
  return scope.AudioContext ?? scope.webkitAudioContext ?? null;
}

/**
 * Safari on iPhone and iPad plays Web Audio as ambient sound, which the
 * Ring/Silent switch mutes. The guide asks to be played as media, as the
 * native player's `.playback` session is, so that it sounds through the
 * switch. Safari has offered this since 16.4; elsewhere there is nothing
 * to ask.
 */
function preferPlaybackSession(): void {
  const session = (
    globalThis.navigator as
      | (Navigator & { audioSession?: { type: string } })
      | undefined
  )?.audioSession;
  if (!session || session.type === "playback") return;
  try {
    session.type = "playback";
  } catch {
    // A session that will not be set plays as it did.
  }
}

/** The reverb's share of the output for a sound, from its percentage. */
function reverbMix(sound: CantorGuideSound): number {
  switch (sound) {
    case "harp":
      return HarpSoundBank.reverbWetDryMix / 100;
    case "organ":
      return ModeledOrgan.reverbWetDryMix / 100;
    case "simpleTone":
      return 0;
  }
}

export class WebAudioCantorPlayer implements CantorAudioPlayer {
  onInterruption: (() => void) | null = null;

  private readonly harpBank: HarpBank | null;
  private context: AudioContext | null = null;
  private impulse: AudioBuffer | null = null;
  private run: Run | null = null;
  private generation = 0;
  private restTimer: ReturnType<typeof setTimeout> | undefined;
  /** True while this player has itself asked the output to rest. */
  private isResting = false;

  constructor(harpBank: HarpBank | null = null) {
    this.harpBank = harpBank;
  }

  async start(request: CantorAudioStart): Promise<void> {
    const generation = (this.generation += 1);
    clearTimeout(this.restTimer);
    // Asked for while the tap that started the guide is still being handled.
    preferPlaybackSession();
    try {
      const existing = this.context;
      const context = this.audioContext();
      // An output only now created, or brought back from rest, is waking.
      const wasRunning = context === existing && context.state === "running";
      if (context.state !== "running") {
        this.isResting = false;
        await resumed(context);
      }
      if (generation !== this.generation) return;

      if (request.sound === "harp") {
        await this.prepareHarp(request, context);
        if (generation !== this.generation) return;
      }

      const now = context.currentTime;
      const previous = this.run;
      this.run = null;
      // Keep the output awake across neume taps; what was sounding fades,
      // and the new performance waits for it.
      let lead = wakingLeadSeconds;
      if (previous !== null) {
        this.silence(previous, now);
        lead = fadeSeconds + drainSeconds;
      } else if (wasRunning) {
        lead = drainSeconds;
      }

      const run = this.makeRun(context, request.sound, generation, now + lead);
      this.run = run;
      request.events.forEach((event, position) => {
        this.scheduleImmediately(run, event, request, () =>
          request.completion(position),
        );
      });
      run.gate.gain.setTargetAtTime(1, run.origin, fadeTimeConstant);
    } catch (error) {
      if (generation === this.generation) this.stop();
      throw error;
    }
  }

  schedule(request: CantorAudioEvent): void {
    const run = this.run;
    if (run === null) return;
    try {
      this.scheduleImmediately(run, request.event, request, request.completion);
    } catch {
      request.completion();
    }
  }

  stop(): void {
    this.generation += 1;
    const context = this.context;
    const run = this.run;
    this.run = null;
    if (context === null) return;
    if (run !== null) this.silence(run, context.currentTime);
    // Silence the hardware as well as the player while idle, retaining the
    // context for the next start.
    clearTimeout(this.restTimer);
    this.restTimer = setTimeout(() => {
      if (this.run !== null || context.state !== "running") return;
      this.isResting = true;
      void context.suspend().catch(() => undefined);
    }, restDelay);
  }

  // MARK: Output

  private audioContext(): AudioContext {
    if (this.context !== null && this.context.state !== "closed")
      return this.context;
    const AudioContextClass = audioContextConstructor();
    if (AudioContextClass === null)
      throw CantorGuideAudioError.outputUnavailable();
    let context: AudioContext;
    try {
      context = new AudioContextClass({ latencyHint: "interactive" });
    } catch {
      throw CantorGuideAudioError.outputUnavailable();
    }
    context.addEventListener("statechange", () => {
      // An output taken away while a performance is sounding ends it, as an
      // interruption or a lost route does natively.
      if (context.state === "running" || this.isResting || this.run === null)
        return;
      this.onInterruption?.();
    });
    this.context = context;
    this.impulse = null;
    return context;
  }

  private makeRun(
    context: AudioContext,
    sound: CantorGuideSound,
    generation: number,
    origin: number,
  ): Run {
    const input = context.createGain();
    const gate = context.createGain();
    gate.gain.value = 0;
    gate.connect(context.destination);

    const mix = reverbMix(sound);
    const dry = context.createGain();
    dry.gain.value = 1 - mix;
    input.connect(dry).connect(gate);
    if (mix > 0) {
      const reverb = context.createConvolver();
      reverb.buffer = this.impulse ??= mediumRoomImpulse(context);
      const wet = context.createGain();
      wet.gain.value = mix;
      input.connect(reverb).connect(wet).connect(gate);
    }

    return {
      generation,
      input,
      gate,
      sources: new Set(),
      renderer: this.makeRenderer(sound, context.sampleRate),
      origin,
      frames: 0,
    };
  }

  private makeRenderer(
    sound: CantorGuideSound,
    sampleRate: number,
  ): GuideRenderer {
    switch (sound) {
      case "harp": {
        const bank = this.harpBank;
        if (bank === null) throw CantorGuideAudioError.soundBankUnavailable();
        return new SampledHarpRenderer(sampleRate, (midiNote) =>
          bank.note(midiNote),
        );
      }
      case "organ":
        return new ModeledOrganRenderer(sampleRate);
      case "simpleTone":
        return new PitchPipeRenderer(sampleRate);
    }
  }

  private async prepareHarp(
    request: CantorAudioStart,
    context: AudioContext,
  ): Promise<void> {
    if (this.harpBank === null)
      throw CantorGuideAudioError.soundBankUnavailable();
    const midiNotes = new Set<number>();
    for (const performed of request.timeline) {
      midiNotes.add(
        SampledHarp.midiNote(
          performed.event,
          request.transposition,
          request.clef,
        ),
      );
    }
    try {
      await this.harpBank.prepare([...midiNotes], context);
    } catch {
      throw CantorGuideAudioError.soundBankUnavailable();
    }
  }

  private scheduleImmediately(
    run: Run,
    event: CantorGuidePerformanceEvent,
    settings: CantorAudioSettings,
    completion: () => void,
  ): void {
    const context = this.context;
    if (context === null) throw CantorGuideAudioError.outputUnavailable();
    const samples = run.renderer.render(
      event,
      settings.tempo,
      settings.transposition,
      settings.clef,
      settings.register,
    );
    const buffer = context.createBuffer(1, samples.length, context.sampleRate);
    buffer.copyToChannel(samples, 0);
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(run.input);

    let startTime = run.origin + run.frames / context.sampleRate;
    if (startTime < context.currentTime) {
      // The page was held up for longer than the notes scheduled ahead.
      // Begin again a moment from now rather than overlap the note before.
      run.origin = context.currentTime + lateLeadSeconds;
      run.frames = 0;
      startTime = run.origin;
    }
    run.frames += samples.length;
    run.sources.add(source);
    source.onended = () => {
      run.sources.delete(source);
      source.disconnect();
      if (run.generation !== this.generation) return;
      this.whenHeard(context, run, completion);
    };
    source.start(startTime);
  }

  /**
   * A buffer has ended on the context's clock a little before its last
   * frame leaves the loudspeaker. The native player is told when the data
   * has been played back; this waits out the same latency.
   */
  private whenHeard(
    context: AudioContext,
    run: Run,
    completion: () => void,
  ): void {
    const latency = Number.isFinite(context.outputLatency)
      ? context.outputLatency
      : 0;
    if (
      latency < 0.004 ||
      (typeof document !== "undefined" && document.hidden)
    ) {
      completion();
      return;
    }
    setTimeout(() => {
      if (run.generation === this.generation) completion();
    }, latency * 1_000);
  }

  /** Fades a run to silence and lets it go. */
  private silence(run: Run, now: number): void {
    run.gate.gain.cancelScheduledValues(now);
    run.gate.gain.setTargetAtTime(0, now, fadeTimeConstant);
    const end = now + fadeSeconds + drainSeconds;
    for (const source of run.sources) {
      source.onended = null;
      try {
        source.stop(end);
      } catch {
        // A source that never started has nothing to stop.
      }
    }
    run.sources.clear();
    setTimeout(
      () => {
        run.gate.disconnect();
        run.input.disconnect();
      },
      (fadeSeconds + drainSeconds) * 1_000 + 50,
    );
  }
}

/** Starts a context's output, or fails as the native engine does without one. */
async function resumed(context: AudioContext): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(CantorGuideAudioError.outputUnavailable()),
      resumeTimeout,
    );
  });
  try {
    await Promise.race([context.resume(), expired]);
  } catch (error) {
    if (error instanceof CantorGuideAudioError) throw error;
    throw CantorGuideAudioError.outputUnavailable();
  } finally {
    clearTimeout(timer);
  }
  if (context.state !== "running")
    throw CantorGuideAudioError.outputUnavailable();
}
