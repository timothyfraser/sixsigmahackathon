# Plumber API Demo

A minimal R REST API starter for the Six Sigma Hackathon. Copy this folder into
your own repo; don't edit it in place.

## Endpoints

- `GET /echo?msg=hello` — echo a message
- `GET /plot` — a PNG histogram
- `POST /sum` — add two numbers
- `/__docs__/` — interactive Swagger docs, free from plumber. This page is a
  demo asset: judges can drive your API from it without you writing a UI.

## The four-script contract

| File | Job |
|---|---|
| `testme.R` | run locally on port 5762 |
| `manifestme.R` | write `manifest.json` for Posit Connect |
| `deployme.R` | publish to Posit Connect |
| `README.md` | this file |

```r
source("testme.R")
source("manifestme.R")
source("deployme.R")
```

## Notes

- Keep your statistics in `R/stats.R` and `source()` it from `plumber.R`. Plain
  functions are testable in a console in ten seconds.
- `rsconnect::writeManifest()` finds dependencies by scanning for `library()`
  calls. Load packages the normal way or they won't be detected.
- Publisher credentials for the course Connect server are handed out at the
  event. See `.claude/skills/connect-publish/SKILL.md`.
