---
description: "Write the project plan (docs/plan.md) from SPEC.md and CONTRACT.yaml; asks all open design questions in one numbered list"
agent: planner
model: google/gemini-3.5-flash
---
You are planning, not coding. Do not create or edit any file except docs/plan.md. This model allows only 5 requests a minute, so use as few steps as you can.

1. In one step, read SPEC.md, CONTRACT.yaml and docs/plan.md (if it exists) completely, before you say anything. Do not search, list folders or re-read a file.
2. In one sentence each, state: the user, the question the tool answers, every statistic, and the formula for each statistic (write the formula out). If SPEC.md leaves any of these unclear or still says FILL IN, stop and ask me before going on. A known-answer check with no concrete numbers (the input data AND the expected values) counts as FILL IN: stop, and offer to work out the numbers with me.
3. List every design decision that is still open (data shape, where the data comes from, what the function or API returns, what the user sees, what counts as "in control" or "capable"). Ask them ALL in this ONE message, as a numbered list: at most 5 questions, each with at most 4 numbered options; mark the option you recommend and say why in one line. Then stop and wait. I will answer in one reply, for example "1-1, 2-3, 3-1". If nothing is open, say so and go straight to step 4.
4. In your next turn, after my answers, write docs/plan.md: a numbered list of tasks, each mapped to one task id from CONTRACT.yaml (use the real ids; never invent one). For each task give: the files it may touch (from its owns list), the test that proves it (the known answer from SPEC.md section 4, AND a degenerate case such as constant data), and a time estimate. Every statistic comes first, each with its formula written out, then the tool around it, then the page or chart. Nothing about styling until the numbers are proven.
5. Under the tasks, list the decisions I made in step 3, one line each.
6. End with the three biggest risks and what we will do about each.

Keep docs/plan.md under 60 lines. We are beginners: short sentences, and explain any jargon in a few words. When docs/plan.md is written, say PLAN WRITTEN and stop.
