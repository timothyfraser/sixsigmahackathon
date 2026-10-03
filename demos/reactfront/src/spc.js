// Individuals (I-MR) control chart statistics. Plain functions, no React,
// so they can be tested without a browser. This file is the graded core:
// change it only with a test that proves the new numbers.

// d2 for a moving range of span 2 (standard SPC constant table).
export const D2 = 1.128

const mean = (xs) => xs.reduce((s, x) => s + x, 0) / xs.length

/**
 * Limits for an individuals chart, estimated from a baseline period only.
 *   center line  = mean of the baseline
 *   sigma-hat    = average moving range / d2   (NOT the raw standard deviation)
 *   UCL / LCL    = center +/- 3 * sigma-hat
 */
export function imrLimits(values, baselineN = values.length) {
  const base = values.slice(0, baselineN)
  if (base.length < 2) throw new Error('Need at least 2 baseline points')
  const ranges = base.slice(1).map((x, i) => Math.abs(x - base[i]))
  const mrBar = mean(ranges)
  const center = mean(base)
  const sigma = mrBar / D2
  return { center, sigma, mrBar, ucl: center + 3 * sigma, lcl: center - 3 * sigma, baselineN: base.length }
}

/** Indices of points strictly outside the limits (Western Electric rule 1). */
export function outOfControl(values, { ucl, lcl }) {
  return values.flatMap((x, i) => (x > ucl || x < lcl ? [i] : []))
}

/** Parse "10.1, 9.8 10.3" into numbers; ignores blanks, rejects junk. */
export function parseValues(text) {
  const parts = text.split(/[\s,;]+/).filter(Boolean)
  const nums = parts.map(Number)
  if (nums.some((n) => !Number.isFinite(n))) throw new Error('Every value must be a number')
  return nums
}
