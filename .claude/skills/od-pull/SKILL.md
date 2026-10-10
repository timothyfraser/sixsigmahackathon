---
name: od-pull
description: Pull a design made in Open Design (OD) into your team repo through the open-design MCP server, then implement it against your real data. Use when someone says "pull this design into the repo", "implement this design", "export the OD artifact", "build this screen from the prototype", or "get the design tokens from Open Design".
---

# od-pull: bring an Open Design design into your repo

Prereq: Open Design is running and connected (skill [`od-setup`](../od-setup/SKILL.md)).
Design is the last mile. Do this only after the statistics task in `CONTRACT.yaml` is checked in.

## 1. Find the design

- `get_active_context`: what is open right now. Use this when someone says "this design".
- `list_projects`, `get_project`, `list_files`, `search_files`: when they name a project or screen.

If a name matches more than one project, confirm which one before going on.

## 2. Pull it

- `get_artifact`: preferred. Returns the entry file plus every file it references (token CSS, JSX, assets)
  in one call.
- `get_file(path)`: one specific file (long files come back in pages; re-call with the next offset).

## 3. Save it, then implement it separately

1. Save the pulled files under `design/<screen>/`, not straight into your app's source.
2. Add a short `design/<screen>/README.md`: project name, date pulled, one line on what the screen is for.
3. In a separate task, turn it into real components: replace placeholder numbers with your API's real
   field names and outputs, keep units and the "how to read this" line, and check it at phone width (375px).

## Don't

- Don't let a design add inputs or outputs the SPEC does not have. Change the SPEC first.
- Don't commit `.mcp.json` or any local path or port.

Check: `design/<screen>/` holds the pulled files and a README, and the implemented view shows real
results from one test dataset.
