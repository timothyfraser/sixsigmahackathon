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
3. **Regenerate the manifest after every dependency change — on a developer
   machine, never on a CI runner.** A stale `manifest.json` is the single most
   common cause of "it deployed but 500s"; a manifest regenerated in CI is the
   single most common cause of "it deploys from my laptop and fails in Actions"
   (see [GitHub Actions](#github-actions) below).
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

If you do set it up, **start from the worked example rather than from scratch**:

> **[timothyfraser/fastapi-connect-demo](https://github.com/timothyfraser/fastapi-connect-demo)** —
> a minimal FastAPI plus a workflow that has deployed green repeatedly, with the
> classic failure named and countered step by step in the file. MIT.

The one thing to know before you try it, because it costs teams hours:

> **`manifest.json` is not a build config. It is an environment fingerprint of
> the machine that generated it** — `locale`, `python.version`, the pip version,
> and an MD5 per file. `rsconnect deploy` **regenerates** it from whatever
> machine it runs on. On a CI runner that records the *runner* instead of your
> app, and Connect is then asked to satisfy a fingerprint describing the wrong
> computer. That is the whole of "it deploys from my laptop and fails in
> Actions."

So the recipe is:

1. **Commit `manifest.json`.** Generate it once on a developer machine, and let
   CI only *verify* it.
2. **Do not install `rsconnect-python` in the deploy job at all.** Publish with
   three plain `curl` calls against the Connect API — `POST
   /__api__/v1/content/{guid}/bundles`, `POST /__api__/v1/content/{guid}/deploy`,
   then poll `GET /__api__/v1/tasks/{id}`. That is exactly what `rsconnect` does
   internally, minus the ability to rewrite your manifest.
3. **Commit `.python-version`**, have `actions/setup-python` read it with
   `python-version-file:`, and assert in CI that the manifest agrees with it.
4. **Commit `.gitattributes` with `* text=auto eol=lf`**, so the manifest's
   per-file checksums are stable across Windows and Linux checkouts.
5. **Stream Connect's own task output into the Actions log**, so the server's
   real error is visible instead of swallowed by the CLI.
6. **Gate on `/health`.** "The bundle was accepted" is not "the app is running".

Rule 2 is the load-bearing one; the rest is defence in depth. The demo repo's
README walks through each with the measured evidence from a real run.

## Further reading

- **[timothyfraser/fastapi-connect-demo](https://github.com/timothyfraser/fastapi-connect-demo)**
  (MIT) — the Actions → Connect recipe above, as a repo you can copy: committed
  manifest, fingerprint assertions, `curl` publish script, `/health` gate.

- [posit-dev/skills](https://github.com/posit-dev/skills) (MIT) — Posit's own
  maintained skills for R package development and deploying to Connect.
- [rsconnect-python docs](https://docs.posit.co/rsconnect-python/)
- [rsconnect (R) docs](https://rstudio.github.io/rsconnect/)
