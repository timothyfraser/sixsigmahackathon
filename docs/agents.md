# Popular AI coding agents

Bring whichever one you already have. They all work with the [starter kit](../kit/README.md): Claude Code
reads `CLAUDE.md`, most others read `AGENTS.md`.

> **Prices and student offers as of 2 October 2026. They change often; check the linked page before you rely on one.**

| Agent | What it is | Cost and free / student access | Start in two lines |
|---|---|---|---|
| **Claude Code** (Anthropic) | Terminal agent; also VS Code, JetBrains, desktop and web | Needs a paid Claude plan (Pro $20/mo, or $17/mo billed yearly; Max from $100/mo) or pay-as-you-go API credits. The free Claude plan does not include it. Some universities buy a Claude education plan; ask yours. [pricing](https://claude.com/pricing) | Install: `curl -fsSL https://claude.ai/install.sh \| bash` (Windows PowerShell: `irm https://claude.ai/install.ps1 \| iex`). Then `cd` into your repo and run `claude`. |
| **Cursor** | A full code editor (VS Code-based) with a built-in agent | Hobby tier is free; Pro is $20/mo. Its student page says only to watch for campus promotions. We could not confirm a current free-Pro student offer. [pricing](https://cursor.com/pricing), [students](https://cursor.com/students) | Download from cursor.com and open your repo folder. Open the agent panel and point it at `SPEC.md`. |
| **GitHub Copilot** | Extension for VS Code and other editors, plus an agent mode | Free tier $0; Pro $10/mo; Pro+ $39/mo. **Verified students get it free** through the Copilot Student plan (since March 2026), after verifying at [GitHub Education](https://education.github.com/pack), the same verification as the Student Developer Pack. Some premium models are only offered in Auto mode on that plan. [plans](https://github.com/features/copilot/plans), [students](https://docs.github.com/en/copilot/how-tos/copilot-on-github/set-up-copilot/enable-copilot/set-up-for-students) | Verify at GitHub Education, then install the GitHub Copilot extension in VS Code. Sign in with GitHub and switch chat to Agent mode. |
| **OpenAI Codex** | Terminal agent (Codex CLI), plus IDE extension and cloud | Comes with ChatGPT plans. OpenAI's pricing page lists Free, Go ($8/mo), Plus ($20/mo) and Pro (from $100/mo), with usage limits that grow with the plan. A "Codex for Students" program is mentioned, but we could not confirm what it offers. [pricing](https://learn.chatgpt.com/docs/pricing) | `npm install -g @openai/codex` (or `brew install --cask codex`). Run `codex` and choose "Sign in with ChatGPT". |
| **Gemini CLI / Antigravity CLI** (Google) | Terminal agent | **Changed this summer:** for free and Google One users, Gemini CLI was replaced by the Antigravity CLI (`agy`) on 18 June 2026. Gemini CLI still runs with a Gemini API key; Google's docs list 250 requests/day on the free API tier (Flash model only). Third-party reports put Antigravity's free tier at about 20 agent requests a day; we could not confirm that with Google. [Gemini CLI quotas](https://geminicli.com/docs/resources/quota-and-pricing/) | Follow the install steps at [antigravity.google](https://antigravity.google). Run `agy` in your repo and sign in with Google. |

**On a budget?** Copilot (free for verified students) or Codex on the ChatGPT plan you already have
costs nothing extra. The tips below matter more than which agent you pick.

## Steering an agent toward correct statistics on a budget

1. **Spec first.** Fill in [`kit/SPEC.md`](../kit/SPEC.md) before the agent writes code. Most wasted
   tokens come from the agent guessing what you meant.
2. **One small task per prompt.** "Do H-03 only" beats "build the app". Small tasks are cheap to throw away.
3. **Make it state the method before it codes.** Ask: "In one sentence, which statistic and which formula
   will you use, and why?" Fix the sentence, not the code.
4. **Ask for a test against a known answer.** A textbook example or a hand calculation, plus a degenerate case
   (constant data). See [`stats-first-steering`](../.claude/skills/stats-first-steering/SKILL.md).
5. **Read the diff.** If nobody on the team can explain a number the tool prints, it isn't done.
6. **Keep a data dictionary.** A codebook in `data/README.md` stops the agent inventing column meanings,
   and it earns rubric points.
7. **Start fresh when it loops.** If the agent has failed twice at the same thing, clear the chat, shrink
   the task, and give it the error message plus the SPEC.
8. **Never paste secrets.** No API keys, passwords or deploy credentials in a prompt, file or commit.
