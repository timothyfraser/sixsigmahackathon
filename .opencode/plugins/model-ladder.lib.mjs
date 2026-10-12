// Pure logic for the model ladder. No OpenCode imports, so tests can load it with plain Node.
// Edit LADDER to change the order. First = tried first. Never add a Gemma model:
// Gemma's 16K tokens-per-minute cap is smaller than one OpenCode request.

export const LADDER = [
  // flash-lite: about 500 requests per day each (newest first)
  "google/gemini-3.5-flash-lite",
  "google/gemini-3.1-flash-lite",
  "google/gemini-3.1-flash-lite-preview",
  // flash: about 20 requests per day each, last resorts (newest first)
  "google/gemini-3.8-flash",
  "google/gemini-3.7-flash",
  "google/gemini-3.6-flash",
  "google/gemini-3.5-flash",
  "google/gemini-3-flash-preview",
];

// A 429 that asks us to wait longer than this is treated as a daily limit.
export const LONG_WAIT_SECONDS = 10 * 60;

// Pacific calendar day, e.g. "2026-10-11". Google resets daily quotas at midnight Pacific.
export function pacificDay(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
}

function asText(err) {
  if (err == null) return "";
  if (typeof err === "string") return err;
  try { return JSON.stringify(err); } catch { return String(err); }
}

// Longest wait the error asks for, in seconds ("retry in 1h1m15s", "retryDelay": "3675s").
export function retrySeconds(text) {
  let best = 0;
  for (const m of text.matchAll(/retry in ((?:\d+(?:\.\d+)?[hms])+)/gi)) {
    let s = 0;
    for (const p of m[1].matchAll(/(\d+(?:\.\d+)?)([hms])/gi)) {
      s += parseFloat(p[1]) * ({ h: 3600, m: 60, s: 1 })[p[2].toLowerCase()];
    }
    best = Math.max(best, s);
  }
  for (const m of text.matchAll(/retryDelay\\*"?\s*:\s*\\*"(\d+(?:\.\d+)?)s/gi)) {
    best = Math.max(best, parseFloat(m[1]));
  }
  return best;
}

// "daily"  -> switch to the next rung
// "minute" -> leave it to OpenCode's own retry
// "other"  -> not ours (503 high demand, auth, ...)
export function classify(err) {
  const text = asText(err);
  const is429 = /\b429\b|RESOURCE_EXHAUSTED|provider\.quota|QuotaExceeded|quota/i.test(text);
  if (!is429) return "other";
  if (/\b503\b|high demand|UNAVAILABLE/i.test(text) && !/\b429\b|RESOURCE_EXHAUSTED/.test(text)) return "other";
  if (/PerDay|per day|RequestsPerDay|requests_per_day/i.test(text)) return "daily";
  if (retrySeconds(text) > LONG_WAIT_SECONDS) return "daily";
  return "minute";
}

// Model named in Google's quota message ("model: gemini-3.1-flash-lite"), as "google/<id>".
export function modelFromError(err) {
  const m = asText(err).match(/model:\s*\\?"?([a-z0-9][a-z0-9.\-]*)/i);
  return m ? `google/${m[1]}` : null;
}

// Next usable rung after `current`: first the rungs below it, then wrap around to the
// rungs above it (a higher rung has its own fresh daily budget). Skips exhausted rungs and
// `current` itself. null = every other rung is used up.
export function nextModel(current, exhausted = [], ladder = LADDER) {
  const dead = new Set([...exhausted, current]);
  const start = ladder.indexOf(current);
  if (start === -1) return firstLive([...dead], ladder);
  for (let k = 1; k < ladder.length; k++) {
    const m = ladder[(start + k) % ladder.length];
    if (!dead.has(m)) return m;
  }
  return null;
}

// First live rung (for a session that starts on a model already used up today).
export function firstLive(exhausted = [], ladder = LADDER) {
  const dead = new Set(exhausted);
  return ladder.find((m) => !dead.has(m)) ?? null;
}

// Offset of Pacific wall-clock time from UTC at `at`, in ms (e.g. -7 h in summer).
function pacificOffsetMs(at) {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles", hourCycle: "h23", year: "numeric", month: "2-digit",
    day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(at).map((x) => [x.type, Number(x.value)]));
  const wall = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return wall - Math.floor(at.getTime() / 1000) * 1000;
}

// The next midnight Pacific after `now` (Google's daily reset), as a Date.
export function nextMidnightPacific(now = new Date()) {
  const [y, m, d] = pacificDay(now).split("-").map(Number);
  const wallMidnight = Date.UTC(y, m - 1, d + 1);
  let t = wallMidnight - pacificOffsetMs(now);
  t = wallMidnight - pacificOffsetMs(new Date(t)); // re-check across a daylight-saving change
  return new Date(t);
}

// When a used-up model comes back: now + the wait Google asked for, but never later than
// the next midnight Pacific. No wait in the error -> midnight Pacific.
export function expiryFor(err, now = new Date()) {
  const midnight = nextMidnightPacific(now);
  const s = retrySeconds(asText(err));
  if (s > 0) return new Date(Math.min(now.getTime() + s * 1000, midnight.getTime()));
  return midnight;
}

// State file: { "version": 2, "exhausted": { "google/<id>": "<ISO time it comes back>" } }.
// Returns the rungs still used up at `now`. The old { day, exhausted: [..] } format counts
// as used up until the end of that Pacific day.
export function exhaustedNow(state, now = new Date()) {
  if (!state) return [];
  if (Array.isArray(state.exhausted)) {
    return state.day === pacificDay(now) ? state.exhausted : [];
  }
  const map = state.exhausted && typeof state.exhausted === "object" ? state.exhausted : {};
  return Object.keys(map).filter((ref) => Date.parse(map[ref]) > now.getTime());
}

// New state with `ref` used up until `until`; expired entries are dropped.
export function markInState(state, ref, until, now = new Date()) {
  const out = {};
  const old = state && !Array.isArray(state.exhausted) && state.exhausted ? state.exhausted : {};
  for (const [k, v] of Object.entries(old)) if (Date.parse(v) > now.getTime()) out[k] = v;
  if (state && Array.isArray(state.exhausted) && state.day === pacificDay(now)) {
    for (const k of state.exhausted) out[k] = nextMidnightPacific(now).toISOString();
  }
  out[ref] = until.toISOString();
  return { version: 2, exhausted: out };
}

// Kept for older callers: same as exhaustedNow.
export const exhaustedToday = exhaustedNow;

export function switchedLine(from, to) {
  return `Daily limit reached on ${from}; switched to ${to}.`;
}

export const END_OF_LADDER =
  "All free Gemini models on this key are used up for today. They reset at midnight Pacific time " +
  "(3 a.m. Eastern). Options: (1) a teammate connects their own Google AI Studio key with /connect " +
  "(each person's key has its own daily budget); (2) switch to an OpenCode Zen free model with " +
  "/models, if your event allows it; (3) wait for the reset.";

export function splitRef(ref) {
  const i = ref.indexOf("/");
  return { providerID: ref.slice(0, i), id: ref.slice(i + 1) };
}
