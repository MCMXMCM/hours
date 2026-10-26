export const minimumCoastVelocity = 40;
export const maximumCoastVelocity = 420;
export const springDuration = 0.9;

const velocitySampleWindow = 120;
const minimumVelocitySampleDuration = 8;
const coastDeceleration = 170;
const minimumCoastDuration = 0.6;
const maximumCoastDuration = 2.8;
const springResponse = 0.48;
const springDamping = 0.72;

function clamp(value, lower, upper) {
  return Math.min(upper, Math.max(lower, value));
}

export function dragRotation(translation, diameter) {
  if (!(diameter > 0)) return 0;
  return (translation / diameter) * (360 / Math.PI);
}

export function releaseAngularVelocity(samples, diameter) {
  if (!(diameter > 0) || samples.length < 2) return 0;

  const latest = samples.at(-1);
  const earliestAllowedTime = latest.time - velocitySampleWindow;
  const earliest =
    samples.find((sample) => sample.time >= earliestAllowedTime) ?? samples[0];
  const elapsed = latest.time - earliest.time;
  if (elapsed < minimumVelocitySampleDuration) return 0;

  const pixelsPerSecond = ((latest.x - earliest.x) / elapsed) * 1_000;
  return clamp(
    dragRotation(pixelsPerSecond, diameter),
    -maximumCoastVelocity,
    maximumCoastVelocity,
  );
}

export function coastDuration(initialVelocity) {
  return clamp(
    Math.abs(initialVelocity) / coastDeceleration,
    minimumCoastDuration,
    maximumCoastDuration,
  );
}

export function coastRotation(
  start,
  initialVelocity,
  elapsed,
  duration,
) {
  if (!(duration > 0)) return start;
  const time = clamp(elapsed, 0, duration);
  const progress = time / duration;
  const distance =
    initialVelocity *
    duration *
    (progress - 0.5 * progress * progress);
  return start + distance;
}

export function springRotation(start, target, elapsed) {
  const time = Math.max(0, elapsed);
  const angularFrequency = (2 * Math.PI) / springResponse;
  const dampedFrequency =
    angularFrequency * Math.sqrt(1 - springDamping * springDamping);
  const decay = Math.exp(-springDamping * angularFrequency * time);
  const dampingAdjustment =
    springDamping / Math.sqrt(1 - springDamping * springDamping);
  const displacement =
    decay *
    (Math.cos(dampedFrequency * time) +
      dampingAdjustment * Math.sin(dampedFrequency * time));

  return target - (target - start) * displacement;
}
