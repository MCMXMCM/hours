// The room in which the guide sounds.
//
// The native app passes the guide through `AVAudioUnitReverb`'s medium-room
// preset, mixed very low. A browser has no such preset, so the room is
// described here as an impulse response: a short, dense decay whose upper
// partials die away first. It is an approximation of that room, not a
// measurement of it, and at the guide's mix (a few parts in a hundred) it
// serves only to keep the notes from sounding bare.

const decaySeconds = 0.72;
const tailSeconds = 0.9;
const preDelaySeconds = 0.008;
/** Where the tail's brightness begins and ends, as one-pole coefficients. */
const openingBrightness = 0.55;
const closingBrightness = 0.12;

/** A small generator with a fixed seed: the room is the same on every visit. */
function generator(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let mixed = state;
    mixed = Math.imul(mixed ^ (mixed >>> 15), mixed | 1);
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> 7), mixed | 61);
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4_294_967_296;
  };
}

/** One channel of the room's response at a sample rate. */
export function mediumRoomResponse(
  sampleRate: number,
  channel: number,
): Float32Array<ArrayBuffer> {
  const length = Math.max(1, Math.floor(tailSeconds * sampleRate));
  const preDelay = Math.floor(preDelaySeconds * sampleRate);
  const response = new Float32Array(length);
  const random = generator(0x9e3779b9 + channel * 0x85ebca6b);
  let smoothed = 0;
  for (let frame = preDelay; frame < length; frame += 1) {
    const elapsed = (frame - preDelay) / sampleRate;
    const progress = (frame - preDelay) / Math.max(1, length - preDelay);
    const brightness =
      openingBrightness + (closingBrightness - openingBrightness) * progress;
    smoothed += brightness * (random() * 2 - 1 - smoothed);
    // Sixty decibels of decay over `decaySeconds`.
    response[frame] =
      smoothed * Math.exp((-6.907_755 * elapsed) / decaySeconds);
  }
  return response;
}

/** The room as a buffer a `ConvolverNode` can hold. */
export function mediumRoomImpulse(context: BaseAudioContext): AudioBuffer {
  const sampleRate = context.sampleRate;
  const left = mediumRoomResponse(sampleRate, 0);
  const right = mediumRoomResponse(sampleRate, 1);
  const impulse = context.createBuffer(2, left.length, sampleRate);
  impulse.copyToChannel(left, 0);
  impulse.copyToChannel(right, 1);
  return impulse;
}
