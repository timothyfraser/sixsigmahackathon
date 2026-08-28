# 03 — manifest-hygiene

**`manifest.json` is not a file list. It is a fingerprint of the machine that
generated it**, which Connect then tries to reproduce on the server.

Once you know that, every "it works on my laptop and fails in CI" deploy failure
stops being mysterious.

## What is actually in there

```json
{
  "version": 1,
  "locale": "English_United States.1252",
  "metadata": { "appmode": "python-fastapi", "entrypoint": "app:app" },
  "python": {
    "version": "3.12.10",
    "package_manager": { "name": "pip", "version": "26.0.1",
                         "package_file": "requirements.txt" }
  },
  "files": { "app.py": { "checksum": "..." }, "...": {} }
}
```

Four things there are properties of **a machine**, not of your project:

1. **`locale`** — `locale.getlocale()` on the publishing machine. A Windows
   laptop yields something like `English_United States.1252` (cp1252, the Windows
   ANSI codepage). A Linux box yields `en_US`. A bare Ubuntu CI runner with
   `LANG`/`LC_ALL` unset yields `(None, None)`, and the manifest gets `""`.
2. **`python.version`** — `sys.version_info` of the interpreter that ran.
3. **`package_manager.version`** — parsed from `python -m pip --version`.
4. **`files[*].checksum`** — per-file, of the files as they were on that disk.

This is the grain of truth in "Connect runs a different encoding." There is a
literal encoding field, it does differ between a laptop and a runner, and it is
one symptom of the larger cause below.

Source, if you want to read it yourself:
[`rsconnect/subprocesses/inspect_environment.py`](https://github.com/posit-dev/rsconnect-python/blob/master/rsconnect/subprocesses/inspect_environment.py)
and [`rsconnect/bundle.py`](https://github.com/posit-dev/rsconnect-python/blob/master/rsconnect/bundle.py).

## RULE 1 — the manifest is a committed artifact, and CI never regenerates it

Generate it **once, on a representative machine**. Commit it. Then:

> **CI verifies the manifest. CI does not write the manifest.**

`rsconnect write-manifest` (or `rsconnect deploy fastapi`, which regenerates it
implicitly) on a bare runner records *the runner's* environment. The bundle
Connect receives is not the bundle that worked on the laptop. That is the entire
shape of the classic Actions→Connect failure.

If your CI step runs `rsconnect deploy`, you have this bug and do not know it yet.
Upload the committed bundle instead — see
[`04-deploy-verify.md`](04-deploy-verify.md).

## RULE 2 — pin the Python version explicitly

Commit a `.python-version` file. Otherwise the manifest's Python requirement is
an accident of whichever interpreter happened to run.

`rsconnect` decides the required version in this order
([docs](https://docs.posit.co/rsconnect-python/deploying/)):

1. a **`.python-version`** file — its content is the requirement
2. `pyproject.toml` → `project.requires-python`
3. `setup.cfg` → `options.python_requires`
4. **fallback:** the interpreter in use is considered the one required

Rule 4 is where lucky projects live. On Connect ≥ 2025.03.0 the detected
requirement is *always respected* — so a manifest demanding 3.12.10 on a server
that offers 3.11 fails during environment restore, **server-side, after a
green-looking upload**.

```bash
echo "3.12" > .python-version   # and make it match connect-target.yaml
```

For R, the equivalent discipline is a clean `renv.lock` regenerated when
dependencies change.

## RULE 3 — every file that ships must be listed, and watched

Two lists have to agree:

- the **manifest's** file list — what gets bundled
- your workflow's **`paths:`** filter — what triggers a deploy

A file that is deployed but not watched means you change it, CI does not fire,
and **Connect quietly keeps running the old code**. This failure is silent and it
has cost real debugging hours. When you add a file, add it to both.

## RULE 4 — a stale manifest is a hard failure

A file listed in the manifest but missing on disk is an **error**. Not a warning,
not something to skip past.

```bash
./posit-dlc/scripts/check-manifest.sh
# → ERROR: manifest lists 3 file(s) that do not exist on disk:
# →   app/routes/legacy.py
# → Regenerate the manifest on a representative machine, then commit it.
```

Regenerate → review the diff → commit. **Read the diff.** If `locale` or
`python.version` changed and you did not intend that, you just regenerated on the
wrong machine.

## RULE 5 — pin your dependencies

`requirements.txt` with `==` versions. `renv.lock` for R. "It works on my laptop"
is a statement about your laptop, and the server is not your laptop.

## RULE 6 — deploy from the app folder, not the repo root

The manifest describes the directory it was written in. Point it at the repo root
and you bundle your notes, your data, your `node_modules`, and your `.env` —
dependency detection goes wide and the build times out.

## RULE 7 — never bundle what you cannot publish

**Everything in the folder goes up.** Secrets, `.env`, unpublishable data, a
scratch CSV with real names in it. Look at the file list in the manifest before
you deploy; it is the definitive answer to "what am I about to publish."

## RULE 8 — entrypoint is explicit

`--entrypoint app:app` for FastAPI. Autodetection sometimes works and is never
worth the debugging when it does not.

## The checklist

```
[ ] .python-version committed, matches connect-target.yaml
[ ] requirements.txt / renv.lock pinned
[ ] manifest.json committed, generated on a representative machine
[ ] check-manifest.sh passes
[ ] manifest file list contains nothing you cannot publish
[ ] workflow paths: filter matches the manifest's file list
[ ] entrypoint stated explicitly
[ ] CI does not run write-manifest or a regenerating deploy
```
