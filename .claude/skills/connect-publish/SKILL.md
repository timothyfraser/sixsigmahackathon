---
name: connect-publish
description: Deploy a FastAPI, plumber, Shiny, or static React app to the course Posit Connect server with rsconnect / rsconnect-python, including manifest hygiene and the failure modes that eat the first hour. Use when a hackathon team is ready to publish, when a deploy fails with a bundle or dependency error, or when someone asks how their tool gets a public URL.
---

# Publishing to Posit Connect

**Publisher credentials are handed out at the event.** Nothing in this repo
contains a server URL or an API key, and you do not need either before you
arrive. Deploys are **local**, from your own machine.

## Set up once

```bash
# Python side
python -m pip install rsconnect-python

# R side
install.packages("rsconnect")
```

Put the two values you are given at the event in a **gitignored** `.env` in your
project folder:

```
CONNECT_SERVER=...
CONNECT_API_KEY=...
```

`.env` is already in `.gitignore`. Confirm with `git status` before you commit —
a leaked publisher key is the one mistake that cannot be undone by a revert.

## The four-script contract

Every deployable demo here ships `testme`, `manifestme`, `deployme`, `README`.
Run them in that order. Do not skip `testme`: a deploy of an app that never ran
locally fails on the server, where the logs are further away.

## Python (FastAPI)

```bash
./testme.sh        # uvicorn app:app --host 0.0.0.0 --port 8000
./manifestme.sh    # rsconnect write-manifest api . --entrypoint app:app
./deployme.sh      # rsconnect deploy fastapi --entrypoint app:app .
```

## R (plumber / Shiny)

```r
source("testme.R")        # plumb("plumber.R") |> pr_run(port = 5762)
source("manifestme.R")    # rsconnect::writeManifest(appDir = ".")
source("deployme.R")      # rsconnect::deployApp(appDir = ".")
```

## Manifest hygiene — the rules that prevent most failures

1. **Deploy from the app folder, not the repo root.** The manifest describes the
   directory it was written in. Extra folders get bundled, dependency detection
   goes wide, and the build times out.
2. **Pin your dependencies.** `requirements.txt` with `==` versions for Python;
   a clean `renv.lock` or a loadable library set for R. "It works on my laptop"
   is a statement about your laptop.
3. **Regenerate the manifest after every dependency change.** A stale
   `manifest.json` is the single most common cause of "it deployed but 500s".
4. **Match the Python/R version** to what the server offers. If the deploy log
   complains about an unavailable interpreter version, that is what it means.
5. **Never bundle data you cannot publish**, secrets, or `.env`. Everything in
   the folder goes up.
6. **Entrypoint must be explicit** for FastAPI (`app:app`). Autodetection is not
   worth the debugging.
7. **Environment variables belong in Connect's settings panel**, not in code and
   not in the bundle.

## When a deploy fails

Read the deploy log top to bottom — Connect prints the failing step. In order of
likelihood:

- dependency resolution (unpinned or unavailable package)
- wrong or missing entrypoint
- stale manifest
- interpreter version mismatch
- the app never actually ran locally

Fix, re-run `manifestme`, re-run `deployme`. Do not start changing the app code
until you have read the log.

## GitHub Actions

An Actions-based deploy path exists and works, but the credentials handed out at
the event are for local publishing. Set up Actions only if your team has spare
time — at hour 22 the local path is the one that gets you a URL.

## Further reading

- [posit-dev/skills](https://github.com/posit-dev/skills) (MIT) — Posit's own
  maintained skills for R package development and deploying to Connect.
- [rsconnect-python docs](https://docs.posit.co/rsconnect-python/)
- [rsconnect (R) docs](https://rstudio.github.io/rsconnect/)
