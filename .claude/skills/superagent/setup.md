# Superagent setup: install the helper tools

For the AGENT to run, and for the student to read along. Do this once per computer or project, not every session.
Tags: VERIFIED = the command was run, or its `--help` / the vendor's own docs were read, on 2026-10-16. UNVERIFIED = from memory; if it fails, tell the student and stop guessing.

## Contents
1. What gets installed and why
2. Requirements
3. Already wired in this repo
4. Claude Code: plugins and the fallback commands
5. OpenCode
6. Cursor, Codex, Copilot, Gemini CLI
7. impeccable on the non-Claude agents
8. motion.dev (the one step a human types)
9. Smoke test
10. Troubleshooting

## 1. What gets installed and why
- **Playwright** (MCP server): the agent's own browser. It opens the page it just built and looks at it, instead of guessing.
- **Context7** (MCP server): current library docs on demand, so the agent does not code from stale memory.
- **impeccable** (plugin): UI design quality. It stops the "generic AI look".
- **motion.dev AI Kit** (skill plus MCP): animation done well. Optional; skip it if the app has no motion.
- **posit-dev skills** (plugins `r-lib`, `shiny`, `quarto`, `connect`): R packages, Shiny, Quarto, Posit Connect.

An MCP server is a small helper program the agent can call. A plugin is a bundle of skills and agents.

## 2. Requirements
- Node.js 18 or newer. Check: `node -v`. The commands use `npx`, which ships with Node.
- Internet access, and `git` (plugin marketplaces are cloned from GitHub).
- Claude Code: version 2.x. Check: `claude --version`.

## 3. Already wired in this repo
- **Claude Code trust dialog (human-only, do this first):** the first time you open the repo, Claude Code asks "do you trust this folder?". The human must accept. Until they do, Claude Code ignores the repo's `.claude/settings.json` (VERIFIED today: "Ignoring 24 permissions.allow entries ... this workspace has not been trusted"), so every python or bash command asks for approval, and the plugin marketplaces are not offered.
- **Claude Code MCP:** `.mcp.json` at the repo root lists Playwright and Context7. The first time you open the project Claude Code asks "approve these project MCP servers?". Only the human can answer: pick yes.
- **Claude Code plugins:** `.claude/settings.json` already declares the `impeccable` and `posit-dev-skills` marketplaces and turns on `impeccable@impeccable`, `r-lib@posit-dev-skills`, `shiny@posit-dev-skills`, `quarto@posit-dev-skills` and `connect@posit-dev-skills`. When a teammate trusts the project folder, Claude Code offers to install them. The human picks yes, then restarts Claude Code. VERIFIED in the Claude Code docs (settings and plugin-marketplaces pages): "When the repository folder is trusted, Claude Code prompts users to install the configured marketplaces and plugins." Section 4 is only the fallback, if the prompt was skipped.
- **OpenCode** reads the `mcp` block in `opencode.json`. Same two servers, nothing to do.
- No file holds a key. Context7 works without a key.

## 4. Claude Code: fallback commands the agent runs
Use these only if `claude plugin list` does not show the five plugins above. Run them one at a time. Each prints a success line starting with a check mark. VERIFIED (run in a clean scratch home, all succeeded).

```bash
claude plugin marketplace add pbakaus/impeccable
claude plugin install impeccable@impeccable
claude plugin marketplace add posit-dev/skills
claude plugin install r-lib@posit-dev-skills
claude plugin install shiny@posit-dev-skills
claude plugin install quarto@posit-dev-skills
claude plugin install connect@posit-dev-skills
```

Skip any posit-dev line the app does not need (no R, no Shiny, no Quarto, no Connect). The marketplace also lists `posit-dev`, `github`, `open-source`, `ggsql`. Skip them unless asked.

Check: `claude plugin list` shows each as enabled. Then tell the student: "Close this session and start a new one, so the new skills load."

If `.mcp.json` is missing (VERIFIED, this is how it was written):

```bash
claude mcp add --scope project playwright -- npx -y @playwright/mcp@latest
claude mcp add --scope project --transport http context7 https://mcp.context7.com/mcp
```

Human-only steps: trusting the folder, approving the project MCP servers, and restarting Claude Code.

## 5. OpenCode
Nothing to install for Playwright and Context7: `opencode.json` has them. The file format was checked against `https://opencode.ai/config.json` (zero schema errors, VERIFIED).
To add another server by hand (VERIFIED from `opencode mcp add --help`):

```bash
opencode mcp add <name> -- <command> <args>        # local server
opencode mcp add <name> --url <https-url>          # remote server
```

OpenCode reads skills from `.claude/skills/` itself. For impeccable, see section 7.

