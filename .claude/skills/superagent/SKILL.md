---
name: superagent
description: The one front door for a Six Sigma Hackathon team. Reads the repo's state, fills in SPEC.md from the team's own description, asks every open design decision as one set of multiple-choice questions, writes the plan, then builds, reviews, checks in and deploys the CONTRACT.yaml tasks one at a time, loading every other skill, template and plugin on its own. Use when someone types "/superagent" (with or without an app idea), says "superagent", "plan our app", "build our tool", "what's next", "where are we", "keep going", or makes any request to start or continue the hackathon project.
---

# superagent: from an app idea to a deployed, tested tool

You are the team's engineer-in-the-loop agent. The team describes their app; you do the rest, one
small verified step at a time. They should never need to know the other skills exist. The point is
not fast code: it is **correct statistics they can explain**, built with closed loops.

Agents without a `/superagent` command (Cursor, Codex, Copilot, Gemini, Open Design's agents) get
here through `AGENTS.md`: when the user types "/superagent" or "superagent", read this file and follow it.

**Contents:** [0 When invoked](#0-when-invoked) · [1 Routing table](#1-routing-table) ·
[2 Models and budget](#2-models-and-budget) · [3 Closed loops](#3-closed-loops) ·
[4 CLI before MCP](#4-cli-before-mcp) · [5 Context economy](#5-context-economy) ·
[6 Gotchas](#6-gotchas) · [7 Charter for a subagent](#7-charter-for-a-subagent)

## 0. When invoked

Do these in order, without being asked. `$ARGUMENTS` (or whatever the user typed after
"superagent") is the team's description of their app; it may be blank.

1. **Read the state, not your memory.** Run `bash .claude/skills/superagent/scripts/check.sh`
   and read `SPEC.md` and `CONTRACT.yaml` completely. Paste the check output. Read `docs/plan.md`
   too if it exists.
2. **Tool check, once.** If you have no browser tool (Playwright) or no library-docs tool
   (Context7), or the team wants a UI polish (impeccable) or animation (motion.dev), ask ONE
   question: "Set up the recommended tools now? (about 5 minutes)". On yes, follow
   `.claude/skills/superagent/setup.md`. On no, carry on and do not ask again this session.
3. **Fill SPEC.md.** If `SPEC.md` still has `FILL IN` lines, write them from the team's
   description, following the rules in `.opencode/commands/spec.md` (steps 2-5). Never invent the
   team name, the track, the chosen prompt or the repo URL: ask. Work the known-answer numbers out
   by hand, in the chat, with the arithmetic shown. Show `git diff SPEC.md`.
4. **Say where they are, in plain words.** What is done, and the next 3-6 CONTRACT tasks with their
   ids and one line each. Tasks run in the CONTRACT order (H-01 to H-08), except: make the public
   repo (the first half of H-08) as soon as H-04 works, so H-06 can deploy early.
5. **Ask every open decision at once.** Collect every open design choice (data shape, inputs, what
   the function returns, what the user sees, what counts as "in control" or "capable", the stack).
   Ask them all in ONE go, as multiple choice, recommended option first, each with a one-line
   reason tied to `SPEC.md`:
   - Claude Code: the AskUserQuestion tool, up to 4 questions, 2-4 options each.
   - OpenCode: the `question` tool, or a numbered list.
   - Any other agent: a numbered list the team answers in one line, like "1-1, 2-3, 3-1".
   Never decide an open question silently. If nothing is open, say so and go on.
6. **Write `docs/plan.md`** following `.opencode/commands/plan.md` (steps 4-6, under 60 lines):
   tasks mapped to real H-ids (never invent one), each with its `owns` paths, its known-answer test
   AND degenerate test, and every statistic's formula written out. Statistics first, then the tool,
   then the page. Add a Decisions section with the answers from step 5.
7. **Roll, one CONTRACT task at a time.** For each task:
   - **Build:** hand it to the `implementer` subagent BY NAME, never a generic one (Claude Code:
     the Agent/Task tool with `subagent_type: "implementer"`, defined in `.claude/agents/implementer.md`;
     OpenCode: `.opencode/agents/implementer.md`) with the charter in section 7. With no subagents,
     follow `.opencode/commands/build.md` yourself.
   - **Review:** any task that computes a statistic goes to the `stats-reviewer` subagent, in a
     fresh context (Claude Code: `subagent_type: "stats-reviewer"`, defined in
     `.claude/agents/stats-reviewer.md`). With no subagents, the team
     runs `.opencode/commands/review.md` in a NEW session. No PASS table, no check-in.
   - **Check in:** follow `.opencode/commands/checkin.md`. Run the `definition_of_done` exactly as
     written and paste its output.
   - **Deploy early:** H-06 as soon as H-04 runs locally. A live URL by mid-event leaves time to fix.
   - After each task, run `check.sh` again and say what is next.

   **Stop for the human only** at a real choice, before any `git commit` or `git push` (show the
   diff and the exact command, then wait for "yes"), and when a deploy credential is needed (the
   team pastes it into GitHub repo secrets or their own terminal, never into chat or a file).

## 1. Routing table

Load a resource only when you reach its row. Read long files by section, never whole.

| When you are about to ... | Load or use |
|---|---|
| start, claim or finish any task | skill `.claude/skills/contract-ledger/SKILL.md` |
| write or accept ANY statistics code | skill `.claude/skills/stats-first-steering/SKILL.md` (before the first line) |
| define or check a course term or symbol (Cpk vs Ppk, d2, MTBF ...) | `.claude/skills/glossary/SKILL.md`, by section only: grep the term, read its TOC entry, then read that one section. Never the whole file (1,400+ lines) |
| pick a starter for the tool | `demos/README.md`, then copy ONE folder from `demos/` into `app/` |
| build a Python API, maybe with React | skill `.claude/skills/fastapi-react-scaffold/SKILL.md` |
| build an R API, maybe with React | skill `.claude/skills/plumber-react-scaffold/SKILL.md` |
| write a README judges can follow (H-07) | `demos/making_readmes/` |
| deploy to Posit Connect (H-06) | skill `.claude/skills/connect-publish/SKILL.md`; workflows in `.claude/skills/connect-publish/workflows/` |
| deploy more than once, from CI, or with shared keys | skill `.claude/skills/posit-dlc/SKILL.md` |
| set up or pull from Open Design (only if the team uses it) | skills `.claude/skills/od-setup/SKILL.md`, `.claude/skills/od-pull/SKILL.md` |
| start a SECOND project in a new repo | blank files in `.claude/templates/` (SPEC, CONTRACT, CLAUDE, AGENTS) |
| install Playwright, Context7, impeccable, motion.dev, posit-dev skills | `.claude/skills/superagent/setup.md` |
| check the repo state | `bash .claude/skills/superagent/scripts/check.sh` (`--team` also requires one task done) |
| look up a closed loop, a definition of done, a template, the model routine | `.claude/skills/superagent/reference/playbook.md`, by section |
| call any library API (FastAPI, plumber, React, pandas, ...) | Context7, when installed: look it up, do not guess |
| see what you built | Playwright, when installed: open the page, read it, take a screenshot |
| polish a UI (only after the statistics pass review) | impeccable, when installed; end with a Playwright screenshot |
| animate something | motion.dev's `/motion` skill, when installed |
| write an R package, a Shiny app or a Quarto doc | posit-dev skills, when installed |
| run one step by hand, the fixed way | the step prompts: `/spec /plan /decide /build /review /checkin /stuck` in OpenCode (`.opencode/commands/`); the same text for any agent in `docs/prompts-starter.md` |
| explain the working routine to the team (set up, plan on a strong model, switch down to build) | `docs/start.md` |
| check what earns points | `docs/criteria.md` (the 100-point rubric) |
| find the event prompts | `docs/prompts.md`: they appear on Devpost at kickoff. Never invent one |
| explain a method the course way | the course textbook, https://timothyfraser.com/sigma/ |
| hit a 429, a hang, or the same error 3 times | `.opencode/commands/stuck.md` |

## 2. Models and budget

**Pro tier (Claude Code):** plan on the strongest model, build on a cheaper one.
1. `/model opus` for sections 0.1-0.6: SPEC, decisions, plan.
2. `/model sonnet` to orchestrate. Hand each CONTRACT task to a Sonnet subagent
   (`.claude/agents/implementer.md`, `.claude/agents/stats-reviewer.md`): one task each, disjoint
   `owns`, small enough to finish in about 15 minutes. Run subagents in parallel only when their
   files do not overlap (H-02 data and H-07 README can; H-03 and H-04 cannot).
3. `/clear` or `/compact` between tasks. The ledger and `docs/plan.md` hold the state, not the chat.

**Free Google tier (OpenCode):** one agent at a time, no parallel subagents (one key's per-minute
limit cannot feed two). Plan on `google/gemini-3.5-flash`, build on `google/gemini-3.1-flash-lite`.
Follow `docs/opencode.md` and `docs/model-ladder.md`. On a 429, wait a minute and type `continue`.

## 3. Closed loops

A step is done when a command says so, not when you think so (details: `reference/playbook.md`).
- Every task's `definition_of_done` is a command. Run it exactly as written; paste the output.
- Every statistic has a known-answer test (numbers from `SPEC.md` section 4) and a degenerate test
  (constant data or n = 1: a clear error or NaN/None with a message, never inf or 0).
- An API: start it in the background, `curl` its health route and one real endpoint on a `data/` file.
- A page: open it with Playwright and read it. A deploy: open the public URL logged out.
- After every task: `bash .claude/skills/superagent/scripts/check.sh`.
- Never say "done", "works" or "should work" without pasted output.

## 4. CLI before MCP

A command-line tool is cheaper, faster and more exact than an MCP server. Use MCP only where no CLI does the job.

| Job | Use |
|---|---|
| history, diffs, staging | `git` (stage explicit paths) |
| repo, secrets, workflow runs | `gh` (`gh run list`, `gh run view`) |
| tests | `pytest` (Python), `Rscript -e "testthat::test_dir('tests')"` (R) |
| hit an API | `curl` |
| deploy | `rsconnect` (R) or `rsconnect-python` via the demo's `deployme` script |
| front end | `npm` |
| a real browser, library docs, animation | MCP: Playwright, Context7, motion.dev |

## 5. Context economy

- Always read: this file, `SPEC.md`, `CONTRACT.yaml` (and `docs/plan.md` once it exists). Nothing else.
- Everything else is loaded at the row in section 1 that needs it, and read by section (heading or grep).
- Subagents keep the main thread small: they read the code and run the tests; you read their report.
- One task per subagent or session. Start fresh between tasks; the files carry the memory.

## 6. Gotchas

These cost teams hours before. The step prompts in `.opencode/commands/` hold the full rules.
- sigma-hat for Cp and Cpk is R-bar/d2 (within-subgroup). The overall standard deviation gives Pp and Ppk, a different statistic.
- Deliver EVERY statistic `SPEC.md` names. For an X-bar and R chart: X-bar limits (A2), R limits (D3, D4), Cp/Cpk, an out-of-control flag per subgroup.
- Never run a server or `testme` in the foreground: it hangs the session. Background it with a time limit; stop it by its PID.
- Never kill processes by name (`taskkill /IM`, `pkill`, `killall`, `Stop-Process -Name`).
- The requirements file lists every third-party import, in the same step as the import.
- Absolute imports (`from app.qc import ...`); everything starts from the repo root with one command.
- No secrets in files, commits, logs or chat. Keys go in GitHub repo secrets or a gitignored `.env`.
- The prompts are on Devpost. Never invent or guess one.
- Stage explicit paths: `git add <file> ...`, never `git add .` or `-A`. Commit only after a yes.
- Write only inside the task's `owns` paths. Need another file? Stop and say which, and why.

## 7. Charter for a subagent

Give every subagent exactly these six fields, short:

```text
MISSION:    one sentence, the CONTRACT task's title in your words.
READ FIRST: SPEC.md (section 4), docs/plan.md, this task's block in CONTRACT.yaml,
            and the skill its row in the routing table names.
OWNS:       the task's owns list, plus its block in CONTRACT.yaml. Nothing else.
TASK ID:    H-0n
VERIFY:     the task's definition_of_done, plus the known-answer and degenerate tests.
REPORT:     STATISTICS, FILES, RUN, TESTS, DEFINITION OF DONE (real output pasted),
            STATUS: READY FOR REVIEW or NOT DONE. No commit, no push, no check-in.
```

Read the report. If any output is missing or summarized, the task is not done: send it back.
