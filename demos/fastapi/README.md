# FastAPI Demo

A minimal Python REST API starter for the Six Sigma Hackathon. Copy this folder
into your own repo; don't edit it in place.

## Endpoints

- `GET /` — root, returns API info
- `GET /echo?msg=hello` — echo a message
- `POST /sum` — add two numbers
- `GET /docs` — interactive OpenAPI docs, free from FastAPI. This page is a
  demo asset: judges can drive your API from it without you writing a UI.

## The four-script contract

| File | Job |
|---|---|
| `testme.sh` | run locally on port 8000 |
| `manifestme.sh` | write `manifest.json` for Posit Connect |
| `deployme.sh` | publish to Posit Connect |
| `README.md` | this file |

```bash
./testme.sh        # then visit http://localhost:8000/docs
./manifestme.sh
./deployme.sh
```

## Notes

- Keep your statistics in a separate module that does **not** import FastAPI.
  `app.py` should be thin. See `.claude/skills/stats-first-steering/SKILL.md`.
- Pin every dependency in `requirements.txt` with `==`.
- Regenerate the manifest after any dependency change.
- Secrets and API keys go in Connect's environment settings, never in the repo.
- Publisher credentials for the course Connect server are handed out at the
  event. See `.claude/skills/connect-publish/SKILL.md`.
