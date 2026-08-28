---
name: posit-dlc
description: The deployment life cycle for Posit Connect - server/target conventions, publisher-credential guardrails, manifest hygiene, the publish-then-verify loop, deployable-on-day-one scaffolds, and the human approval gates. Use when publishing anything to a Posit Connect server, when a deploy fails or a green build produced no running app, when setting up a project that will deploy, or when handling publisher credentials.
---

# posit-dlc

**This skill is a pointer, not a copy.** The methodology lives in exactly one
place — `posit-dlc/core/` at the repo root — so that this file and `AGENTS.md`
cannot drift from it. Read the core files; do not paraphrase them from here.

## Start here

**[`posit-dlc/core/00-workflow.md`](../../../posit-dlc/core/00-workflow.md)** —
the five stages and the three approval gates. Read it before anything else.

## The six components

| Component | File |
|---|---|
| connect-target | [`posit-dlc/core/01-connect-target.md`](../../../posit-dlc/core/01-connect-target.md) |
| publisher-credentials | [`posit-dlc/core/02-publisher-credentials.md`](../../../posit-dlc/core/02-publisher-credentials.md) |
| manifest-hygiene | [`posit-dlc/core/03-manifest-hygiene.md`](../../../posit-dlc/core/03-manifest-hygiene.md) |
| deploy-verify | [`posit-dlc/core/04-deploy-verify.md`](../../../posit-dlc/core/04-deploy-verify.md) |
| content-scaffolds | [`posit-dlc/core/05-content-scaffolds.md`](../../../posit-dlc/core/05-content-scaffolds.md) |
| generation-discipline | [`posit-dlc/core/06-generation-discipline.md`](../../../posit-dlc/core/06-generation-discipline.md) |

Overview and install: [`posit-dlc/README.md`](../../../posit-dlc/README.md).

## The three gates, restated because they bind you

An agent may prepare everything on either side of a gate. It may not cross one.

- **GATE 1** — a human has read the code before it is published anywhere.
- **GATE 2** — a human has confirmed the target GUID by reading
  `scripts/preflight.sh` output. **A wrong GUID overwrites live content and
  there is no undo.**
- **GATE 3** — a human decides whether a demonstration deploy is kept or deleted.
  Deleting server content is a human action, always.

"The user asked me to deploy" is consent for **one** deploy to **one** confirmed
target, not a standing authorization for the session.

## Never

- print, log, summarize, or commit a credential — not even partially redacted
- run `rsconnect write-manifest` (or a regenerating `rsconnect deploy`) in CI
- report a `detached` deploy as a success
- invent a content GUID

## Relationship to the other skills here

- [`connect-publish`](../connect-publish/SKILL.md) — the fast path: the four
  scripts and the commands for a hackathon-length local deploy. Start there if
  you just need a URL today.
- **`posit-dlc`** — the durable path: the guarded life cycle for a project that
  will deploy more than once, by more than one person, possibly from CI.
- [`posit-dev/skills`](https://github.com/posit-dev/skills) (MIT) — Posit's own
  `deploy-to-connect` and friends. Install them; this complements them.
