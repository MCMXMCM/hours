// The cantor guide's controller, parallel to `ChantPlaybackController` in
// `HoursApp/ChantPlaybackController.swift`: what is playing, which note is
// being sung, and the listener's options. The sound itself is made by a
// `CantorAudioPlayer`, which stands where `ChantAudioPlayer` does natively.

import { Preferences, preferenceKeys } from "@/app/preferences.ts";
import { Store } from "@/app/store.ts";
import type { ChantEvent, ChantScore } from "@/core/models.ts";
import {
  ChantRegisters,
  CantorGuideSounds,
  ScholaPitches,
  defaultCantorGuideSound,
  defaultChantRegister,
  defaultScholaPitch,
  type CantorGuideSound,
  type ChantRegister,
  type ScholaPitch,
} from "./options.ts";
import {
  CantorGuideSynthesizer,
  GABCClefs,
  type CantorGuidePerformanceEvent,
  type GABCClef,
} from "./performance.ts";

/** What every note of one performance is rendered with. */
export interface CantorAudioSettings {
  readonly tempo: number;
  readonly transposition: number;
  readonly clef: GABCClef;
  readonly register: ChantRegister;
}

export interface CantorAudioStart extends CantorAudioSettings {
  /** The first notes, to be scheduled at once and in order. */
  readonly events: readonly CantorGuidePerformanceEvent[];
  readonly sound: CantorGuideSound;
  /**
   * Every note the performance may go on to ask for, so that a sound which
   * must be fetched can be made ready before the first note is heard.
   */
  readonly timeline: readonly CantorGuidePerformanceEvent[];
  /** Called with a note's position among `events` once it has been heard. */
  readonly completion: (position: number) => void;
}

export interface CantorAudioEvent extends CantorAudioSettings {
  readonly event: CantorGuidePerformanceEvent;
  /** Called once the note has been heard, or cannot be played. */
  readonly completion: () => void;
}

export interface CantorAudioPlayer {
  /** Replaces whatever is sounding with these notes. */
  start(request: CantorAudioStart): Promise<void>;
  /** Appends a note to those already scheduled. */
  schedule(request: CantorAudioEvent): void;
  stop(): void;
  /** Called when the output was taken away; see `ChantPlaybackController`. */
  onInterruption: (() => void) | null;
}

export interface ChantPlaybackState {
  readonly isPlaying: boolean;
  readonly currentEventID: string | null;
  readonly preparedScoreID: string | null;
  readonly errorMessage: string | null;
  readonly tempo: number;
  readonly scholaPitch: ScholaPitch;
  readonly chantRegister: ChantRegister;
  readonly guideSound: CantorGuideSound;
  readonly loopsPhrase: boolean;
}

const scheduledBufferWindow = 8;

export class ChantPlaybackController {
  static readonly defaultTempo = 1.0;
  static readonly tempoRange = {
    lowerBound: 0.65,
    upperBound: 1.45,
    step: 0.05,
  } as const;
  static readonly scholaPitchKey = preferenceKeys.scholaPitch;
  static readonly chantRegisterKey = preferenceKeys.chantRegister;
  static readonly guideSoundKey = preferenceKeys.guideSound;

  readonly store: Store<ChantPlaybackState>;

  private readonly audioPlayer: CantorAudioPlayer;
  private readonly preferences: Preferences;
  private activeScore: ChantScore | null = null;
  private activeStartEventID: string | null = null;
  private playsSingleNote = false;
  // A lesson can keep related examples on the same pitch reference.
  // This is session state, never part of the persisted Office score format.
  private pitchReference: ChantScore | null = null;
  private playbackID: symbol | null = null;

  constructor(audioPlayer: CantorAudioPlayer, preferences: Preferences) {
    this.audioPlayer = audioPlayer;
    this.preferences = preferences;

    let guideSound = defaultCantorGuideSound;
    const rawSound = preferences.string(ChantPlaybackController.guideSoundKey);
    const savedSound =
      rawSound === null ? null : CantorGuideSounds.fromRawValue(rawSound);
    if (savedSound !== null) guideSound = savedSound;

    let scholaPitch = defaultScholaPitch;
    if (preferences.has(ChantPlaybackController.scholaPitchKey)) {
      const savedPitch = ScholaPitches.fromRawValue(
        integer(preferences, ChantPlaybackController.scholaPitchKey),
      );
      if (savedPitch !== null) scholaPitch = savedPitch;
    }

    let chantRegister = defaultChantRegister;
    if (preferences.has(ChantPlaybackController.chantRegisterKey)) {
      const savedRegister = ChantRegisters.fromRawValue(
        integer(preferences, ChantPlaybackController.chantRegisterKey),
      );
      if (savedRegister !== null) chantRegister = savedRegister;
    }

    this.store = new Store<ChantPlaybackState>({
      isPlaying: false,
      currentEventID: null,
      preparedScoreID: null,
      errorMessage: null,
      tempo: ChantPlaybackController.defaultTempo,
      scholaPitch,
      chantRegister,
      guideSound,
      loopsPhrase: false,
    });

    // The native controller watches for an interruption, a lost route, and a
    // reset of the media services; here the player reports the same.
    audioPlayer.onInterruption = () => this.invalidateEngineConfiguration();
  }

