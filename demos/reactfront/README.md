# React Front End Demo

A one-screen quality-control app: paste measurements, see an individuals
(I-MR) control chart with the center line, the +/-3 sigma limits, and any
points outside them in red. Plain Vite + React, a hand-drawn SVG chart, no UI
kit. It works on a phone.

The statistics live in `src/spc.js` and are tested in `src/spc.test.js`. The
chart and the page are in `src/App.jsx`. The API address lives in `src/api.js`
and nowhere else.

A front end is optional. FastAPI's `/docs` page is already a working demo.
Build this only once your statistics are verified.

## Run it

You need Node.js 20 or newer.

```bash
npm install
npm run dev        # open the http://localhost:5173 link it prints
```

## Point it at your API

The app pings `GET /` on the API in [`../fastapi/`](../fastapi/) and shows
whether it is reachable. The address defaults to `http://127.0.0.1:8000`. To
change it, create a file named `.env.local` in this folder:

```
VITE_API_URL=https://your-api-address
```

then restart `npm run dev` (or rebuild). Your API needs CORS turned on, or the
browser blocks the call: see the
[`fastapi-react-scaffold`](../../.claude/skills/fastapi-react-scaffold/SKILL.md) skill.

The demo API has no control-chart route, so the limits are computed in the
browser. When your API has one, `limitsOnServer()` in `src/api.js` shows where
it slots in.

## Build and test

```bash
npm run build      # writes dist/, a static site that works under any URL path
npm test           # runs the statistics tests
```

## Deploy to Posit Connect

Easiest: copy
[`.claude/skills/connect-publish/workflows/deploy-react-static.yml`](../../.claude/skills/connect-publish/workflows/deploy-react-static.yml)
into your repo's `.github/workflows/` and both scripts in
[`.claude/skills/connect-publish/scripts/`](../../.claude/skills/connect-publish/scripts/)
into `.github/scripts/`, add the two repository secrets it names, and push. It runs `npm ci && npm run build` and publishes `dist/` as static
content.

Manual: run `npm run build`, then publish the `dist/` folder as static content
(see the [`connect-publish`](../../.claude/skills/connect-publish/SKILL.md) skill).
Deploy the API first and set `VITE_API_URL` to its address before you build:
Vite bakes the value into `dist/`.

Never commit `node_modules/` or `dist/` (both are in `.gitignore`). Do commit
`package-lock.json`, so `npm ci` installs the same versions everywhere.

## Extend it with your AI agent

Keep the statistics in `src/spc.js`, and make the agent prove every change
with a test before it touches the page. Prompts that work:

- "Add an X-bar and R chart for subgroups of size 5 to `src/spc.js`, using the
  A2, D3 and D4 table constants. Add a test that reproduces a worked textbook
  example before you change `App.jsx`."
- "Add Western Electric rules 2 to 4 to `outOfControl()` in `src/spc.js`. Write
  one test per rule with a planted pattern and check each flags exactly the
  points I planted. Do not change how the limits are computed."
- "Move `imrLimits()` into our FastAPI app as `POST /spc/imr`, with a pytest
  that matches `src/spc.test.js`, then call it from `App.jsx` through
  `limitsOnServer()` in `src/api.js`, keeping the browser version as a fallback."
