# Two tools worth ten minutes of setup

> As of 2 October 2026. Prices change; check the linked pages before relying on them.

## Wispr Flow

Voice dictation that types into any text box, including your agent's prompt. Talking is faster than
typing, and a spoken prompt usually carries more context, which is what an agent needs.

- **Free:** 2,000 words a week on desktop (Mac, Windows), 1,000 a week on mobile.
- **Pro:** $15/month, or $12/month billed yearly. **Students and educators** with an institutional email
  get 50% off Pro. See [wisprflow.ai/pricing](https://wisprflow.ai/pricing).
- **Try it on your SPEC:** talk through who the user is and which statistic you'll compute, then tidy the text.
- Name the file, the task and the check out loud: *"Task H-03, in src, add the capability function; done
  means pytest passes."*

## Open Design

A free, open-source (Apache-2.0), local-first design workspace. You sketch a screen, and its MCP server
lets your agent read the design and build from it instead of guessing. Download:
[open-design.ai](https://open-design.ai); source: [github.com/nexu-io/open-design](https://github.com/nexu-io/open-design).

- [`od-setup`](../.claude/skills/od-setup/SKILL.md) installs it and connects it to your agent.
- [`od-pull`](../.claude/skills/od-pull/SKILL.md) pulls a design into your repo and implements it.
- Use it **after** your statistics work and are tested. A polished screen around a wrong chart still scores badly.
