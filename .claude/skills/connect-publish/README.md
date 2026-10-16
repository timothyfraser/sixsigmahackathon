# Deploy from GitHub Actions to Posit Connect

Copy **one workflow file** into your repo, add **two secrets**, push. Every push
to `main` then redeploys your app and checks that it actually answers.

The local path (`deployme.sh` / `deployme.R` in each demo) still works and is
the fastest way to your first URL. Use this folder when you want every push to
redeploy without anyone running a command.

## Which workflow fits your app

| Your app | Copy this workflow | Copy these scripts | Commit a manifest? |
|---|---|---|---|
| FastAPI (Python API) | `workflows/deploy-fastapi.yml` | `scripts/connect-publish-async.sh` | yes |
| plumber (R API) | `workflows/deploy-plumber.yml` | `scripts/connect-publish-async.sh` | yes |
| Shiny (R dashboard) | `workflows/deploy-shiny-r.yml` | `scripts/connect-publish-async.sh` | yes |
| Shiny for Python | `workflows/deploy-shiny-py.yml` | `scripts/connect-publish-async.sh` | yes |
| React / Vite front end | `workflows/deploy-react-static.yml` | **both** scripts | no, it is built for you |

Two apps (say an API and a front end)? Copy two workflows. Each one deploys its
own content item.

## 1. Copy the files into YOUR repo

The workflows are in `.claude/skills/connect-publish/workflows/` and the
scripts in `.claude/skills/connect-publish/scripts/` (next to this README).
They go here:

```
your-repo/
  .github/
    workflows/deploy-fastapi.yml          <- the one workflow you picked
    scripts/connect-publish-async.sh      <- the script(s) from the table
    scripts/connect-publish-static-async.sh   (React only)
```

If your app is not at the top of your repo, open the workflow and change
`APP_DIR` in the `env:` block at the top (e.g. `APP_DIR: 'api'`). That block is
the only part you should need to edit. `CONTENT_NAME` defaults to
`<owner>-<repo>-<kind>`, so you rarely need to touch it.

## 2. Add two repo secrets

GitHub: your repo > **Settings > Secrets and variables > Actions > New
repository secret**. Add both:

| Name | Value |
|---|---|
| `CONNECT_SERVER` | the Connect server address, handed out at the event |
| `CONNECT_API_KEY` | your publisher API key, handed out at the event |

**Never commit these values** to a file, a README, or a commit message. Secrets
live in GitHub's settings page and nowhere else. The workflows never print them.

## 3. Commit your manifest (not for React)

`manifest.json` lists your packages and their versions, written **on your own
machine** where the app runs. Re-write it and re-commit whenever you add a
package. The workflow ships it exactly as committed. It never rewrites it.

**FastAPI**: from the app folder:

```bash
python -m pip install rsconnect-python
python --version                      # e.g. Python 3.12.4
rsconnect write-manifest fastapi . --entrypoint app:app
```

Then, in your editor, create a file named `.python-version` holding just the
major.minor version, e.g. `3.12`. (Use the editor, not PowerShell `echo`, which
writes a format Actions cannot read.)

**Shiny for Python**: same, but `rsconnect write-manifest shiny . --entrypoint app:app`.

**plumber or Shiny (R)**: in R, from the app folder (this is what
`demos/plumber/manifestme.R` does):

```r
rsconnect::writeManifest(appDir = ".")
```

**All stacks**: add a `.gitattributes` file at the top of your repo containing
`* text=auto eol=lf`, so Windows and Mac/Linux checkouts give the manifest the
same file checksums.

**React**: nothing to write. Commit `package-lock.json` (from `npm install`); the
workflow runs `npm ci && npm run build` and publishes `dist/`.

## 4. Push and watch

Push to `main` (or open the **Actions** tab and click **Run workflow**). Click the
run to watch it. Lines starting `connect>` are Connect's own build log. The last
step prints `LIVE:` and your app's address once it answers.

The first run creates your content item on Connect. Later runs update the same
one. Open it in Connect to share it or change who can see it.

## If it fails

Read the first red `Error:` line. It names the fix. The three most common:

1. **"manifest ... expected ..." or "manifest says Python X but .python-version
   says Y".** The manifest is stale, from the wrong folder, or made with the
   wrong command. Re-write it on your machine from `APP_DIR` (step 3), commit,
   push. Never generate it inside Actions.
2. **"Repo secret ... is not set" or HTTP 401/403.** A secret is missing,
   misspelled, or has a stray space. Re-add it in Settings (names are
   case-sensitive). A 409 means someone else already owns that content name:
   change `CONTENT_NAME`.
3. **`connect>` lines end in a package install error, or the check never sees
   200.** A package or version Connect cannot install, or an app that crashes at
   start. Run it locally first (`testme`), pin versions, re-write the manifest.
   Then open the app in Connect and read its **Logs** tab.

## Where this comes from

These files adapt
[timothyfraser/fastapi-connect-demo](https://github.com/timothyfraser/fastapi-connect-demo)
(MIT). It has a longer write-up of why `rsconnect deploy` inside Actions breaks
and why three plain `curl` calls to the Connect API do not.
