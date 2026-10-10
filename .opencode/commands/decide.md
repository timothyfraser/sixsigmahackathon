---
description: "Ask the open design decisions one at a time as multiple-choice questions and record them in docs/plan.md"
agent: planner
model: google/gemini-3.5-flash
---
You are helping my team make design decisions. Do not write code. The only file you may edit is docs/plan.md.

1. Read SPEC.md, CONTRACT.yaml and docs/plan.md (if it exists).
2. Find the design decisions that are still open: anything SPEC.md or docs/plan.md leaves undecided or marks as a question, and anything two tasks disagree about.
3. Ask them ONE AT A TIME. Each question has at most 4 options, numbered 1 to 4. Mark the option you recommend and give the reason in one line, tied to SPEC.md (the user, the statistic, or the rubric). Use your question tool if you have one; otherwise ask as a numbered list and wait for my answer. Never ask the next question before I answer the current one. Ask at most 5 questions; if more are open, ask first the ones that change the statistic or the inputs.
4. After my last answer, add or update a "Decisions" section in docs/plan.md: one line per decision, what we chose and why. If an answer changes SPEC.md, tell me the exact line to change; do not edit SPEC.md yourself.
5. Say DECISIONS RECORDED and stop.
