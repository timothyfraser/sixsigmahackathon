# Superagent setup: install the helper tools

For the AGENT to run, and for the student to read along. Do this once per computer or project, not every session.
Tags: VERIFIED = the command was run or its `--help` read on 2026-10-16. UNVERIFIED = taken from vendor docs or memory; if it fails, tell the student and stop guessing.

## Contents
1. What gets installed and why
2. Requirements
3. Already wired in this repo
4. Claude Code: commands the agent runs
5. OpenCode
6. Cursor, Codex, Copilot, Gemini CLI
7. motion.dev (the one step a human types)
8. Smoke test
9. Troubleshooting

## 1. What gets installed and why
- **Playwright** (MCP server): the agent's own browser. It opens the page it just built and looks at it, instead of guessing.
- **Context7** (MCP server): current library docs on demand, so the agent does not code from stale memory.
- **impeccable** (plugin): UI design quality. It stops the "generic AI look".
- **motion.dev AI Kit** (skill plus MCP): animation done well. Optional; skip it if the app has no motion.
- **posit-dev skills** (plugins): R packages, Shiny, Quarto. Install only what the app uses.

An MCP server is a small helper program the agent can call. A plugin is a bundle of skills and agents.

## 2. Requirements
- Node.js 18 or newer. Check: `node -v`. The commands use `npx`, which ships with Node.
- Internet access, and `git` (plugin marketplaces are cloned from GitHub).
- Claude Code: version 2.x. Check: `claude --version`.

## 3. Already wired in this repo
- **Claude Code** reads `.mcp.json` at the repo root. It lists Playwright and Context7. The first time you open the project Claude Code asks "approve these project MCP servers?". Only the human can answer: pick yes.
- **OpenCode** reads the `mcp` block in `opencode.json`. Same two servers, nothing to do.
- Both files hold no keys. Context7 works without a key.

Plugins (impeccable, posit-dev) are NOT wired in the repo. They install per user, below.

## 4. Claude Code: commands the agent runs
Run these in the shell, one at a time. Each prints a success line starting with a check mark. VERIFIED (run in a clean scratch home, all succeeded).

```bash
claude plugin marketplace add pbakaus/impeccable
claude plugin install impeccable@impeccable
```

Only if the app uses R or Quarto (VERIFIED, plugin names read from the marketplace file):

```bash
claude plugin marketplace add posit-dev/skills
claude plugin install posit-dev@posit-dev-skills
claude plugin install shiny@posit-dev-skills
claude plugin install quarto@posit-dev-skills
```

The marketplace also lists `github`, `open-source`, `r-lib`, `ggsql`, `connect`. Skip them unless asked.

Check: `claude plugin list` shows each as enabled. Then tell the student: "Close this session and start a new one, so the new skills load."

If `.mcp.json` is missing (VERIFIED, this is how it was written):

```bash
claude mcp add --scope project playwright -- npx -y @playwright/mcp@latest
claude mcp add --scope project --transport http context7 https://mcp.context7.com/mcp
```

Human-only steps: approving the project MCP servers, and restarting Claude Code.

## 5. OpenCode
Nothing to install for Playwright and Context7: `opencode.json` has them. The same file format was checked against `https://opencode.ai/config.json` (zero schema errors, VERIFIED).
To add another server by hand (VERIFIED from `opencode mcp add --help`):

```bash
opencode mcp add <name> -- <command> <args>        # local server
opencode mcp add <name> --url <https-url>          # remote server
```

OpenCode reads skills from `.claude/skills/` itself. impeccable and posit-dev skills: copy the skill folders into `.claude/skills/` (UNVERIFIED; the impeccable README describes its non-Claude install, read it before running anything).

## 6. Cursor, Codex, Copilot, Gemini CLI
All UNVERIFIED today, from vendor docs. The agent should open the vendor page, not trust this table blindly. Shape of each entry: server `playwright` runs `npx -y @playwright/mcp@latest`; server `context7` is the URL `https://mcp.context7.com/mcp`.

| Agent | Where the MCP config goes |
|---|---|
| Cursor | `.cursor/mcp.json` in the project, or Settings, then MCP. Key `mcpServers`. |
| Codex | `~/.codex/config.toml`, table `[mcp_servers.playwright]` with `command` and `args`; for a URL server `url = "..."`. |
| Copilot in VS Code | `.vscode/mcp.json`. Top key is `servers` (not `mcpServers`). |
| Gemini CLI | `~/.gemini/settings.json`, key `mcpServers`. |

For these agents the human must also restart the app after the config changes. Skills: they read `AGENTS.md`, which points at `.claude/skills/superagent/SKILL.md`. For design quality they can read the impeccable skill files directly.

## 7. motion.dev (the one step a human types)
`npx motion-ai` is an interactive menu (VERIFIED: it exits with "motion-ai is interactive" when no terminal is attached, so the agent cannot run it). Ask the student to type this in their own terminal, in the project folder:

```bash
npx motion-ai
```

Choose scope **Project**, pick their agent (Claude Code, OpenCode, Codex, Cursor, Gemini CLI, Copilot), confirm. It copies a `motion` skill into the agent's skills folder and adds two hosted MCP servers, `motion` (docs search, free, no key) and `motion-plus` (needs a paid Motion+ sign-in; ignore it).
MIT licensed. Source: github.com/motiondivision/ai-kit. Afterwards: restart the agent; `/motion` works.

## 8. Smoke test
Ask the agent, in the new session:
1. "Open https://example.com with Playwright and tell me its title." Expected: `Example Domain`.
2. "Use Context7 to look up the FastAPI CORSMiddleware arguments." Expected: a list including `allow_origins`.

If both answer, setup is done. Say so in one line, then go back to `SKILL.md` section 0.

## 9. Troubleshooting
- `npx: command not found`: Node.js is missing or not on PATH. Install Node 18+ from nodejs.org, open a new terminal.
- Playwright server not listed, or the tools are missing: restart the agent. In Claude Code run `/mcp` to see status. On native Windows, if `npx` fails to start, change the Playwright entry in `.mcp.json` to `"command": "cmd"` with `"args": ["/c", "npx", "-y", "@playwright/mcp@latest"]` (UNVERIFIED).
- First Playwright run downloads a browser; it can take a minute. Wait.
- `Filename too long` while adding a marketplace (seen on Windows): run from a shorter folder path or turn on long paths in Git: `git config --global core.longpaths true` (UNVERIFIED fix).
- Plugin "not found in marketplace": run `claude plugin marketplace update <name>`, then install again.
- Plugin installed but skill not visible: start a new session.
- Do not paste any key into a file. Keys go in the agent's own settings, never the repo.
