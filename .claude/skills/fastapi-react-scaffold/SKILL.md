---
name: fastapi-react-scaffold
description: Scaffold a Python FastAPI backend with a React front end for a hackathon project - project shape, the four-script contract, CORS, and how to split the analysis code from the API layer. Use when a team picks Python for a REST API or a dashboard-style web app.
---

# FastAPI + React scaffold

Start from [`demos/fastapi/`](../../../demos/fastapi/) and
[`demos/reactfront/`](../../../demos/reactfront/). Copy them into your own repo
rather than editing them in place.

## Shape

```
yourproject/
  api/
    stats.py           <- your statistics. plain functions. no framework.
    test_stats.py      <- verification against known cases. write this early.
    app.py             <- FastAPI routes. thin. calls stats.py.
    requirements.txt   <- pinned versions
    testme.sh manifestme.sh deployme.sh README.md
  web/
    src/               <- React app (Vite)
    testme.sh manifestme.sh deployme.sh README.md
```

**`stats.py` must not import FastAPI.** That separation is what lets you test the
statistics without running a server, and it is the difference between finding a
wrong estimator at hour 3 and at hour 23. See the `stats-first-steering` skill.

## Backend

`app.py` stays thin — parse input, call a function from `stats.py`, return JSON:

```python
from fastapi import FastAPI
from stats import xbar_r_limits

app = FastAPI(title="...", version="1.0.0")

@app.get("/")
async def root():
    return {"message": "API is running", "docs": "/docs"}

@app.post("/spc/xbar")
async def spc_xbar(payload: dict):
    return xbar_r_limits(payload["values"], payload["subgroup_size"])
```

FastAPI gives you interactive docs at `/docs` for free. That page is a demo asset
— judges can drive your API from it without you writing a UI at all. If time is
short, `/docs` *is* your front end.

## CORS

A React front end on a different origin will be blocked without this:

```python
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware, allow_origins=["*"],
    allow_methods=["*"], allow_headers=["*"],
)
```

Wide-open CORS is fine for a hackathon demo. Do not carry it into anything real.

## Front end

Vite + React, kept deliberately small:

```bash
npm create vite@latest web -- --template react
cd web && npm install && npm run dev
```

Put the API base URL in one place (`src/config.js`) so the switch from
`http://localhost:8000` to your Connect URL is a one-line edit at hour 23, not a
grep across the codebase.

Build with `npm run build`; deploy the `dist/` folder as a static bundle. Do not
commit `node_modules/` or `dist/` — both are gitignored.

## Deploy

The API and the front end deploy as two separate pieces of content on Posit
Connect. Deploy the API first, get its URL, put it in `src/config.js`, rebuild,
then deploy the front end. See the `connect-publish` skill.

## Time budget

Roughly: statistics + verification 40%, API 20%, front end 25%, deploy + demo
prep 15%. If you are past half the clock and the statistics are not verified,
cut the front end and ship the API with its `/docs` page.
