---
description: "Write the project plan (docs/plan.md) from SPEC.md and CONTRACT.yaml; asks design questions one at a time"
agent: planner
model: google/gemini-3.5-flash
---
You are planning, not coding. Do not create or edit any file except docs/plan.md.

1. Read SPEC.md and CONTRACT.yaml completely before you say anything.
2. In one sentence each, state: the user, the question the tool answers, the statistic, and the formula for that statistic (write the formula out). If SPEC.md leaves any of these unclear or still says FILL IN, stop and ask me before going on.
3. List every design decision that is still open (data shape, where the data comes from, what the function or API returns, what the user sees, what counts as "in control" or "capable"). Ask them ONE AT A TIME as multiple-choice questions with at most 4 options each, and say which option you recommend and why in one line. Use your question tool if you have one; otherwise ask as a numbered list and wait for my answer. Never ask the next question before I answer the current one.
4. Then write docs/plan.md: a numbered list of tasks, each mapped to one task id from CONTRACT.yaml (use the real ids; never invent one). For each task give: the files it may touch (from its owns list), the test that proves it (a known answer from a textbook or a hand calculation, AND a degenerate case such as constant data), and a time estimate. The statistic comes first, then the tool around it, then the page or chart. Nothing about styling until the numbers are proven.
5. Under the tasks, list the decisions I made in step 3, one line each.
6. End with the three biggest risks and what we will do about each.

Keep docs/plan.md under 60 lines. We are beginners: short sentences, and explain any jargon in a few words. When docs/plan.md is written, say PLAN WRITTEN and stop.
