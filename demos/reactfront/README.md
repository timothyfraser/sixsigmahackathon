# React Front End Demo

A React front end is one way to put a face on your API. It is optional — a
FastAPI `/docs` page or a plumber `/__docs__/` page is already a working demo
surface, and Shiny gets you a dashboard with no npm at all.

Build one only if your statistics are already verified.

## Scaffold it

```bash
npm create vite@latest web -- --template react
cd web && npm install && npm run dev
```

## Shape

```
web/
  src/config.js     <- API base URL lives HERE and only here
  src/App.jsx       <- fetch from the API, render results
  package.json
  testme.sh         <- npm run dev
  manifestme.sh     <- build, then write a Connect manifest for dist/
  deployme.sh       <- publish dist/ to Posit Connect
```

`src/config.js`:

```js
export const API_BASE = import.meta.env.VITE_API_BASE ?? "http://localhost:8000";
```

One place to change means the switch from localhost to your Connect URL at hour
23 is a one-line edit, not a grep across the codebase.

## Deploy

Front end and API are two separate pieces of content on Posit Connect. Deploy
the API first, put its URL in `config.js`, `npm run build`, then publish `dist/`
as a static bundle. See `.claude/skills/connect-publish/SKILL.md`.

Never commit `node_modules/` or `dist/` — both are gitignored.

## Your API needs CORS

A front end served from a different origin is blocked without it. See the
`fastapi-react-scaffold` or `plumber-react-scaffold` skill for the snippet.
