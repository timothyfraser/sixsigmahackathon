---
name: od-setup
description: Install Open Design (OD) and connect its MCP server to your coding agent. Use when someone says "set up Open Design", "install od", "connect Claude/Codex/Cursor to Open Design", "the open-design MCP won't connect", "open-design tools missing", or "failed to reach daemon".
---

# od-setup: install Open Design and connect it to your agent

Open Design is a free, open-source (Apache-2.0), local-first design workspace. Each project holds a
rendered design (HTML/JSX/CSS) plus its source files, and an MCP server lets your agent read the design you
have open. Overview: [`docs/tools.md`](../../../docs/tools.md#open-design).

## 1. Install

Download the desktop app (macOS or Windows) from <https://open-design.ai>. On Linux, run from source
(see <https://github.com/nexu-io/open-design>). Keep your agent, the `od` command and the app on the **same**
machine and environment (for example, all in Windows or all in WSL, not split).

## 2. Connect your agent

Prefer the snippet the app gives you over writing one by hand:

- In the app: **Settings > MCP server** shows the config for this install.
- Or from a terminal where `od` works:

  ```bash
  od mcp install claude --print   # dry run: shows what it would write, changes nothing
  od mcp install claude           # or: codex, cursor (see: od mcp install --help)
  ```

- Restart your agent session so it re-reads its MCP config.

## 3. If the tools vanish ("failed to reach daemon")

Some configs bake in a fixed port. After an app restart or upgrade the port can change and the baked one
goes stale. Do not hand-edit the port: rerun `od mcp install <agent>` (with `--print` first) or re-copy the
snippet from Settings, then restart the agent.

## Don't

- Don't commit `.mcp.json` or any agent config that contains a local path or port.

Check: your agent's tool list shows the `open-design` tools, and `list_projects` returns your projects
without an error.
