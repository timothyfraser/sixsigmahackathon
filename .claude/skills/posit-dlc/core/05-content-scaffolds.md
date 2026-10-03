# 05 — content-scaffolds

**The plumbing should be pre-solved so that your build time goes into the thing
you are actually being judged on.** A scaffold that is manifest-correct on day
one is worth more than a clever one.

## What a deployable-on-day-one project ships

Any project, any language. If one of these is missing, you will find out at the
worst possible moment.

| File | Why |
|---|---|
| `manifest.json` | committed, generated on a representative machine (`03`) |
| `.python-version` / `renv.lock` | the runtime is pinned, not inferred (`03` RULE 2) |
| `requirements.txt` (pinned `==`) | dependency resolution is deterministic |
| `connect-target.yaml` | the target is declared, non-secret (`01`) |
| a **health route** | verification has something to ask (`04`) |
| `.gitignore` with `.env` | before the first commit, not after |
| a one-command local run | `testme` — if it can't be started, nobody sees it |
| `README.md` | what it is, what the endpoints are, how to run it |

## The four-script contract

The demos in this repo (`demos/fastapi/`, `demos/plumber/`, `demos/reactfront/`)
already follow this shape. Copy it into your own project and your deploy is
boring, which is the goal at hour 22.

| File | Job |
|---|---|
| `testme.*` | run it locally, one command, no arguments |
| `manifestme.*` | write `manifest.json` — run on **your** machine, never in CI |
| `deployme.*` | push it to Connect |
| `README.md` | what it is, what the endpoints are, how to run it |

`posit-dlc` slots into that contract rather than replacing it: `deployme` is where
`preflight.sh` → `publish-async.sh` → `verify.sh` belong.

## Layout rule — the domain logic does not import the web framework

The single highest-leverage structural decision:

```
your-project/
  app.py               # thin: routes in, JSON out. imports analysis.
  analysis.py          # ALL the real work. imports numpy/pandas. NOT fastapi.
  test_analysis.py     # tests the real work, no server needed
  requirements.txt
  .python-version
  manifest.json
  connect-target.yaml
```

Why it matters here specifically:

- `analysis.py` is testable without starting a server, so it actually gets tested.
- A reviewer can read the part that matters without wading through routing.
- When the deploy breaks, you know instantly whether it is a plumbing problem or
  a logic problem — they live in different files.
- You can swap FastAPI for plumber, or a dashboard for an API, without touching
  the part anyone is grading.

Keep `app.py` under a page if you can. A route that computes anything is a route
that should be calling a function.

## The minimum FastAPI shape

```python
# app.py
from fastapi import FastAPI
import analysis

VERSION = "1.0.0"
app = FastAPI(title="...", version=VERSION)

@app.get("/health")
async def health():
    return {"status": "ok", "version": VERSION}

@app.get("/summary")
async def summary(n: int = 30):
    return analysis.summarize(n)     # the work happens elsewhere
```

```bash
echo "3.12" > .python-version
rsconnect write-manifest api . --entrypoint app:app   # on YOUR machine
```

## The minimum plumber shape

```r
# plumber.R
source("analysis.R")
VERSION <- "1.0.0"

#* @get /health
function() list(status = "ok", version = VERSION)

#* @get /summary
function(n = 30) summarize(as.numeric(n))
```

```r
rsconnect::writeManifest(appDir = ".")   # on YOUR machine
```

## Front ends

A React front end deployed as static content to Connect is a separate content
item with its own GUID and its own `connect-target.yaml`. It talks to the API
over the API's public URL. Two items, two GUIDs, two health checks — do not try
to make one bundle serve both.

## Scaffolding discipline for an agent

1. Write `analysis` first, with tests. Routes are the last thing.
2. Add the health route **before** the interesting routes. It is what proves the
   deploy.
3. Pin every dependency as you add it, not in a cleanup pass.
4. Generate the manifest **last**, once dependencies have stopped moving.
5. Run it locally and show the output before proposing a deploy.
6. Stop at GATE 2. Publishing is a human decision.
