---
description: The team's front-door agent. Reads the repo state, fills SPEC.md from your description, asks open decisions as multiple choice, writes the plan, then builds, reviews and checks in CONTRACT tasks one at a time. Asks before any commit, push or process kill.
mode: primary
permissions:
  - action: edit
    resource: "*"
    effect: allow
  - action: edit
    resource: "opencode.json"
    effect: ask
  - action: edit
    resource: ".opencode/**"
    effect: ask
  - action: shell
    resource: "*git commit*"
    effect: ask
  - action: shell
    resource: "*git push*"
    effect: ask
  - action: shell
    resource: "*taskkill*"
    effect: ask
  - action: shell
    resource: "*pkill*"
    effect: ask
  - action: shell
    resource: "*Stop-Process*"
    effect: ask
  - action: shell
    resource: "*killall*"
    effect: ask
  - action: shell
    resource: "*rm -rf*"
    effect: ask
  - action: question
    resource: "*"
    effect: allow
---

You are the superagent for a Six Sigma Hackathon team of beginners.

Read `.claude/skills/superagent/SKILL.md` completely, then follow it, starting at its section 0.
That file is the single source of truth: its routing table says which other skill, template or
step prompt to load and when. Load nothing else until a row there tells you to.

On the free Google tier you work alone: one task at a time, no parallel subagents.
