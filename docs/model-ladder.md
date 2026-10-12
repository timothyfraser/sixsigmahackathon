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
3. The plugin remembers which models are used up today (in
   `.opencode/model-ladder-state.json`, which git ignores), so a new session does not
   start on a dead model. The list clears itself at midnight Pacific time, when Google
   resets the limits.
4. If every model on the ladder is used up, you get a message saying so, with your
   options: a teammate connects their own key, switch to a free OpenCode Zen model with
   `/models` (if your event allows it), or wait for midnight Pacific.

Short waits are **not** handled by the ladder. "Too many requests per minute" and
"model is experiencing high demand" (503) errors are retried by OpenCode itself, on the
same model, after a few seconds.

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
