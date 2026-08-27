# 00 — The workflow

Five stages. Three human approval gates. The gates are the point: an agent that
can push to a shared Connect server without a human saying yes is a hazard, not
a productivity gain.

```
  DECLARE ──▶ SCAFFOLD ──▶ [GATE 1] ──▶ MANIFEST ──▶ [GATE 2] ──▶ PUBLISH ──▶ VERIFY ──▶ [GATE 3]
   target      content      code is      hygiene      target is    async       health       keep
   (§01)       (§05)        reviewed     (§03)        confirmed    (§04)       route        or delete
                                                      (§01,§02)                (§04)        (README)
```

## Stage 1 — DECLARE the target

Before a line of app code. Write `connect-target.yaml` (see
[`01-connect-target.md`](01-connect-target.md)): server URL, API prefix, access
type, naming convention, and a **GUID sentinel** that has to be replaced by hand.

Output: a committed, non-secret file. Credentials do **not** appear in it.

## Stage 2 — SCAFFOLD the content

Build the thing. Keep the domain logic in a module that does not import the web
framework — it is the part that gets tested and the part anybody reviews.
[`05-content-scaffolds.md`](05-content-scaffolds.md) lists what a project must
ship to be deployable on day one.

**Run it locally before you think about deploying.** A deploy of an app that has
never run locally fails on the server, where the logs are further away.

### GATE 1 — a human has read the code

Not "the tests pass." A person has looked at what is about to be published to a
server other people can reach. In a team, this is a PR review. Alone, it is you
reading the diff with the intent to find something.

## Stage 3 — MANIFEST

Generate `manifest.json` on a representative machine, commit it, and never let
CI regenerate it. [`03-manifest-hygiene.md`](03-manifest-hygiene.md) explains why
the manifest is an environment fingerprint and what breaks when you forget.

Run `scripts/check-manifest.sh` — it hard-fails if the manifest lists a file that
is not on disk.

### GATE 2 — the target is confirmed

Run `scripts/preflight.sh`. It does a **read-only** `GET` on the content GUID and
prints the **title** of what lives there. A human reads that title and confirms
it is the thing they meant to overwrite.

This gate exists because **a wrong GUID does not fail harmlessly — it overwrites
whatever content it does point at.** There is no undo. See
[`02-publisher-credentials.md`](02-publisher-credentials.md).

## Stage 4 — PUBLISH

Upload the bundle, start the deploy, **do not block on it**.
[`04-deploy-verify.md`](04-deploy-verify.md) explains why: a blocking publish
bills the server's environment-restore time to your CI minutes, and the build
belongs on Connect while the waiting does not.

## Stage 5 — VERIFY

`scripts/verify.sh` polls a health route on the content URL until it answers.
**Green is not live.** A successful upload means the bundle was accepted, not
that the app came up. Only a health route answering proves the app came up.

### GATE 3 — keep it or delete it

If this deploy existed to prove the tooling works, delete it now and say so.
If it is the real deliverable, it gets an owner. See the cleanup convention in
[`../README.md`](../README.md).

## What the agent may and may not do unattended

| Action | Unattended? |
|---|---|
| Write app code, tests, scaffolding | yes |
| Generate or check a manifest | yes |
| Run `preflight.sh` (read-only) | yes |
| Run the app locally | yes |
| **Publish to a shared Connect server** | **no — GATE 2** |
| **Delete content from a shared Connect server** | **no — human action, always** |
| Read a key, print a key, commit a key | **never, at any gate** |

## Extension rules (opt-in, not always-on)

Borrowed from AI-DLC's design: keep the optional rigor in separate files that a
human invokes on purpose, rather than a monolith nobody reads.

- **deploy-hardening** — [`04-deploy-verify.md`](04-deploy-verify.md) §"Hardening"
- **data-handling** — do not bundle data you cannot publish; everything in the
  folder goes up ([`03-manifest-hygiene.md`](03-manifest-hygiene.md))
- **secret-scanning** — `posit-dlc/.gitleaks.toml`, run before every push