  // MARK: State

  get isPlaying(): boolean {
    return this.store.value.isPlaying;
  }

  get currentEventID(): string | null {
    return this.store.value.currentEventID;
  }

  get preparedScoreID(): string | null {
    return this.store.value.preparedScoreID;
  }

  get errorMessage(): string | null {
    return this.store.value.errorMessage;
  }

  get tempo(): number {
    return this.store.value.tempo;
  }

  set tempo(tempo: number) {
    this.store.update({ tempo });
  }

  get scholaPitch(): ScholaPitch {
    return this.store.value.scholaPitch;
  }

  set scholaPitch(scholaPitch: ScholaPitch) {
    if (scholaPitch === this.scholaPitch) return;
    this.store.update({ scholaPitch });
    this.preferences.set(ChantPlaybackController.scholaPitchKey, scholaPitch);
    this.restartAfterGuideSelectionChange();
  }

  get chantRegister(): ChantRegister {
    return this.store.value.chantRegister;
  }

  set chantRegister(chantRegister: ChantRegister) {
    if (chantRegister === this.chantRegister) return;
    this.store.update({ chantRegister });
    this.preferences.set(
      ChantPlaybackController.chantRegisterKey,
      chantRegister,
    );
    this.restartAfterGuideSelectionChange();
  }

  get guideSound(): CantorGuideSound {
    return this.store.value.guideSound;
  }

  set guideSound(guideSound: CantorGuideSound) {
    if (guideSound === this.guideSound) return;
    this.store.update({ guideSound });
    this.preferences.set(ChantPlaybackController.guideSoundKey, guideSound);
    this.restartAfterGuideSelectionChange();
  }

  get loopsPhrase(): boolean {
    return this.store.value.loopsPhrase;
  }

  set loopsPhrase(loopsPhrase: boolean) {
    this.store.update({ loopsPhrase });
  }

  get targetDominantOffset(): number {
    return (
      ScholaPitches.semitoneOffset(this.scholaPitch) +
      ChantRegisters.octaveOffset(this.chantRegister)
    );
  }

  // MARK: Playback

  prepare(score: ChantScore, pitchReference: ChantScore | null = null): void {
    if (this.preparedScoreID !== score.id) {
      this.stop();
      this.activeStartEventID = null;
    }
    this.pitchReference = pitchReference;
    this.activeScore = score;
    this.store.update({ errorMessage: null, preparedScoreID: score.id });
  }

  toggle(score: ChantScore): void {
    if (this.isPlaying && this.preparedScoreID === score.id) {
      this.stop();
    } else {
      this.play(
        score,
        this.preparedScoreID === score.id ? this.activeStartEventID : null,
      );
    }
  }

  play(score: ChantScore, fromEventID: string | null = null): void {
    this.playFrom(score, fromEventID, false);
  }

  playNote(score: ChantScore, eventID: string): void {
    this.playFrom(score, eventID, true);
  }

