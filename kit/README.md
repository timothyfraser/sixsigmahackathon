# Starter kit: build with an AI agent without wasting your budget

Copy the four files in this folder into the root of **your team's repo**:
[`SPEC.md`](SPEC.md), [`CONTRACT.yaml`](CONTRACT.yaml), [`CLAUDE.md`](CLAUDE.md), [`AGENTS.md`](AGENTS.md).

## Why spec first

An agent with no spec guesses. Each guess spends tokens, and you then spend more tokens undoing it.
A one-page spec tells the agent who the user is, which statistic to compute and what "done" looks like,
so it builds the right thing the first time. A contract breaks the work into small tasks, each with a
check you can run, so you always know what is finished and what is just "probably fine". Writing it
takes your team about 20 minutes, and it is also most of the rubric's Tool Design section
([`docs/criteria.md`](../docs/criteria.md)).

## The 15-minute loop

1. **Write the SPEC** together, out loud (try [Wispr Flow](../docs/tools.md#wispr-flow)). Fill every `<...>`.
2. **List tasks in CONTRACT.yaml.** Each one gets a `definition_of_done` that is a command, a file or a URL.
3. **Let the agent build ONE task.** Prompt: *"Read SPEC.md and CONTRACT.yaml. Check out H-03 and do only that."*
4. **Check it.** Run the definition of done yourself. Read the diff. Can you explain every number it prints?
5. **Commit** the work and the ledger change together. Next task.

If a loop runs past 15 minutes, stop the agent, make the task smaller, and start again.

## More

- Skills your agent can load: [`contract-ledger`](../.claude/skills/contract-ledger/SKILL.md),
  [`stats-first-steering`](../.claude/skills/stats-first-steering/SKILL.md),
  [`od-setup`](../.claude/skills/od-setup/SKILL.md), [`od-pull`](../.claude/skills/od-pull/SKILL.md).
- Which agent to use and what it costs: [`docs/agents.md`](../docs/agents.md).
- Dictation and design tools: [`docs/tools.md`](../docs/tools.md).
