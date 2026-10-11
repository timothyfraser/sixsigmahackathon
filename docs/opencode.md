# Use a free AI agent tonight

**OpenCode + a free Google AI Studio key.** OpenCode is a coding agent: a program in your
terminal that reads this repo, plans with you, writes code, and runs the tests. Google AI Studio
gives you the AI model behind it for free. **Cost: $0. No credit card.**

This is the course's recommended path if you have no paid AI plan. If you already pay for Claude,
ChatGPT or Copilot, use that instead ([`agents.md`](agents.md)).

> Numbers on this page were checked on **10 October 2026** with OpenCode 2.0.26. Free tiers change.
> Your own limits are on your AI Studio rate-limit page: <https://aistudio.google.com/rate-limit>.

---

## 1. The 48-hours-before checklist (do it Wednesday, not Friday)

Setup takes about 15 minutes when the Wi-Fi is quiet. Do it before the event.

- [ ] OpenCode installed: `opencode --version` prints `opencode v2.` something ([section 2](#2-install-opencode)).
- [ ] A free key from **your own** Google account ([section 3](#3-get-your-free-key)). One per person.
- [ ] Key connected with `/connect` ([section 4](#4-connect-the-key)).
- [ ] `/models` shows `gemini-3.5-flash` (Gemini 3.5 Flash) and `gemini-3.1-flash-lite` (Gemini 3.1 Flash Lite).
- [ ] One test question answered on campus Wi-Fi (or the network you will use).
- [ ] Optional backup: GitHub Student Developer Pack verified, for Copilot ([`agents.md`](agents.md)).
- [ ] This repo cloned, `SPEC.md` opened once, `CONTRACT.yaml` skimmed.

---

## 2. Install OpenCode

These are the commands opencode.ai shows today. Pick one line for your computer.

| Your computer | Run this |
|---|---|
| **macOS / Linux** | `curl -fsSL https://opencode.ai/v2/install \| bash` |
| **macOS** (Homebrew) | `brew install anomalyco/tap/opencode-v2` |
| **Any OS with Node.js** (Windows too) | `npm install -g @opencode/cli` |
| **Windows without Node.js** | Download the standalone CLI zip (x64 or ARM64) from <https://opencode.ai/v2/docs>, or run the curl line above inside **Git Bash** |

<!-- UNVERIFIED: the Windows paths (npm on Windows, the CLI zip, curl inside Git Bash) were not re-run on a clean Windows machine; opencode.ai says "Windows package managers are not supported" and shows no PowerShell one-liner (checked 2026-10-10). The demo run must confirm one Windows lane end to end. -->

Then **close the terminal and open a new one**, and check:

```bash
opencode --version
```

You should see `opencode v2.0.26` or newer.

**"opencode: command not found"?** Open a new terminal first. On Windows, the curl/zip install
puts the program in `%USERPROFILE%\.opencode\bin`. Add that folder to your PATH (Start menu →
"Edit environment variables for your account" → Path → New), then open a new terminal.

---

## 3. Get your free key

A **key** (API key) is a long password that lets OpenCode use your free Google quota.

1. Go to <https://aistudio.google.com/apikey> and sign in with a **personal** Google account.
2. Accept the terms if asked. AI Studio makes a default project for you.
3. Click **Create API key**. Copy it.

No card is asked for. If the button is greyed out, your account may already have Google Cloud
projects: follow the "Import projects" prompt on that page, then try again.

**Key rules.** Paste the key in exactly one place: OpenCode's `/connect` (next step).

- Never put it in a file in this repo, a `.env`, a chat message, a prompt, a screenshot or a commit.
- Do not share it by default. Each person uses their own key. (Sharing is possible as a last resort: read [Option: cycling or sharing keys](#option-cycling-or-sharing-keys) first.)
- If it leaks: create a new key on the same page and delete the old one.

---

## 4. Connect the key

Open a terminal **in this repo's folder** and start OpenCode:

```bash
cd sixsigmahackathon
opencode
```

1. Type `/connect` and press Enter.
2. Choose **Google**, then the **API key** method.
3. Paste your key and press Enter.
4. Type `/models`. Check that `gemini-3.5-flash` (shown as Gemini 3.5 Flash) and `gemini-3.1-flash-lite` (shown as Gemini 3.1 Flash Lite) are listed.

> **Careful with names.** "Gemini 3.5 Flash **Lite**" (`gemini-3.5-flash-lite`) is a *different* model from `gemini-3.1-flash-lite`. It cannot finish a build on the free tier. Do not pick it for `/build`.

<!-- UNVERIFIED: the menu labels written as "shown as Gemini ..." throughout this page follow Google's model names but were not read from the OpenCode /models picker on 2026-10-10; the demo run must confirm them. -->
<!-- UNVERIFIED: the interactive /connect -> Google -> paste flow and the /models picker were documented by OpenCode but not run end to end in the TUI on 2026-10-10 (an agent cannot paste a key interactively). The demo run must confirm the exact menu labels. -->

Check from a normal terminal, any time:

```bash
opencode auth list
```

It should list **Google**. Your key is now stored by OpenCode itself, outside this repo, and survives restarts.

Always start OpenCode **inside this repo folder**. The repo's [`opencode.json`](../opencode.json) picks
the free Gemini model and points OpenCode at [`CLAUDE.md`](../CLAUDE.md), [`SPEC.md`](../SPEC.md) and the
skills in [`.claude/skills/`](../.claude/skills/). OpenCode reads those skills as they are: expect the 8
repo skills plus 2 built-in ones. More than 10 means skills from a folder above the repo; that is harmless.

Use Claude Code too? Your own personal skills from it will also show up in OpenCode's list; that's normal and doesn't affect the repo.

> **Advanced: the environment-variable route.** You can set `GEMINI_API_KEY` instead of `/connect`.
> OpenCode runs a background service that keeps the environment it started with, so stop it after
> setting the variable. In PowerShell:
>
> ```powershell
> $env:GEMINI_API_KEY = "<your key>"
> opencode service stop
> opencode
> ```
>
> On macOS/Linux use `export GEMINI_API_KEY="<your key>"`. This leaves the key in your shell history;
> `/connect` does not. OpenCode does **not** read a `.env` file in the repo, so do not make one for it.

---

## 5. The model ladder: which model for which job

Google's free tier gives **each model its own daily allowance**. Think of it as a ladder: when one
rung is used up, step down to the next. (RPM = requests per minute; a "request" is one step of the agent.)

| Job | Model | Per key, per day | Per minute | What it costs |
|---|---|---|---|---|
| **Think**: plan, design decisions | `gemini-3.5-flash` (Gemini 3.5 Flash) | 20 requests | 5 | a good plan took 4 requests (about 1 minute) |
| Think, next rungs | `gemini-3.8-flash`, `3.7-flash`, `3.6-flash`, `3-flash`, `2.5-flash` | 20 each | 5 each | step down when one is spent |
| **Loop**: build, test, fix, check in | `gemini-3.1-flash-lite` (Gemini 3.1 Flash Lite) | 500 requests | 15 | one tested task took 29 requests (about 5 minutes) |
| Loop fallback | `gemini-3.5-flash-lite` (Gemini 3.5 Flash Lite) | 500 | 15 | fine for a quick plan (re-run if a formula is missing); **could not finish a build** in our tests |
| Not for agents | Gemma models | | | won't work in an agent: OpenCode's first message is bigger than Gemma's per-minute limit |

The repo's commands pick the right rung for you: `/plan` and `/decide` use `gemini-3.5-flash` (Gemini 3.5 Flash);
`/build`, `/checkin` and `/stuck` use `gemini-3.1-flash-lite` (Gemini 3.1 Flash Lite).
Remember: Gemini 3.5 Flash **Lite** is not the same model as Gemini 3.1 Flash Lite.

<!-- UNVERIFIED: per-command model pins are documented by OpenCode but were not exercised in the TUI on 2026-10-10. -->

**One agent per key.** The real ceiling is not requests per day. It is about **250,000 input tokens
per minute** per model, and OpenCode sends 20,000-30,000 tokens on every step. Two agents on one key
hit that wall in under a minute. So a team works in parallel **across people**: each person runs one
agent on their own key, from their own Google account.

**Per-team arithmetic.** One key ≈ 5 plans and ≈ 15 built tasks a day. A team of three, each with
their own key, has three times that. Two keys from the same Google account share one allowance, so only keys from different people's accounts add capacity. Daily quotas reset at **midnight Pacific** (3 AM Eastern).

**Step-down rule.** Per-minute limit hit (a `429` error)? Wait one minute, `/new`, run the command again.
Daily limit hit? `/models` → the next rung down the same row of the table.

### Option: cycling or sharing keys

**The default stays the same: your own key, from your own Google account.** If you want more
capacity, there is an option. Treat it as a last resort, and read the security note first.

**How it works.** When your key's daily quota runs out, a teammate can hand you their key. You run
`/connect` again and paste it. Later, switch back by running `/connect` with your own key. The
teammate's key still counts against *their* allowance, so only borrow it while theirs has room.

**Security: an API key is a password.**

- Share it only **in person**, or in a **direct message that you then delete**.
- Never put it in a group chat, a file, a commit or a screenshot.
- Anyone holding the key can use up the owner's quota. On a **paid** account, they can spend the owner's money.
- After the hackathon, the owner should **delete the key and make a new one** at <https://aistudio.google.com/apikey>.
- Two keys from the **same** Google account share one quota. Only keys from **different people's** accounts add capacity.

---

## 6. Your first hour

Everything below happens inside OpenCode, in this repo. The example is generic (a bolt-torque line);
your event prompt will differ. The same prompts, as plain text for any other agent (Claude Code,
Codex, Copilot, Gemini/Antigravity), are in [`prompts-starter.md`](prompts-starter.md). The commands
themselves live in [`.opencode/commands/`](../.opencode/commands/).

**Minute 0-10: say hello.** Start `opencode` in the repo and type:

> What is this repo for, and which files should we fill in first? Two sentences.

It should name `SPEC.md` and `CONTRACT.yaml`. That proves the key, the model and the repo are all connected.

**Minute 10-20: fill in the SPEC with your team, not the agent.** Open [`SPEC.md`](../SPEC.md) and
replace every `FILL IN` line. Four sentences are enough: **who** uses the tool (a quality engineer on a
bolt-tightening line), **what** question it answers (is torque in control, and is the process capable?),
**which statistic** (X-bar and R charts with subgroups of 5; Cp and Cpk), and **which stack** (FastAPI + one
React page). Put a hand-calculated known answer in section 4. The agent guesses whatever you leave blank.

**Minute 20-30: `/plan`, then `/decide`.** Type `/new`, then `/plan`. The planner reads `SPEC.md` and
`CONTRACT.yaml`, states the statistic and its formula, and writes `docs/plan.md`. It does not touch code.
A good plan for the bolt example states the formulas before any task:

```text
X-bar chart: centre = X-double-bar; limits = X-double-bar ± A2·R-bar   (n = 5: A2 = 0.577)
R chart:     centre = R-bar; LCL = D3·R-bar, UCL = D4·R-bar             (D3 = 0, D4 = 2.114)
sigma-hat = R-bar / d2 (d2 = 2.326);  Cp = (USL − LSL) / 6·sigma-hat
Cpk = min(USL − X-double-bar, X-double-bar − LSL) / 3·sigma-hat
H-03  app/qc.py + tests/: known answer from SPEC section 4, plus constant data (must not divide by zero)
```

Then type `/decide`. It asks the open design questions one at a time, as multiple choice, with a
recommendation. You answer with a number:

```text
How should the tool receive the torque measurements?
  1. CSV upload (columns: subgroup, value)   <- recommended: matches SPEC
  2. Paste a table into a text box
  3. A form, one subgroup at a time
```

<!-- VERIFIED 2026-10-10 (instructor test, OpenCode 2.0.26 + free Gemini): the questions arrive as numbered text in the chat, not clickable boxes; answer by typing the number. -->

Read `docs/plan.md` as a team. If a formula looks wrong, say so now. Fixing a sentence is free; fixing code is not.

**Minute 30-45: `/build H-03`.** Type `/new`, then `/build H-03`. H-03 is the first statistics task in
[`CONTRACT.yaml`](../CONTRACT.yaml): one plain, tested function. The agent checks the task out, writes
`app/qc.py` and `tests/test_qc.py`, and runs the tests. Good output shows the **real** test result:

```text
tests/test_qc.py::test_qc_known_answer PASSED
tests/test_qc.py::test_qc_degenerate_constant PASSED
2 passed
```

and numbers you can check against your hand calculation, for example X-bar centre 25.00, UCL 25.23,
LCL 24.77; R centre 0.40, UCL 0.85; Cp = Cpk = 1.94.

**Minute 45-55: `/review`.** Type `/new`, then `/review`. A reviewer checks the statistic against the
known answer and the constant-data case and reports PASS or FAIL with the numbers. Then read the change
yourselves:

```bash
git status
git diff
```

Can each of you explain every number the test printed? If not, ask the agent to explain one function in
plain English.

**Minute 55-60: `/checkin H-03`.** It marks the task `done` in `CONTRACT.yaml` with a one-line result,
in the same commit as the code. Check that `owner` and `started_at` are filled in, not deleted.

<!-- UNVERIFIED: the argument form of /checkin (with or without a task id) depends on the command file being written in parallel; confirm against .opencode/commands/checkin.md. -->

Next task: `/new`, then `/build H-04`. One task per session, every time.

---

## 7. Session hygiene

- **`/new` for every task.** A fresh session sends fewer tokens per step, so you stay under the per-minute limit.
- **`/compact` when a session gets long** and answers get slow or vague. It summarises the conversation.
- **Read the diff after every task** (`git diff`). The agent's summary is not proof; the test output is.
- **Stage files by name** (`git add app/qc.py tests/test_qc.py`), never `git add .`.

<!-- UNVERIFIED: /new and /compact are documented TUI commands but were not exercised on 2026-10-10. -->

---

## 8. When it stalls

| You see | What it means | Do this |
|---|---|---|
| `429`, `RESOURCE_EXHAUSTED` or `quota`, and the agent stops | a per-minute or daily limit | wait one minute, `/new`, run the command again; still failing → `/models`, next rung down ([section 5](#5-the-model-ladder-which-model-for-which-job)) |
| Nothing happens for over a minute, no error | no key connected | `opencode auth list`; if Google is missing, `/connect` again |
| `API key not valid` | key copied wrong, or deleted | copy it again, or make a new one |
| `Model exo-free has been deprecated` | you started OpenCode outside the repo folder | `cd` into the repo and run `opencode` again |
| The same error three times | the task is too big | stop; `/stuck`, or `/new` with a smaller task and the error message pasted in |
| It edits a file outside the task | ignoring the task's `owns` list | say "undo that; only touch the files in the task's owns list", then check `git diff` |
| It says a helper agent failed and it "did it another way" | it swapped in a different agent | stop it; ask it to report the error instead. Never accept a substitute |
| It asks you to put the key in a file or `.env` | wrong advice | refuse. Keys go in `/connect` only |
| Your model is gone from `/models` | Google renamed or retired it | pick the next rung of the same row |
| `opencode: command not found` | PATH not updated | open a new terminal; see [section 2](#2-install-opencode) |

<!-- UNVERIFIED: OpenCode's exact on-screen wording for a Gemini 429 was not captured on 2026-10-10 (the run exits with a provider.quota error). -->

Windows note: Windows PowerShell 5.1 saves text files with a hidden byte-order mark that breaks some
tools. If you must create a config file, use VS Code or RStudio. OpenCode itself needs no `.env`.

---

## 9. Other free options, and their data terms

**Data terms** say what the vendor may do with what you send.

| Option | Cost | What happens to your prompts | Use it when |
|---|---|---|---|
| **Google AI Studio free tier** (this page) | $0 | Google may use free-tier prompts and responses to improve its products, and human reviewers may read them (paid tiers: no). Google says not to send sensitive, confidential or personal information. You must be 18+. | the default |
| **OpenCode Zen free models** (any model ending in `-free` in `/models`) | $0, "for a limited time" | **Varies by model.** Some: collected data may be used to improve the model. Some: zero retention, no training. Some: trial use only, do not send personal or confidential data. Some: prompts used to train the vendor's future models. Check the model's row at <https://opencode.ai/docs/zen/> before you use it. | **only if your employer allows third-party AI vendors** |
| **GitHub Copilot**, Student plan | $0 for verified students | see GitHub's terms | you verified the Student Developer Pack ([`agents.md`](agents.md)) |

Zen free models answered with no sign-in when we tested; the list rotates, so pick any `-free` model
`/models` shows today rather than a name from this page.

**Ollama (running a model on your own laptop) is a warning, not a path.** It needs roughly 16 GB of
memory or more, it is slow, and small local models are poor at agent work. For most laptops it is a
trap during a 24-hour event.

---

## 10. If you work for a defense contractor (or any employer with an AI policy)

Many of you work for employers that restrict which AI vendors you may use. Google AI Studio is the
course's recommended free vendor for that reason, and Copilot is the second. Do **not** use Zen free
models unless your employer allows third-party AI vendors. Even for Google, check your employer's
policy on the **free** tier: Google may use free-tier prompts to improve its products; paid tiers do
not. Hackathon code and data are public anyway, and your invented dataset is not confidential. Never
paste anything from work into any agent.
