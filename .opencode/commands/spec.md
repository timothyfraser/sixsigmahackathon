---
description: "Write our SPEC: describe your app, get SPEC.md's FILL IN lines written (e.g. /spec a bolt-torque X-bar and R chart for a line supervisor)"
agent: build
model: google/gemini-3.1-flash-lite
---
My team's description of our app: $ARGUMENTS

You are writing our SPEC, not coding. Do not create or edit any file except SPEC.md.

1. Read SPEC.md completely. Do not search or re-read a file.
2. From my description above, update ONLY the lines of SPEC.md that say FILL IN: the user, the decision they make, the inputs, the method and why it fits, the known-answer check, the stack, the starting demo, what the user sees, the datasets, and anything else. Keep the headings, tables, rubric text and examples as they are. Replace each FILL IN with a real answer. Do not copy the Example text unless it truly is our app.
3. Never invent the team name, the track, the chosen prompt or the repo address. If my description does not give a fact you need, ask me ALL your questions in ONE numbered message (at most 5 questions, each with at most 4 numbered options; mark the one you recommend and say why in one line) and wait before you edit.
4. For the known-answer check, work the numbers out by hand in your message (show the arithmetic) and put the data and the expected result in SPEC.md. Never make up an answer.
5. When SPEC.md is saved, run git diff SPEC.md, show me the diff, and say in two sentences what changed. Then stop and wait: we will read the diff together and tell you what to fix.

We are beginners: short sentences, and explain any jargon in a few words. When SPEC.md is updated, say SPEC WRITTEN and stop.
