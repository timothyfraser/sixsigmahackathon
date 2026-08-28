# 02 — publisher-credentials

**A publisher key is the ability to write to a shared server.** Treat it like
one. This is the component AI-DLC has no analogue for, and it is the one that
actually hurts when a room full of people all have keys to the same Connect.

## Credentials live in exactly one place

Pick the one that matches how you deploy, and use only that one.

| How you deploy | Where the key lives |
|---|---|
| From your laptop | a **gitignored `.env`** in the project, or the saved server from `rsconnect add` |
| From GitHub Actions | **repository Actions secrets** — `CONNECT_SERVER`, `CONNECT_API_KEY` |

Never in the repo. Never in `manifest.json`. Never in a script's default value.
Never echoed into a log, a PR description, or a chat message.

```bash
# .gitignore — before you write the file, not after
.env
.posit/
rsconnect/
```

Run the secret scan before you push. `posit-dlc/.gitleaks.toml` is configured for
Connect key shapes:

```bash
gitleaks detect --config posit-dlc/.gitleaks.toml --no-banner
```

**A leaked publisher key is the one mistake a revert does not fix.** The commit
stays in the reflog, in every fork, and in every clone anyone made. If it
happens: rotate the key on the server first, tell whoever administers it second,
and clean the history third — in that order.

## Runtime configuration is NOT deploy configuration

This distinction causes more confusion than any other.

- **Deploy configuration** — how the bundle gets to the server. `CONNECT_SERVER`,
  `CONNECT_API_KEY`. Lives in `.env` or Actions secrets.
- **Runtime configuration** — what the app needs *while running*. Database URLs,
  third-party API keys, feature flags. Lives on the **Connect content item**:
  Content → Settings → Vars.

Runtime values do not belong in the workflow, in the bundle, or in the manifest.
If your app reads `os.environ["DATABASE_URL"]`, that variable is set in Connect's
Vars panel, not in your deploy script.

### Blast radius

**Connect Vars are readable by anyone who can *edit* the content.** The editor
list on a content item is therefore a security boundary, not a convenience
setting. Adding a collaborator as an editor gives them every secret that app
holds. Add viewers freely; add editors deliberately.

## The wrong-GUID hazard is not a 404

The single most expensive mistake available with a publisher key:

> **A wrong GUID does not fail harmlessly. It overwrites whatever content it
> does point at.**

Deploying to a GUID that belongs to someone else's app replaces their app with
yours. Connect does what you asked. There is no confirmation prompt and no undo.

**Mitigation, and it is not optional:** a pre-flight read-only read of the target
that prints the title of what is there, before a single byte of bundle is
uploaded.

```bash
./posit-dlc/scripts/preflight.sh
# → target GUID   : 7f3c...
# → target title  : team-07-spc-api
# → owner         : tfraser
# Confirm this is the content you intend to overwrite.
```

A human reads that title. That is GATE 2 in
[`00-workflow.md`](00-workflow.md). An agent does not clear it on its own.

## `CONNECT_API_KEY` in the environment breaks CLI-flag deploys

A real and well-documented `rsconnect-python` behaviour
([issue #532](https://github.com/posit-dev/rsconnect-python/issues/532)):
deploying with `rsconnect deploy fastapi -s "$SERVER" -k "$KEY" ...` **fails if
`CONNECT_API_KEY` is also set in the environment.**

That is exactly the CI shape — workflows conventionally export both *and* pass
flags. Pick one:

- **flags only**, with no `CONNECT_API_KEY` exported into the step's env, or
- a **saved server** (`rsconnect add --name prod ...`) referenced by name.

Do not do both. Symptom when you do: an authentication-flavoured error that
survives every key rotation you try.

Related: `rsconnect-python` is weak at surfacing *server-side* errors
([#224](https://github.com/posit-dev/rsconnect-python/issues/224)), which is why
these failures feel mysterious. When the client is unhelpful, read the deploy log
on Connect itself.

## Rules for an agent holding a key

1. **Never print it.** Not in a log, not in a summary, not "redacted" with the
   first four characters showing.
2. **Never write it to a new file.** Read it from the environment at the moment
   of use.
3. **Never commit it**, and refuse a request to, whatever the justification.
4. **Never clear GATE 2 alone.** Publishing to a shared server needs an explicit
   human yes for that specific target.
5. **Never delete server content on your own initiative.** Deletion is a human
   action, always.
