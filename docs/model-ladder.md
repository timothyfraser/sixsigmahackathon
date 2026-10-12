# The model ladder: never run out of free Gemini

Every free Gemini model has its **own daily limit** (about 500 requests a day for
"flash-lite" models, about 20 for "flash" models). When the model you are using runs
out for the day, OpenCode would normally stop with a `429` error. The model ladder
plugin stops that from ending your work.

## What happens automatically

1. You work as normal.
2. When your model hits its **daily** limit, the plugin switches your session to the
   next model on the ladder and continues the task. You will see one line like:
   `Daily limit reached on google/gemini-3.5-flash-lite; switched to google/gemini-3.1-flash-lite.`
   It tries the models below yours first, then wraps around to the ones above it, so
   starting in the middle of the ladder (the repo default, `gemini-3.1-flash-lite`, is
   the second model) never skips the top one.
3. The plugin remembers which models are used up (in
   `.opencode/model-ladder-state.json`, which git ignores), so a new session does not
   start on a dead model.
4. **Used-up models come back when Google says they do.** Google's error usually says
   how long to wait ("Please retry in 1h1m15s"). The plugin marks the model used up for
   exactly that long, and never past midnight Pacific time, when Google resets every
   daily limit. If the error gives no wait, the model is back at midnight Pacific.
5. If every model on the ladder is used up, you get a message saying so, with your
   options: a teammate connects their own key, switch to a free OpenCode Zen model with
   `/models` (if your event allows it), or wait for midnight Pacific.

Short waits are **not** handled by the ladder. "Too many requests per minute" and
"model is experiencing high demand" (503) errors are retried by OpenCode itself, on the
same model, after a few seconds.

The state file looks like this (each model with the time it comes back, in UTC):

```json
{ "version": 2, "exhausted": { "google/gemini-3.1-flash-lite": "2026-10-11T19:01:15.000Z" } }
```

Deleting it is safe: the next daily-limit error simply writes it again.

## Which model am I on?

The model name is shown next to the agent name at the bottom of the OpenCode screen
(for example `build · gemini-3.1-flash-lite`). Type `/models` to see or change it.

## The ladder, and how to edit it

The list is at the top of `.opencode/plugins/model-ladder.lib.mjs`, in `LADDER`.
The first model is tried first. Newest flash-lite models come first (big daily budget),
then flash models as a last resort (small budget). Never add a Gemma model: its
per-minute token limit is smaller than a single OpenCode request.

After you edit it, check it:

```bash
python tools/check_model_ladder.py          # is the list well formed?
python tools/check_model_ladder.py --live   # which models answer on my key today?
```

`--live` sends one tiny request to each model, using the `GEMINI_API_KEY` in your
environment.

## Each person's key has its own budget

Limits belong to the Google project behind a key, not to the team. If your key is used
up, a teammate with their own key can `/connect` it and the whole ladder is fresh again.

## Limits

* Subagents with a `model:` pin in `.opencode/agents/*.md` are child sessions. The plugin
  sees their errors and switches them too, but a brand-new subagent always starts on its
  pinned model; if that model is used up today it fails once and is then switched.
* `opencode run` (one-shot, non-interactive) may exit on the first error before the
  plugin's "continue" message is processed. The switch is still remembered, so the next
  run starts on a live model.
