// Swift's numeric behaviour where JavaScript's differs, for the arithmetic
// ported from `HoursApp/ChantPlaybackController.swift`. Swift's `Double` is a
// JavaScript number; its `Float` is a number passed through `Math.fround`, or
// stored in a `Float32Array`.

/**
 * `max(_:_:)`, which Swift defines as `y >= x ? y : x`. A NaN in second place
 * therefore yields the first argument, where `Math.max` yields NaN: it is
 * this that clamps an invalid tempo to a finite duration.
 */
export function max(x: number, y: number): number {
  return y >= x ? y : x;
}

/** `min(_:_:)`, which Swift defines as `y < x ? y : x`. */
export function min(x: number, y: number): number {
  return y < x ? y : x;
}

/**
 * `Int(_:)` of a `Double`, which truncates toward zero. (Swift traps on a
 * value that is not finite or lies beyond `Int`; none arises from a finite
 * tempo, weight, and sample rate.)
 */
export function int(value: number): number {
  const truncated = Math.trunc(value);
  return truncated === 0 ? 0 : truncated;
}
