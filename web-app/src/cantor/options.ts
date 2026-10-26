// The listener's cantor guide options, parallel to `ScholaPitch`,
// `ChantRegister`, and `CantorGuideSound` at the head of
// `HoursApp/ChantPlaybackController.swift`.
//
// Each type is the union of its Swift raw values, since those are what the
// native app stores: `cantorGuide.scholaPitch` and `cantorGuide.register`
// hold an Int, `cantorGuide.sound` a String. The namespace named for the
// plural of a type carries its cases, `allCases`, `init?(rawValue:)` as
// `fromRawValue`, and its computed properties as functions of the same names.

/** The raw value of a `ScholaPitch`, which is also its `semitoneOffset`. */
export type ScholaPitch = 0 | 1 | 2 | 3 | 4 | 5;

const scholaPitchCases = {
  g: 0,
  aFlat: 1,
  a: 2,
  bFlat: 3,
  b: 4,
  c: 5,
} as const satisfies Record<string, ScholaPitch>;

const scholaPitchAllCases: readonly ScholaPitch[] = [
  scholaPitchCases.g,
  scholaPitchCases.aFlat,
  scholaPitchCases.a,
  scholaPitchCases.bFlat,
  scholaPitchCases.b,
  scholaPitchCases.c,
];

export const ScholaPitches = {
  ...scholaPitchCases,

  allCases: scholaPitchAllCases,

  /** `ScholaPitch(rawValue:)`. */
  fromRawValue(rawValue: number): ScholaPitch | null {
    return scholaPitchAllCases.find((pitch) => pitch === rawValue) ?? null;
  },

  id(pitch: ScholaPitch): number {
    return pitch;
  },

  displayName(pitch: ScholaPitch): string {
    switch (pitch) {
      case scholaPitchCases.g:
        return "G";
      case scholaPitchCases.aFlat:
        return "A♭";
      case scholaPitchCases.a:
        return "A";
      case scholaPitchCases.bFlat:
        return "B♭";
      case scholaPitchCases.b:
        return "B";
      case scholaPitchCases.c:
        return "C";
    }
  },

  semitoneOffset(pitch: ScholaPitch): number {
    return pitch;
  },
};

/** The raw value of a `ChantRegister`: `low` is 0 and `high` is 1. */
export type ChantRegister = 0 | 1;

const chantRegisterCases = {
  low: 0,
  high: 1,
} as const satisfies Record<string, ChantRegister>;

const chantRegisterAllCases: readonly ChantRegister[] = [
  chantRegisterCases.low,
  chantRegisterCases.high,
];

export const ChantRegisters = {
  ...chantRegisterCases,

  allCases: chantRegisterAllCases,

  /** `ChantRegister(rawValue:)`. */
  fromRawValue(rawValue: number): ChantRegister | null {
    return (
      chantRegisterAllCases.find((register) => register === rawValue) ?? null
    );
  },

  id(register: ChantRegister): number {
    return register;
  },

  displayName(register: ChantRegister): string {
    switch (register) {
      case chantRegisterCases.low:
        return "Low";
      case chantRegisterCases.high:
        return "High";
    }
  },

  octaveOffset(register: ChantRegister): number {
    switch (register) {
      case chantRegisterCases.low:
        return -12;
      case chantRegisterCases.high:
        return 0;
    }
  },
};

export type CantorGuideSound = "harp" | "organ" | "simpleTone";

const cantorGuideSoundAllCases: readonly CantorGuideSound[] = [
  "harp",
  "organ",
  "simpleTone",
];

export const CantorGuideSounds = {
  allCases: cantorGuideSoundAllCases,

  /** `CantorGuideSound(rawValue:)`. */
  fromRawValue(rawValue: string): CantorGuideSound | null {
    return cantorGuideSoundAllCases.find((sound) => sound === rawValue) ?? null;
  },

  id(sound: CantorGuideSound): string {
    return sound;
  },

  displayName(sound: CantorGuideSound): string {
    switch (sound) {
      case "harp":
        return "Harp";
      case "organ":
        return "Organ";
      case "simpleTone":
        return "Tone";
    }
  },
};

// The values `ChantPlaybackController` holds before a listener chooses.

export const defaultScholaPitch: ScholaPitch = ScholaPitches.a;
export const defaultChantRegister: ChantRegister = ChantRegisters.low;
export const defaultCantorGuideSound: CantorGuideSound = "organ";