## 6. Cursor, Codex, Copilot, Gemini CLI
All four VERIFIED on 2026-10-16 from the vendors' own docs (Cursor's MCP page, OpenAI Codex source, the VS Code MCP servers page, the Gemini CLI configuration reference). Server `playwright` runs `npx -y @playwright/mcp@latest`. Server `context7` is the URL `https://mcp.context7.com/mcp`.
Use the **user-level** file or the Settings screen, so nothing new lands in the project folder. Restart the app after editing.

| Agent | User-level config | Shape |
|---|---|---|
| Cursor | `~/.cursor/mcp.json`, or Settings, then MCP | top key `mcpServers`; local: `"command": "npx"`, `"args": [...]`; remote: `"url": "https://mcp.context7.com/mcp"` |
| Codex | `~/.codex/config.toml` | table `[mcp_servers.playwright]` with `command = "npx"` and `args = ["-y", "@playwright/mcp@latest"]`; table `[mcp_servers.context7]` with `url = "https://mcp.context7.com/mcp"` |
| Copilot in VS Code | the user `mcp.json`: run the command **MCP: Open User Configuration** | top key `servers` (not `mcpServers`); remote needs `"type": "http"` plus `"url"`; local uses `"command"` and `"args"` |
| Gemini CLI | `~/.gemini/settings.json` | top key `mcpServers`; local: `command` and `args`; remote streamable HTTP: `"httpUrl"` (the key `url` means the older SSE kind) |

Codex can also add them for you, no editing (VERIFIED from its CLI source; this only writes `~/.codex/config.toml`):

```bash
codex mcp add playwright -- npx -y @playwright/mcp@latest
codex mcp add context7 --url https://mcp.context7.com/mcp
```

Skills: these agents read `AGENTS.md`, which points at `.claude/skills/superagent/SKILL.md`.

## 7. impeccable on the non-Claude agents
VERIFIED from the impeccable README on GitHub, and the install was run into a scratch home folder on 2026-10-16. One command covers OpenCode, Cursor, Codex, Copilot and Gemini CLI. It puts the skill in the user's home folder, so the project stays clean:

```bash
npx impeccable install --providers=opencode,cursor,codex,github,gemini --scope=global --no-hooks -y
```

Drop any provider the student does not use. Where it lands: OpenCode `~/.config/opencode/skills/`, Cursor `~/.cursor/skills/`, Codex `~/.agents/skills/`, Copilot `~/.github/skills/` (plus `~/.copilot/agents/`), Gemini `~/.gemini/skills/`. Restart the agent, then type `/impeccable init` in its chat (not in the terminal).
Update later: `npx impeccable update`.
Extras from the README: Copilot in VS Code can also use the marketplace extension `renaissance-geek.impeccable`. Cursor skills need Agent Skills enabled in Cursor Settings, then Rules. Gemini CLI skills need Skills turned on under `/settings`.

## 8. motion.dev (the one step a human types)
`npx motion-ai` is an interactive menu (VERIFIED: it exits with "motion-ai is interactive" when no terminal is attached, so the agent cannot run it). Ask the student to type this in their own terminal, in the project folder:

```bash
npx motion-ai
```

Choose scope **Project**, pick their agent (Claude Code, OpenCode, Codex, Cursor, Gemini CLI, Copilot), confirm. It copies a `motion` skill into the agent's skills folder and adds two hosted MCP servers, `motion` (docs search, free, no key) and `motion-plus` (needs a paid Motion+ sign-in; ignore it).
MIT licensed. Source: github.com/motiondivision/ai-kit. Afterwards: restart the agent; `/motion` works.

## 9. Smoke test
Ask the agent, in the new session:
1. "Open https://example.com with Playwright and tell me its title." Expected: `Example Domain`.
2. "Use Context7 to look up the FastAPI CORSMiddleware arguments." Expected: a list including `allow_origins`.

If both answer, setup is done. Say so in one line, then go back to `SKILL.md` section 0.

## 10. Troubleshooting
- `npx: command not found`: Node.js is missing or not on PATH. Install Node 18+ from nodejs.org, open a new terminal.
- Playwright server not listed, or the tools are missing: restart the agent. In Claude Code run `/mcp` to see status.
- Only on an older Claude Code on Windows, if `npx` fails to start: in `.mcp.json` change the Playwright entry to `"command": "cmd"` with `"args": ["/c", "npx", "-y", "@playwright/mcp@latest"]`. Current versions run it as written (VERIFIED on Windows).
- First Playwright run downloads a browser; it can take a minute. Wait.
- `Filename too long` while adding a marketplace (seen on Windows when the folder path is very long): use a shorter folder path, or run `git config --global core.longpaths true`.
- Plugin "not found in marketplace": run `claude plugin marketplace update <name>`, then install again.
- Plugin installed but skill not visible: start a new session.
- Do not paste any key into a file. Keys go in the agent's own settings, never the repo.
