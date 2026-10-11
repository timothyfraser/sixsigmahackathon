---
description: "Run a task's definition_of_done and check it in to CONTRACT.yaml (e.g. /checkin H-03); commits only after your yes"
agent: build
model: google/gemini-3.1-flash-lite
---
Task id: $1
If the task id above is blank, use the task in CONTRACT.yaml that is in_progress; if there is none, or more than one, ask me which.

Check this task in, following the contract-ledger skill (.claude/skills/contract-ledger/SKILL.md).

1. Run the task's definition_of_done exactly as written in CONTRACT.yaml. Paste the command and its real output.
2. If it failed, stop: the task is not done. Leave status: in_progress, write what is missing in result, and tell me.
3. If it passed, edit only this task's block in CONTRACT.yaml: status: done, and result = one line saying what exists now and the check that proved it. Keep owner and started_at filled in (fill them if they are blank); never delete a field. Quote any value that contains a colon.
4. Check the ledger still parses: python -c "import yaml; yaml.safe_load(open('CONTRACT.yaml'))"
5. Show me git status, the diff, and the exact commit command, staging files by name (the task's owned files plus CONTRACT.yaml; never git add . or git add -A). Wait for my yes before committing. Never push.
6. End your final message with the definition_of_done output, pasted again, and the commit hash.
