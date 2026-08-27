# posit-dlc

**A deployment life cycle for Posit Connect, packaged as agent-steering files.**

If you have publisher credentials on a Posit Connect server, this bundle helps
you — and the coding agent sitting next to you — create and ship content on that
server **efficiently** (you are not rediscovering the manifest rules at hour 22)
and **safely** (you are not overwriting somebody else's app or committing a key).

It is deliberately not hackathon-specific. The Connect server is *configuration*,
not code. Copy `posit-dlc/` into any repo that publishes to any Connect.

## Why it exists

AWS Labs ships [`aidlc-workflows`](https://github.com/awslabs/aidlc-workflows)
(MIT-0) — an AI-Driven Life Cycle methodology written as harness-neutral steering
rules with thin per-harness surfaces. Its shape is worth borrowing: one core,
many generated surfaces, and a human approval gate between phases.

AI-DLC covers a whole SDLC — inception, construction, operations. **`posit-dlc`
is AI-DLC's Operations phase made first-class for Posit Connect**, plus just
enough construction scaffolding to produce content that is deployable on day one.
Structure borrowed with thanks; MIT-0 imposes no attribution burden, but credit
is cheap and the lineage is useful.

## The six components

Read them in order the first time. After that, jump to the one that is biting.

| # | Component | File | What it prevents |
|---|---|---|---|
| 1 | **connect-target** | [`core/01-connect-target.md`](core/01-connect-target.md) | guessing the server, the API prefix, or the content GUID |
| 2 | **publisher-credentials** | [`core/02-publisher-credentials.md`](core/02-publisher-credentials.md) | a leaked key; a deploy that overwrites the wrong app |
| 3 | **manifest-hygiene** | [`core/03-manifest-hygiene.md`](core/03-manifest-hygiene.md) | "it works on my laptop, it fails in CI" |
| 4 | **deploy-verify** | [`core/04-deploy-verify.md`](core/04-deploy-verify.md) | believing a green check means the app is up |
| 5 | **content-scaffolds** | [`core/05-content-scaffolds.md`](core/05-content-scaffolds.md) | spending your build time on plumbing |
| 6 | **generation-discipline** | [`core/06-generation-discipline.md`](core/06-generation-discipline.md) | drifted duplicate instruction files; an unapproved push to a shared server |

The workflow that strings them together, with its approval gates, is
[`core/00-workflow.md`](core/00-workflow.md). **Start there.**

## File map

```
posit-dlc/
  README.md                     this file
  connect-target.example.yaml   the committed, non-secret target declaration
  .gitleaks.toml                secret-scan config — run it before you push
  core/
    00-workflow.md              the five stages and the three approval gates
    01-connect-target.md        server conventions, GUIDs, provision-once
    02-publisher-credentials.md where keys live, blast radius, the wrong-GUID hazard
    03-manifest-hygiene.md      the manifest is an environment fingerprint
    04-deploy-verify.md         fire-and-forget publish, then verify a health route
    05-content-scaffolds.md     what a deployable-on-day-one project ships
    06-generation-discipline.md one core, thin surfaces, and the human gates
  scripts/
    preflight.sh                read-only: prove the GUID points where you think
    check-manifest.sh           hard-fail on a stale or lying manifest
    publish-async.sh            upload + deploy, do not block, print the task id
    verify.sh                   poll a health route until it answers
```

Every script takes its configuration from a `connect-target.yaml` in your project
and its credentials from the environment. **No script in this bundle prints a
key, and none of them writes one to disk.**

## Install

```bash
# 1. copy the core into your project
cp -r posit-dlc/ /path/to/your-project/

# 2. declare your target (non-secret, committed)
cd /path/to/your-project
cp posit-dlc/connect-target.example.yaml connect-target.yaml
$EDITOR connect-target.yaml        # fill in server_url, leave guid as the sentinel

# 3. put credentials in a gitignored .env (never committed)
printf 'CONNECT_SERVER=...\nCONNECT_API_KEY=...\n' > .env
grep -qx '.env' .gitignore || echo '.env' >> .gitignore

# 4. point your agent at the core
#    Claude Code: .claude/skills/posit-dlc/SKILL.md already does this
#    anything else: add the AGENTS.md row (see core/06-generation-discipline.md)
```

## Cleanup convention

**Anything this bundle deploys as a demonstration is deleted when the
demonstration is over**, by the person who deployed it, in the same working
session. A Connect server accumulates abandoned content faster than anyone
expects, and an abandoned app with a live URL is somebody's future confusion.

The rule, precisely:

- Content deployed to **prove the tooling works** (a smoke test, a scaffold
  run-through, a bundle self-check) is **deleted immediately after verification**,
  and the deletion is stated out loud in whatever report or PR describes the run.
- Content deployed as **the actual deliverable** stays, and gets an owner.
- If you cannot delete it — no permission, wrong account — say so explicitly and
  name the GUID so somebody who can, does. Silence is not cleanup.

`scripts/` deliberately ships no `delete.sh`. Deletion of shared-server content
is a human action taken deliberately, not a script somebody runs by reflex.

## Further reading

- [`posit-dev/skills`](https://github.com/posit-dev/skills) (MIT) — Posit's own
  maintained skills, including `deploy-to-connect`. Install them; this bundle
  complements them rather than replacing them.
- [rsconnect-python docs](https://docs.posit.co/rsconnect-python/deploying/)
- [Posit Connect API reference](https://docs.posit.co/connect/api/)
- [`awslabs/aidlc-workflows`](https://github.com/awslabs/aidlc-workflows) (MIT-0)
  — the methodology whose shape this borrows.
