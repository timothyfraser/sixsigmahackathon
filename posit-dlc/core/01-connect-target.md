# 01 — connect-target

**The bundle must know which Connect it is talking to, and what the house style
is, before it writes a line of code.**

Everything in this component is **non-secret and committed**. The server URL is
not a credential. The API key is, and it lives somewhere else entirely — see
[`02-publisher-credentials.md`](02-publisher-credentials.md).

## The declaration

Copy `posit-dlc/connect-target.example.yaml` to `connect-target.yaml` at your
project root and fill it in.

```yaml
server_url: "PUT_SERVER_URL_HERE"      # e.g. https://connect.example.org
api_prefix: "/__api__/v1"              # do not change this
content:
  guid: "PUT_GUID_HERE"                # provisioned by a human, once
  title: "my-team-spc-api"
  access_type: "acl"                   # acl | logged_in | all
  health_path: "/health"
runtime:
  python_version: "3.12"               # must match .python-version
```

## The API prefix is `/__api__/v1`

Two underscores on each side. It is easy to leave off, and leaving it off does
not produce an obvious error — you get a **404 that reads like a permissions
problem**, and people burn an hour on credentials that were fine all along.

```bash
# right
curl -sS -H "Authorization: Key $CONNECT_API_KEY" \
  "$CONNECT_SERVER/__api__/v1/content/$GUID"

# wrong — 404, and you will blame your key
curl -sS -H "Authorization: Key $CONNECT_API_KEY" \
  "$CONNECT_SERVER/content/$GUID"
```

## Content is addressed by GUID, and the GUID is committed

Not looked up by name at deploy time, not guessed, not passed on the command
line by whoever is deploying today. It goes in `connect-target.yaml` (or, for
CI, an `env:` value in the workflow) as a literal.

Until a human fills it in it stays as the sentinel `PUT_GUID_HERE`, and every
script in this bundle **hard-fails loudly** on the sentinel rather than doing
something creative.

## Provision once, by hand

**A human creates the content item on the server. Automation never invents a
GUID.** The first deploy of a new app is a deliberate human act; every deploy
after that targets the GUID that act produced.

This is not ceremony. It is the only thing standing between "the workflow ran"
and "the workflow created seventeen orphaned apps because a retry loop was
enthusiastic."

Make it a guard step, not a comment:

```bash
if [ "$CONTENT_GUID" = "PUT_GUID_HERE" ]; then
  echo "ERROR: content.guid is still the sentinel."
  echo "  A human must create the content item on Connect once, then paste"
  echo "  its GUID into connect-target.yaml. Automation does not invent GUIDs."
  exit 1
fi
```

## Naming and URL conventions

Decide these once, write them in the declaration, and stop arguing about them.

- **Content name** — lowercase, hyphenated, prefixed by team or project:
  `team-07-spc-api`, not `api` and not `Final FINAL v2`. On a shared server the
  prefix is what makes your content findable and other people's content safe.
- **Vanity URL** — set it deliberately or not at all. A vanity URL is a global
  namespace on that server; taking a generic one (`/api`, `/dashboard`) is
  antisocial.
- **`access_type`** — `acl` (named users only), `logged_in` (anyone with an
  account), or `all` (public). Default to the most restrictive one that lets your
  audience in, then widen on purpose.

## A 401 or 403 is often the release schedule, not an outage

On a server where content ACLs gate access deliberately, a 403 on someone else's
content is the system working. Before you debug your credentials, check whether
you were supposed to be able to see that thing yet.

## Reusability

Nothing above is specific to any one event, course, or team. Changing servers is
editing one YAML file. That is the whole design goal: **the Connect target is
configuration, not code.**
