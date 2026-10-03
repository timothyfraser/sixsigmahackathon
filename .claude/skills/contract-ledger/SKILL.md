---
name: contract-ledger
description: Work one task at a time from CONTRACT.yaml - check a task out before starting and check it in (status done + one-line result) in the same commit as the work. Load when asked to start, pick up, claim, finish or check in a task, when about to build something, or when someone says "check out H-03" or "what's next".
---

# contract-ledger

`CONTRACT.yaml` is the team's task ledger; `SPEC.md` says what the tool IS. Templates for both are in
[`kit/`](../../../kit/README.md). Copy them to your repo root first.

## Before any work: is there a task?

Find the task in `CONTRACT.yaml` that covers the request. If none does, **propose** a new block (append it,
never rewrite another task) with `id`, `title`, `status: todo`, `owner: ""`, `owns: [...]` (the paths it
will write) and a `definition_of_done` that is a command that passes, a file that exists or a URL that
answers. Wait for a human to agree before building it.

## Check out

Edit only that task's block:

```yaml
    status: in_progress
    owner: "<name, or agent + teammate>"
    started_at: "<YYYY-MM-DD HH:MM>"
```

Refuse to check out a task that a teammate already has `in_progress`. Say so and suggest another.

## Work

Write only inside the task's `owns` paths. Need something outside them? Stop and add a task first.
Keep the change small enough for a human to read the whole diff.

## Check in

1. Run the `definition_of_done` exactly as written and quote what it printed. If it fails, the task is not done.
2. Edit the block:

   ```yaml
       status: done
       result: "<one line: what exists now and the check that proved it>"
   ```

3. Commit the work and the ledger together, staging explicit paths:
   `git add <owned paths> CONTRACT.yaml && git commit -m "H-03: <title>; check in"`.
4. If the check only partly passed, leave `status: in_progress` and write what is missing in `result`.

## Check the ledger parses

```bash
python -c "import yaml; yaml.safe_load(open('CONTRACT.yaml'))"
```

Quote any string that contains a colon. No tabs.
