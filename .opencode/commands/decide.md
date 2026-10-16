---
description: "Ask the open design decisions as one numbered multiple-choice list and record your answers in docs/plan.md"
agent: planner
model: google/gemini-3.5-flash
---
You are helping my team make design decisions. Do not write code. The only file you may edit is docs/plan.md. This model allows only 5 requests a minute, so use as few steps as you can.

1. In one step, read SPEC.md, CONTRACT.yaml and docs/plan.md (if it exists). Do not search or re-read a file.
2. Find the design decisions that are still open: anything SPEC.md or docs/plan.md leaves undecided or marks as a question, and anything two tasks disagree about.
3. Ask them ALL in this ONE message, as a numbered list: at most 5 questions (if more are open, pick the ones that change the statistic or the inputs), each with at most 4 numbered options. Mark the option you recommend and give the reason in one line, tied to SPEC.md (the user, the statistic, or the rubric). Then stop and wait. I will answer in one reply, for example "1-1, 2-3, 3-1".
4. In your next turn, after my answers, add or update a "Decisions" section in docs/plan.md: one line per decision, what we chose and why. If an answer changes SPEC.md, tell me the exact line to change; do not edit SPEC.md yourself.
5. Say DECISIONS RECORDED and stop.
