# AGENTS.md: <tool name>

Read before doing anything: `SPEC.md` (what the tool is) and `CONTRACT.yaml` (what is being done).
For Codex, Cursor, Copilot, Gemini and any agent that reads AGENTS.md. Claude Code reads `CLAUDE.md`;
keep the two in step.

## How work happens here
- **One task at a time.** Nothing gets built that is not a task in `CONTRACT.yaml`. No task? Propose one
  and wait for a human to agree.
- Check the task out before starting; check it in (`status: done` + a one-line `result`) in the same
  commit as the work. Write only inside the task's `owns` paths.
- **Verify, don't claim.** Run the task's `definition_of_done` and quote what it printed. If it failed,
  the task is not done. Say so.
- Keep each change small enough for a human to read the whole diff.

## Statistics come first
- State the method in words (SPEC section 4) before writing code for it.
- Write the statistic as a plain function first; wrap it in an API or UI only after its test passes.
- Every statistic gets a test against a known answer (textbook example or hand calculation) and a
  degenerate case (constant data, n = 1, missing values).
- Never invent data and present it as real. Test data lives in `data/` with a codebook.
- Say which assumptions a method needs (normality, independence, subgroup size) and how the tool checks them.
- If you are unsure a formula is right, say so and show the source. Do not guess quietly.

## Hard rules
- Never write a password, token or API key into a file, commit, log or chat. Secrets live in `.env`
  (gitignored) or your deploy host's secret store.
- Stage explicit paths: `git add <files>`, never `git add -A` or `git add .`.
- Do not add a dependency, framework or feature the SPEC does not ask for.

## Commands
- Run locally: `<./testme.sh or Rscript testme.R>`
- Test: `<pytest or Rscript -e "testthat::test_dir('tests')">`
- Deploy: `<./deployme.sh or Rscript deployme.R>`
