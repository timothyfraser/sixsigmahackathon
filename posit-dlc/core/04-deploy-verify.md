# 04 — deploy-verify

Publishing has two halves and people conflate them. **Uploading a bundle is not
deploying an app, and a green check is not a running service.**

## Publish fire-and-forget, verify out-of-band

Connect does real work when it receives a bundle: it restores the environment,
installs packages, and starts the process. That can take minutes.

If your CI job *blocks* on it, you are billing Connect's server-side build to
your CI minute meter, for a build your CI is not doing. This is not theoretical
— one repo running the blocking pattern burned roughly **1,160 Actions minutes in
a single month** and exhausted its private-repo budget twice.

> **The build belongs on Connect. The waiting does not.**

The shape:

```bash
# 1. upload the committed bundle (a tar.gz of the manifest + its files)
POST $CONNECT_SERVER/__api__/v1/content/$GUID/bundles

# 2. ask Connect to deploy it — returns a task id immediately
POST $CONNECT_SERVER/__api__/v1/content/$GUID/deploy   {"bundle_id": "..."}

# 3. watch the task for a SHORT bounded window, then let go
GET  $CONNECT_SERVER/__api__/v1/tasks/$TASK_ID

# 4. verify separately, against the app itself
GET  $CONTENT_URL/health
```

`scripts/publish-async.sh` does 1–3. `scripts/verify.sh` does 4.

Note what step 1 and 2 do **not** involve: `rsconnect` running on the runner. No
`rsconnect` in CI means no regenerated manifest, and no
[issue #532](https://github.com/posit-dev/rsconnect-python/issues/532)
env-versus-flag collision. See [`03-manifest-hygiene.md`](03-manifest-hygiene.md).

## Green ≠ live

Two distinct outcomes, and they must be reported differently:

| Status | Means | Does it mean the app is up? |
|---|---|---|
| `succeeded` | Connect finished the deploy inside the watch window | probably — still verify |
| `detached` | upload + deploy were **accepted**; the watch window ended first | **no** |
| `failed` | Connect's deploy task failed | no — read the task log |

`detached` is a normal, healthy outcome of the fire-and-forget pattern. It is not
a failure and it is not a success. A script that prints "deployed!" on `detached`
is lying to you.

## The verification is a health route, not a green check

Every deployable thing this bundle scaffolds ships a health route:

```python
@app.get("/health")
async def health():
    return {"status": "ok", "version": VERSION}
```

```r
#* @get /health
function() { list(status = "ok", version = VERSION) }
```

Then:

```bash
./posit-dlc/scripts/verify.sh
# → GET https://connect.example.org/content/7f3c.../health
# → 200 {"status":"ok","version":"1.0.0"}
# → VERIFIED
```

**Your definition of done is "the health route answers", not "the workflow is
green."** Write it that way in your acceptance criteria and you will catch the
class of failure where the upload succeeded and the process never started.

Include a `version` in the health payload. Then the health check also answers
"did my *new* code deploy, or am I looking at yesterday's process?"

## A 401/403 during verification may be the ACL, not a bug

If the content's `access_type` is `acl` or `logged_in`, an unauthenticated curl
gets a 401/403 — correctly. Verify with the API key header, or expose the health
route publicly on purpose. Do not go rotate credentials over this.

## Reading a failure

In rough order of likelihood:

1. **Manifest mismatch** — CI regenerated it. See `03`.
2. **Interpreter version** — the manifest demands a version the server does not
   offer. See `03` RULE 2.
3. **Dependency resolution** — an unpinned or unavailable package.
4. **Missing or wrong entrypoint.**
5. **The app never ran locally.** Go run it locally.

Read the **Connect-side** task log, not just the CI log. `rsconnect-python` is
known to swallow server-side error detail
([#224](https://github.com/posit-dev/rsconnect-python/issues/224)); the real
message is on the server.

Do not start editing app code until you have read the log.

## Hardening (opt-in extension rule)

Turn these on when the content is something people depend on:

- **Pre-flight the GUID on every deploy**, not just the first. `preflight.sh` is
  read-only and takes a second.
- **Deploy twice, verify twice.** A deploy path that has only ever worked once
  has not been shown to be repeatable.
- **Fail the pipeline on `failed`, and report `detached` as `detached`** — never
  collapse the three statuses into a boolean.
- **Alert on the health route**, not on the deploy job. The deploy job stops
  telling you anything the moment it finishes.
- **Integration testing against a real Connect:** see
  [`posit-dev/with-connect`](https://github.com/posit-dev/with-connect), a CLI +
  GitHub Action for exactly that. Not required; worth knowing about.
