# Engineering playbook

Load this when you need the "how do I work well" rules. Read one section, not the whole file.

**Contents:** (a) [Closed loops](#a-closed-loops) | (b) [CLI before MCP](#b-cli-before-mcp) | (c) [Context economy](#c-context-economy) | (d) [Single source of truth](#d-single-source-of-truth) | (e) [Definitions of done](#e-definitions-of-done) | (f) [Code as templates](#f-code-as-templates) | (g) [Model routine](#g-model-routine) | (h) [Git for teams](#h-git-for-teams)

This playbook is for engineers who use AI to build, not the other way around. The AI writes fast. You decide what is correct, and a check proves it.

## (a) Closed loops

**What it is.** A closed loop is a task you can finish without anyone's opinion. It ends in a command that passes or a URL that answers. An open loop ends in "it should work".

**The loop:** `SPEC.md` (what the tool is) -> `CONTRACT.yaml` (what is being done) -> build one task -> verify -> record (`status: done` plus a one-line `result`, same commit as the work).

**Decisions and why**
- Every task's `definition_of_done` is a command or a URL. If you cannot write the command, you do not yet know what "done" means. Fix that first.
- Every statistic gets two tests before any page exists: a **known answer** (a textbook or hand-calculated example the function must reproduce) and a **degenerate case** (one subgroup, all values equal, empty input: it must fail loudly or return a clear message, never a plausible wrong number). The rules are in `.claude/skills/stats-first-steering/SKILL.md`.
- Test the API from the outside: `curl -s -o /dev/null -w "%{http_code}\n" https://YOUR-URL/` prints `200` (use any cheap route your API has; the demos answer at `/`). Then call the real route with real data and compare the number with your known answer.
- Look at the page: take a screenshot at phone width and desktop width, then read both.
  `npx playwright screenshot --viewport-size "390,844" URL phone.png` and `npx playwright screenshot --viewport-size "1280,800" URL desktop.png`. (Or ask the Playwright MCP to do it.)
- Run `bash .claude/skills/superagent/scripts/check.sh` any time. It shows which tasks are done and what is next. Add `--team` once you have started: it fails if no task is checked in.
- **A green deploy is not a live app. The URL answering is.** A workflow can pass while the app crashes on start. Open the URL and call it.

**Things to avoid:** saying "done" with no pasted output; checking only that the code runs, not that the number is right; testing only on the happy path.

**Run and validate:** `bash .claude/skills/superagent/scripts/check.sh` prints `ok`, `todo` or `FAIL` per line and ends with `PASS` or `FAIL`.

## (b) CLI before MCP

**What it is.** A CLI is a command you type (`git`, `gh`). An MCP is a tool server your agent calls. Use the CLI when one exists.

**Why.** A CLI costs less context (no tool list loaded every session), gives the same output every time, and the command shows up in the transcript, so a teammate can rerun it.

| Job | Use this CLI | Why |
|---|---|---|
| History, branches, diffs | `git` | exact, scriptable, in the transcript |
| Pull requests, issues, Actions logs | `gh` (`gh pr create`, `gh run list`, `gh run view --log-failed`) | reads the failing deploy log without a browser |
| Python tests | `python -m pytest` | one line, exit code says pass or fail |
| R tests | `Rscript -e "testthat::test_dir('tests')"` | same idea for R |
| Is the API alive? | `curl` | status code and body in one line |
| Deploy to Posit Connect | `rsconnect` (Python) or `rsconnect` R package, through the demo's `deployme` script | the same command works by hand and in CI |
| JavaScript build and run | `npm` / `npx` | `npm run build` fails loudly |
| Run an R script | `Rscript file.R` | no IDE needed |
| Run a Python module or script | `python -m module`, `python -X utf8 file.py` | `-X utf8` avoids Windows encoding crashes |

**Use an MCP only where no CLI gives the agent the same thing:**
- **Playwright** lets the agent see a real browser page (click, screenshot, read the page).
- **Context7** gives current library docs, so the agent does not guess an old API.
- **motion's MCP** searches animation docs.

**Things to avoid:** installing an MCP for something `gh` or `curl` already does; leaving many MCPs on (each one adds its tool list to every session).

## (c) Context economy

**What it is.** The agent has a limited reading window. Everything loaded stays loaded, and a crowded window makes it forget and make mistakes.

**Decisions and why**
- **Always read, and nothing more:** `CLAUDE.md` or `AGENTS.md`, `SPEC.md`, `CONTRACT.yaml`, and the `/superagent` router. Keep these short.
- **Load a skill when its row fires.** The routing table says when. Do not preload skills "just in case".
- **Long files: read the table of contents, then grep.** The glossary (`.claude/skills/glossary/SKILL.md`) is about 1,400 lines. `grep -n "Control charts" .claude/skills/glossary/SKILL.md`, then read only that section.
- **One task per session or subagent.** Finish it, record it, start fresh.
- **Clear between tasks:** `/clear` in Claude Code, `/new` in OpenCode. Use `/compact` in Claude Code when a long session must go on.
- **Subagents return a short report** (what changed, the pasted test output, anything stuck), never file dumps.

**Things to avoid:** pasting whole files into chat; asking the agent to "read the whole repo"; one giant session for the whole weekend.

## (d) Single source of truth

**What it is.** Each fact lives in exactly one place. Everything else points to it.

- `SPEC.md` says what the tool is. `CONTRACT.yaml` says what is being done. `docs/plan.md` says how.
- **When they disagree, fix the document, not the code.** If the plan and the SPEC clash, decide which is right, edit the wrong document, then build.
- **One function per statistic.** The API route, the page and the tests all import it. If a number is computed in two places, they will drift.
- **Never copy a number into two places.** Not a limit, not a constant, not an example result. Compute it once, or put it in `data/` with the codebook.
- The method sentence in `SPEC.md` section 4 is the contract for the statistic. The code must match it word for word.

**Things to avoid:** a README that quotes numbers by hand; a front end that recomputes a statistic "to be safe"; two copies of a dataset.

## (e) Definitions of done

**What it is.** A command, plus the output it must print. Anyone can run it and get the same answer.

**How to write one:** (1) name the command, (2) say what it must print, (3) make it fail when the work is wrong.

| Work | Bad (cannot fail) | Good (a command and an output) |
|---|---|---|
| X-bar/R function | "the control chart function works" | `python -m pytest tests/test_qc.py` passes, and it includes: the textbook example reproduces the book's center line and limits to 3 decimals, and a single subgroup raises a clear error |
| API route | "the endpoint is up" | `curl -s -X POST URL/xbar -d @data/planted_shift.json` returns HTTP 200 and `out_of_control: true` for the planted row |
| Page | "looks nice" | screenshots at 390px and 1280px show the chart, the number with its unit, and the one-line "how to read this", with no sideways scroll |
| Deploy | "the workflow is green" | `curl -s -o /dev/null -w "%{http_code}\n" URL/` prints `200` after the deploy, and the route from the API row returns the right number on the live URL |

**Things to avoid:** "should work", "looks right", a done task with an empty `result`.

## (f) Code as templates

**What it is.** Copy a working starter, change it. Do not ask the AI to invent a project layout.

- Copy **ONE** folder from `demos/` (`fastapi`, `plumber`, `reactfront`, `shinyapp`, `pypackage`, `rpackage`) into `app/`. `demos/README.md` has the list. Do not edit `demos/` in place.
- Keep the **four-script contract** in `app/`: `testme`, `manifestme`, `deployme`, `README.md`. One command each, no arguments.
- Deploy workflows come from `.claude/skills/connect-publish/workflows/`. Copy one to `.github/workflows/`. Steps are in `.claude/skills/connect-publish/README.md`.
- Blank `SPEC.md`, `CONTRACT.yaml`, `CLAUDE.md`, `AGENTS.md` for a fresh repo are in `.claude/templates/`.
- Write the statistic in a plain function file (`app/qc.py` or `app/qc.R`) that the template calls.

**Things to avoid:** generating a framework from scratch when a template exists; mixing two stacks in one `app/`; editing the template and the copy.

## (g) Model routine

**What it is.** Think with the strongest model you have, build with a cheaper one.

- **Pro plan:** plan on the strongest model (SPEC, `docs/plan.md`, the hard design choices). Then switch to the cheaper, faster model and orchestrate cheap subagents: one task each, disjoint files, about 15 minutes each. Run subagents in parallel only when their files do not overlap. You review each diff before it is kept.
- **Free Google tier:** one agent at a time, small steps, `/new` between tasks. Rate limits are the problem here, not intelligence. See `docs/opencode.md`.
- Use the strongest model again for review of the statistic, since a wrong formula costs the most.

**Things to avoid:** the strongest model on every small edit; many agents editing the same file; letting an agent run past about 15 minutes without a look.

## (h) Git for teams

- **One branch per person or per task.** `git switch -c h-03-xbar`. Merge by pull request, and a teammate reads the diff.
- **Small commits** that each pass the tests. A commit message says what and why in one line.
- **Stage explicit paths:** `git add app/qc.py tests/test_qc.py`. Never `git add -A` or `git add .`, they sweep in files you did not mean to share.
- **Update with `git pull --no-rebase`.** Do not rebase a branch a teammate is using.
- **Never commit `.env`**, a key, a token or a server address. Keys go in GitHub repo secrets or a gitignored `.env`. If one slips into a commit, tell a mentor and rotate the key: deleting the file does not remove it from history.
- Check in a task in the same commit as the work, so the ledger never lies about the code.

**Run and validate:** `git status` shows only the files you meant; `git diff --staged` reads clean before every commit.
