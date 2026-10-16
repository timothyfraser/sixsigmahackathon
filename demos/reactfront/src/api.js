// The ONLY place the API base URL lives. Set VITE_API_URL in a .env.local
// file (or in the build environment) to point at your deployed API.
export const API_URL = (import.meta.env.VITE_API_URL || 'http://127.0.0.1:8000').replace(/\/$/, '')

async function getJson(path, options) {
  const res = await fetch(`${API_URL}${path}`, options)
  if (!res.ok) throw new Error(`${path} returned HTTP ${res.status}`)
  return res.json()
}

/** GET / on the FastAPI demo. Returns {"message": "FastAPI is running!", "docs": "/docs"}. */
export function checkApi() {
  return getJson('/')
}

/** POST /sum?a=..&b=.. on the FastAPI demo. Returns {"result": a + b}. */
export function sumOnServer(a, b) {
  const q = new URLSearchParams({ a: String(a), b: String(b) })
  return getJson(`/sum?${q}`, { method: 'POST' })
}

// Where your own statistics endpoint slots in. The demo API has no SPC route,
// so App.jsx computes the limits in the browser with src/spc.js. Once your API
// has one (for example POST /spc/imr taking {"values": [...], "baseline_n": 20}),
// call it from App.jsx with this function. It must return the same shape that
// imrLimits() in src/spc.js returns:
//   { center, sigma, mrBar, ucl, lcl, baselineN }
export function limitsOnServer(values, baselineN) {
  return getJson('/spc/imr', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ values, baseline_n: baselineN }),
  })
}
