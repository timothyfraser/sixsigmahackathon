![](../docs/images/banner_thin.png)
---

# README `demos`

Starter templates for the Six Sigma Hackathon. **Copy a folder into your own
repo** — don't edit these in place.

| Demo | What it is |
|---|---|
| [`fastapi/`](fastapi/) | Python REST API (FastAPI) |
| [`plumber/`](plumber/) | R REST API (plumber) |
| [`reactfront/`](reactfront/) | React front end for either API |
| [`shinyapp/`](shinyapp/) | R Shiny dashboard |
| [`rpackage/`](rpackage/) | R package skeleton |
| [`making_readmes/`](making_readmes/) | how to write a README judges can follow |

## The four-script contract

Every deployable demo ships the same four files. Copy the shape into your own
project and your deploy stays boring, which is what you want at hour 22.

| File | Job |
|---|---|
| `testme.*` | run it locally, one command, no arguments |
| `manifestme.*` | write `manifest.json` for Posit Connect |
| `deployme.*` | push it to Posit Connect |
| `README.md` | what it is, what the endpoints are, how to run it |

If someone who has never seen your project can't start it with one command, a
judge won't see it running either.

---
![](../docs/images/banner_icons.png)
