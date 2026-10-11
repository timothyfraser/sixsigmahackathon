---
description: "Diagnose a stall: 429 or quota, a silent hang, a deprecated model, a loop (e.g. /stuck <paste the error>)"
agent: build
model: google/gemini-3.1-flash-lite
---
I am stuck. What I see (the error text or the symptom): $ARGUMENTS

Diagnose before doing anything else. Do not edit any file in this step.

1. Restate the problem in one sentence and say which of these it is:
   a. 429, RESOURCE_EXHAUSTED, "quota" or "rate limit": the free key's per-minute or per-day allowance is used up. Fixes, in this order: for a per-minute limit (the error says "retry in" some seconds), wait one minute, then type continue in the SAME session (do not start a new session: a new one repeats every step it already did and hits the same limit); for a daily limit, step down the model ladder (another model ending in -flash for planning and thinking, the other model ending in -flash-lite for building); a teammate's key from their own Google account; and only if your employer allows third-party AI vendors, a Zen model whose name ends in -free, or GitHub Copilot. After switching models, if a slash command still fails the same way, paste that command's prompt from docs/prompts-starter.md instead, because each slash command asks for a fixed model.
   b. Nothing happens, no answer and no error: usually no key is connected. In OpenCode type /connect, choose Google, paste your key, then pick a model with /models.
   c. "Model ... has been deprecated": the agent was started outside the repo folder. Close it, cd into the repo, and start it again.
   d. The same error three times in a row: the task is too big. Start a fresh session, shrink the task to the smallest piece that can be tested, and put the error text in the new prompt.
   e. Answers are slow or vague: the session is too long. Compact it (/compact in OpenCode) or start a fresh one.
   f. A test or a command fails: show the exact command and its output, and say what you think is wrong in one sentence.
   g. Something else: say so plainly.
2. Give me ONE next step to try, as a command or a sentence I can type. If it is a code change, describe it and wait for my yes.
3. If you do not know, say "I don't know" and suggest asking a mentor. Never guess at a fix to a statistic.