  private playFrom(
    score: ChantScore,
    fromEventID: string | null,
    singleNote: boolean,
  ): void {
    if (this.preparedScoreID !== score.id) {
      this.pitchReference = null;
    }
    this.playbackID = null;
    this.activeScore = score;
    this.activeStartEventID = fromEventID;
    this.playsSingleNote = singleNote;

    const selectedEvents = singleNote
      ? score.timeline.events.filter((event) => event.id === fromEventID)
      : this.selectedEvents(score, fromEventID);
    const timeline = CantorGuideSynthesizer.performance(selectedEvents, score);
    if (timeline.length === 0) {
      this.audioPlayer.stop();
      this.store.update({
        isPlaying: false,
        currentEventID: null,
        preparedScoreID: score.id,
        errorMessage: "This chant has no playable notes.",
      });
      return;
    }

    const tempoAtStart = this.tempo;
    const clefAtStart = GABCClefs.fromGABC(score.gabc);
    const reference = this.pitchReference ?? score;
    const transpositionAtStart = CantorGuideSynthesizer.centeredTransposition(
      reference.timeline.events,
      this.targetDominantOffset,
      GABCClefs.fromGABC(reference.gabc),
    );
    const registerAtStart = this.chantRegister;
    const soundAtStart = this.guideSound;
    const loopsAtStart = this.loopsPhrase && !singleNote;
    const playbackID = Symbol("playback");
    this.playbackID = playbackID;
    const settings: CantorAudioSettings = {
      tempo: tempoAtStart,
      transposition: transpositionAtStart,
      clef: clefAtStart,
      register: registerAtStart,
    };

    const initialBufferCount = loopsAtStart
      ? scheduledBufferWindow
      : Math.min(scheduledBufferWindow, timeline.length);
    const initialEvents: CantorGuidePerformanceEvent[] = [];
    for (let position = 0; position < initialBufferCount; position += 1) {
      const event = eventAt(position, timeline, loopsAtStart);
      if (event !== null) initialEvents.push(event);
    }
    this.store.update({
      isPlaying: true,
      errorMessage: null,
      preparedScoreID: score.id,
      currentEventID: timeline[0].event.id,
    });

    // As natively, the output starts on a later turn: of several requests
    // made together, only the last reaches the player.
    queueMicrotask(() => {
      if (this.playbackID !== playbackID) return;
      this.audioPlayer
        .start({
          ...settings,
          events: initialEvents,
          sound: soundAtStart,
          timeline,
          completion: (position) =>
            this.didFinishEvent(
              position,
              timeline,
              loopsAtStart,
              playbackID,
              settings,
            ),
        })
        .catch((error: unknown) => {
          if (this.playbackID !== playbackID) return;
          this.playbackID = null;
          this.store.update({
            isPlaying: false,
            currentEventID: null,
            errorMessage: `Couldn\u{2019}t start audio output. ${localizedDescription(error)}`,
          });
        });
    });
  }

  restartIfPlaying(score: ChantScore): void {
    if (!(this.isPlaying && this.preparedScoreID === score.id)) return;
    this.playFrom(score, this.activeStartEventID, this.playsSingleNote);
  }

  private restartAfterGuideSelectionChange(): void {
    if (!this.isPlaying || this.activeScore === null) return;
    this.playFrom(
      this.activeScore,
      this.activeStartEventID,
      this.playsSingleNote,
    );
  }

  stop(): void {
    this.playbackID = null;
    this.store.update({ isPlaying: false, currentEventID: null });
    this.audioPlayer.stop();
  }

  private selectedEvents(
    score: ChantScore,
    fromEventID: string | null,
  ): ChantEvent[] {
    const events = score.timeline.events;
    const found =
      fromEventID === null
        ? -1
        : events.findIndex((event) => event.id === fromEventID);
    const startIndex = found >= 0 ? found : 0;
    if (!(startIndex < events.length)) return [];
    const remaining = events.slice(startIndex);
    if (!this.loopsPhrase) return remaining;
    const phraseID = remaining[0].phraseID;
    const end = remaining.findIndex((event) => event.phraseID !== phraseID);
    return end < 0 ? remaining : remaining.slice(0, end);
  }

  private schedule(
    position: number,
    timeline: readonly CantorGuidePerformanceEvent[],
    loops: boolean,
    playbackID: symbol,
    settings: CantorAudioSettings,
  ): void {
    const event = eventAt(position, timeline, loops);
    if (event === null) return;
    this.audioPlayer.schedule({
      ...settings,
      event,
      completion: () =>
        this.didFinishEvent(position, timeline, loops, playbackID, settings),
    });
  }

  private didFinishEvent(
    position: number,
    timeline: readonly CantorGuidePerformanceEvent[],
    loops: boolean,
    playbackID: symbol,
    settings: CantorAudioSettings,
  ): void {
    if (this.playbackID !== playbackID) return;

    const nextPosition = position + 1;
    const nextEvent = eventAt(nextPosition, timeline, loops);
    if (nextEvent === null) {
      this.stop();
      return;
    }

    this.store.update({ currentEventID: nextEvent.event.id });
    this.schedule(
      position + scheduledBufferWindow,
      timeline,
      loops,
      playbackID,
      settings,
    );
  }

  private invalidateEngineConfiguration(): void {
    this.playbackID = null;
    this.store.update({ isPlaying: false, currentEventID: null });
    this.audioPlayer.stop();
  }
}

function eventAt(
  position: number,
  timeline: readonly CantorGuidePerformanceEvent[],
  loops: boolean,
): CantorGuidePerformanceEvent | null {
  if (!(position >= 0) || timeline.length === 0) return null;
  if (loops) return timeline[position % timeline.length];
  return position < timeline.length ? timeline[position] : null;
}

/** `UserDefaults.integer(forKey:)`: zero for what is not a number. */
function integer(preferences: Preferences, key: string): number {
  const value = Number(preferences.string(key));
  return Number.isFinite(value) ? Math.trunc(value) : 0;
}

function localizedDescription(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
