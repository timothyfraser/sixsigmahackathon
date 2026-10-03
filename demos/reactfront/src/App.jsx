import { useEffect, useMemo, useState } from 'react'
import { imrLimits, outOfControl, parseValues } from './spc.js'
import { API_URL, checkApi } from './api.js'

// Sample data: 20 in-control fill weights (grams), then a drift upward.
const SAMPLE = [
  50.1, 49.8, 50.3, 49.9, 50.0, 50.4, 49.7, 50.2, 50.0, 49.9,
  50.1, 50.3, 49.8, 50.0, 50.2, 49.9, 50.1, 50.0, 49.8, 50.2,
  50.3, 50.5, 50.9, 51.2, 50.4,
].join(', ')

const fmt = (x) => x.toFixed(3)

function ControlChart({ values, limits, flagged }) {
  const W = 640
  const H = 300
  const pad = { l: 16, r: 48, t: 16, b: 28 }
  const lo = Math.min(limits.lcl, ...values)
  const hi = Math.max(limits.ucl, ...values)
  const span = hi - lo || 1
  const y = (v) => pad.t + (H - pad.t - pad.b) * (1 - (v - lo + span * 0.05) / (span * 1.1))
  const x = (i) => pad.l + (W - pad.l - pad.r) * (values.length < 2 ? 0.5 : i / (values.length - 1))
  const bad = new Set(flagged)

  const hline = (v, label, cls) => (
    <g className={cls}>
      <line x1={pad.l} x2={W - pad.r} y1={y(v)} y2={y(v)} />
      <text x={W - pad.r + 4} y={y(v) + 4}>{label}</text>
    </g>
  )

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      role="img"
      aria-label={`Individuals control chart of ${values.length} points, ${flagged.length} outside the control limits`}
    >
      {hline(limits.ucl, 'UCL', 'limit')}
      {hline(limits.center, 'CL', 'center')}
      {hline(limits.lcl, 'LCL', 'limit')}
      {limits.baselineN < values.length && (
        <line
          className="baseline"
          x1={x(limits.baselineN - 0.5)}
          x2={x(limits.baselineN - 0.5)}
          y1={pad.t}
          y2={H - pad.b}
        />
      )}
      <polyline className="series" points={values.map((v, i) => `${x(i)},${y(v)}`).join(' ')} />
      {values.map((v, i) => (
        <circle key={i} cx={x(i)} cy={y(v)} r={bad.has(i) ? 6 : 3.5} className={bad.has(i) ? 'pt out' : 'pt'}>
          <title>{`Point ${i + 1}: ${v}${bad.has(i) ? ' (outside limits)' : ''}`}</title>
        </circle>
      ))}
      <text x={pad.l} y={H - 8} className="axis">point 1</text>
      <text x={W - pad.r} y={H - 8} className="axis" textAnchor="end">{`point ${values.length}`}</text>
    </svg>
  )
}

export default function App() {
  const [text, setText] = useState(SAMPLE)
  const [baselineN, setBaselineN] = useState(20)
  const [api, setApi] = useState({ state: 'checking' })

  useEffect(() => {
    checkApi()
      .then((r) => setApi({ state: 'ok', message: r.message }))
      .catch(() => setApi({ state: 'down' }))
  }, [])

  const result = useMemo(() => {
    try {
      const values = parseValues(text)
      const n = Math.min(Math.max(2, Number(baselineN) || 2), values.length)
      const limits = imrLimits(values, n)
      return { values, limits, flagged: outOfControl(values, limits) }
    } catch (e) {
      return { error: e.message }
    }
  }, [text, baselineN])

  return (
    <main>
      <h1>Control chart demo</h1>
      <p className="lede">
        An individuals (I-MR) chart. The limits come from the first <em>baseline</em> points only:
        center = baseline mean, sigma-hat = average moving range / 1.128,
        limits = center &plusmn; 3 sigma-hat. Red points fall outside the limits.
      </p>

      <p className={`api ${api.state}`} role="status">
        API at <code>{API_URL}</code>:{' '}
        {api.state === 'checking' && 'checking...'}
        {api.state === 'ok' && `connected (${api.message})`}
        {api.state === 'down' && 'not reachable. Limits are computed in the browser either way.'}
      </p>

      <label htmlFor="values">Measurements (comma or space separated)</label>
      <textarea id="values" rows={4} value={text} onChange={(e) => setText(e.target.value)} />

      <label htmlFor="baseline">Baseline points used to set the limits</label>
      <input
        id="baseline"
        type="number"
        min={2}
        value={baselineN}
        onChange={(e) => setBaselineN(e.target.value)}
      />

      {result.error ? (
        <p className="error" role="alert">{result.error}</p>
      ) : (
        <>
          <ControlChart {...result} />
          <dl className="stats">
            <div><dt>Center line</dt><dd>{fmt(result.limits.center)}</dd></div>
            <div><dt>Sigma-hat</dt><dd>{fmt(result.limits.sigma)}</dd></div>
            <div><dt>UCL</dt><dd>{fmt(result.limits.ucl)}</dd></div>
            <div><dt>LCL</dt><dd>{fmt(result.limits.lcl)}</dd></div>
          </dl>
          <p aria-live="polite">
            {result.flagged.length === 0
              ? 'No points outside the limits.'
              : `Outside the limits: point${result.flagged.length > 1 ? 's' : ''} ${result.flagged.map((i) => i + 1).join(', ')}.`}
          </p>
        </>
      )}
    </main>
  )
}
