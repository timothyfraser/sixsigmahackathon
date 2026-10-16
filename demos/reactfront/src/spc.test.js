import { describe, it, expect } from 'vitest'
import { imrLimits, outOfControl, parseValues, D2 } from './spc.js'

describe('imrLimits', () => {
  it('matches a hand-worked case', () => {
    // 1..5: mean 3, every moving range is 1, so sigma-hat = 1 / 1.128
    const l = imrLimits([1, 2, 3, 4, 5])
    expect(l.center).toBeCloseTo(3, 10)
    expect(l.mrBar).toBeCloseTo(1, 10)
    expect(l.sigma).toBeCloseTo(1 / D2, 10)
    expect(l.ucl).toBeCloseTo(3 + 3 / D2, 10) // 5.6596
    expect(l.lcl).toBeCloseTo(3 - 3 / D2, 10) // 0.3404
  })

  it('degenerate case: constant data has zero spread and no flags', () => {
    const xs = [7, 7, 7, 7, 7]
    const l = imrLimits(xs)
    expect(l.sigma).toBe(0)
    expect(outOfControl(xs, l)).toEqual([])
  })

  it('uses only the baseline, so a planted shift is flagged where it was put', () => {
    const base = [10, 10.2, 9.9, 10.1, 9.8, 10, 10.2, 9.9, 10.1, 10]
    const xs = [...base, 10.1, 12.5, 10]
    const l = imrLimits(xs, base.length)
    expect(outOfControl(xs, l)).toEqual([11])
  })
})

describe('parseValues', () => {
  it('accepts commas, spaces and newlines', () => {
    expect(parseValues('1, 2\n3 4')).toEqual([1, 2, 3, 4])
  })
  it('rejects non-numbers', () => {
    expect(() => parseValues('1, two')).toThrow()
  })
})
