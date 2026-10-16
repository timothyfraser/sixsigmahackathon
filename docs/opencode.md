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
- [ ] This repo cloned, and `SPEC.md` and `CONTRACT.yaml` seen once (you will ask the agent to update `SPEC.md`, not edit it by hand).

---

## 2. Install OpenCode

These are the commands opencode.ai shows today. Pick one line for your computer.

| Your computer | Run this |
|---|---|
| **macOS / Linux** | `curl -fsSL https://opencode.ai/v2/install \| bash` |
| **macOS** (Homebrew) | `brew install anomalyco/tap/opencode-v2` |
| **Any OS with Node.js** (Windows too) | `npm install -g @opencode/cli` |
| **Windows without Node.js** | Run the curl line above inside **Git Bash** (recommended), or download <https://opencode.ai/files/bin/2.0.26/opencode-windows-x64.zip> (ARM laptops: `opencode-windows-arm64.zip` in the same folder) and unzip `opencode.exe` into `%USERPROFILE%\.opencode\bin`. The zip linked from opencode.ai/v2/docs is an older 2.0.6 build, so use the link in this row. |

npm 11 may print a warning such as `install-scripts ... postinstall`. It is harmless; `opencode --version` below is the real check.

<!-- VERIFIED 2026-10-11: npm and the Git Bash curl line were run on Windows 11 and both installed v2.0.26; the 2.0.26 zip URL returns HTTP 200. -->

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

1. Type `/connect` and press Enter. A list titled **Connect an integration** opens.
2. Choose **Google** (near the top, under **Popular**; type `goo` to filter). OpenCode goes straight to a box titled **Connect Google**.
3. Paste your key where it says `API key` and press Enter.

Already connected once? Choosing Google shows your saved account instead of the key box. That is fine: skip to `/models`. From a normal terminal, `opencode auth login google` does the same job and asks `Enter your Google API key`.

4. Type `/models`. Check that `gemini-3.5-flash` (shown as Gemini 3.5 Flash) and `gemini-3.1-flash-lite` (shown as Gemini 3.1 Flash Lite) are listed.

> **Careful with names.** "Gemini 3.5 Flash **Lite**" (`gemini-3.5-flash-lite`) is a *different* model from `gemini-3.1-flash-lite`. It cannot finish a build on the free tier. Do not pick it for `/build`.

<!-- UNVERIFIED: the "shown as Gemini ..." labels were not read from the /models picker. -->
<!-- VERIFIED 2026-10-11: the /connect flow above is what the v2.0.26 TUI shows (Google has one auth method, so there is no method step). Still UNVERIFIED: the /models display labels. -->

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
| **Think**: plan, design decisions | `gemini-3.5-flash` (Gemini 3.5 Flash) | 20 requests | 5 | a plan takes 4-8 requests (2-3 minutes, because only 5 fit in a minute) |
| Think, next rungs | `gemini-3.8-flash`, `3.7-flash`, `3.6-flash`, `3-flash`, `2.5-flash` | 20 each | 5 each | step down when one is spent |
| **Loop**: build, test, fix, check in | `gemini-3.1-flash-lite` (Gemini 3.1 Flash Lite) | 500 requests | 15 | one tested task took 29 requests (about 5 minutes) |
| Loop fallback | `gemini-3.5-flash-lite` (Gemini 3.5 Flash Lite) | 500 | 15 | fine for a quick plan (re-run if a formula is missing); **could not finish a build** in our tests |
| Not for agents | Gemma models | | | won't work in an agent: OpenCode's first message is bigger than Gemma's per-minute limit |

The repo's commands pick the right rung for you: `/plan` and `/decide` use `gemini-3.5-flash` (Gemini 3.5 Flash);
`/build`, `/checkin` and `/stuck` use `gemini-3.1-flash-lite` (Gemini 3.1 Flash Lite).
Remember: Gemini 3.5 Flash **Lite** is not the same model as Gemini 3.1 Flash Lite.

<!-- VERIFIED 2026-10-11: /plan ran on gemini-3.5-flash and /build on gemini-3.1-flash-lite, as pinned. -->

**One agent per key.** The real ceiling is not requests per day. It is about **250,000 input tokens
per minute** per model, and OpenCode sends 20,000-30,000 tokens on every step. Two agents on one key
hit that wall in under a minute. So a team works in parallel **across people**: each person runs one
agent on their own key, from their own Google account.

**Per-team arithmetic.** One key ≈ 5 plans and ≈ 15 built tasks a day. A team of three, each with
their own key, has three times that. Two keys from the same Google account share one allowance, so only keys from different people's accounts add capacity. Daily quotas reset at **midnight Pacific** (3 AM Eastern).

**Step-down rule.** Per-minute limit hit (a `429` error that says "Please retry in" some seconds)? Wait one
minute, then type `continue` in the **same** session. Do **not** start a new session for this: `/new`
repeats every step the agent already did and hits the same limit again.
Daily limit hit? `/models` → the next rung down the same row of the table.

One oddity: Google may count `gemini-3.5-flash` requests against the `gemini-3.6-flash` row of your
rate-limit page (the 429 names the model it billed). Use the error text, not the model you picked, to
see which allowance ran out.

### Quota in plain words

- A **quota** is how many requests Google lets one key make in a day. It resets at midnight Pacific.
- **Each model has its own daily quota.** Using up one model does not touch another.
- **One full build can use a key's whole daily `gemini-3.1-flash-lite` quota (500 requests).** A SPEC,
  a plan, test data, one statistic and part of an API was enough to run one key dry.
- So **plan with one model and build with another**: `/plan` uses `gemini-3.5-flash`, `/build` uses
  `gemini-3.1-flash-lite`. Do not spend your build model on chatting or planning.
- Rehearsals count. A practice run the day before uses the same quota you need on the day.
- If a model runs out for the day, see docs/model-ladder.md.

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

The quickest start is one command: `/superagent <your app>`. The step commands below are the same steps done by hand.

**Minute 0-10: say hello.** Start `opencode` in the repo and type:

> What is this repo for, and which files describe our project? Two sentences.

It should name `SPEC.md` and `CONTRACT.yaml`. That proves the key, the model and the repo are all connected.

**Minute 10-20: describe your app, and ask the agent to write the SPEC.** You do not fill in
[`SPEC.md`](../SPEC.md) by hand, and you do not need to read all of it. As a team, agree on a few
sentences: **who** uses the tool, **what data** they have, **which statistic** answers their question, and
**what they should see**. Then ask your agent (this is the `/spec` command; the plain-text prompt for other agents is in
[`prompts-starter.md`](prompts-starter.md)):

> Describe your app in a few sentences (who uses it, what data they have, what statistic answers their question, what they should see), and ask your agent: "Update SPEC.md's FILL IN lines from this description and show me the diff."

`/spec` does exactly that. For the bolt example, type:

```text
/spec A quality engineer on a bolt-tightening line uploads torque readings (CSV). We use X-bar and R charts with subgroups of 5, plus Cp and Cpk. Known answer: 4 subgroups of 5, grand mean 25.0 N-m, R-bar 0.4 N-m, spec 25 +/- 1.5 N-m. They see "in control: yes/no" and a chart. FastAPI plus one React page.
```

Now **read the diff together**. Check that the user, the statistic and the known answer are what you meant;
if something is wrong or vague, say what to change and ask again. Do not move on until it says what
you mean: the agent guesses whatever the SPEC leaves blank, and `/build` takes its known-answer test from
section 4. (`grep -c "FILL IN[.,]" SPEC.md` prints 0 when every blank is filled.)

**Minute 20-30: `/plan`, then `/decide`.** Type `/new`, then `/plan`. The planner reads `SPEC.md` and
`CONTRACT.yaml`, states the statistic and its formula, asks all its open questions in one numbered list,
and after your one reply writes `docs/plan.md`. It does not touch code.
A good plan for the bolt example states the formulas before any task:

```text
X-bar chart: centre = X-double-bar; limits = X-double-bar ± A2·R-bar   (n = 5: A2 = 0.577)
R chart:     centre = R-bar; LCL = D3·R-bar, UCL = D4·R-bar             (D3 = 0, D4 = 2.114)
sigma-hat = R-bar / d2 (d2 = 2.326);  Cp = (USL − LSL) / 6·sigma-hat
Cpk = min(USL − X-double-bar, X-double-bar − LSL) / 3·sigma-hat
H-03  app/qc.py + tests/: known answer from SPEC section 4, plus constant data (Cp, Cpk undefined: error or NaN, never inf)
```

`/plan` and `/decide` ask every open design question in **one** message, as a numbered multiple-choice
list with a recommendation. You answer all of them in one reply, question number then option number
(`1-1, 2-2`). One message instead of five matters: the planning model allows only 5 requests a minute.
Run `/decide` later for anything still open.

```text
1. How should the tool receive the torque measurements?
   1. CSV upload (columns: subgroup, value)   <- recommended: matches SPEC
   2. Paste a table into a text box
   3. A form, one subgroup at a time
2. What does the user see first?
   1. "Stop the line: yes/no"                 <- recommended: the decision in SPEC
   2. The chart only
```


Read `docs/plan.md` as a team. If a formula looks wrong, say so now. Fixing a sentence is free; fixing code is not.

**Minute 30-45: `/build H-03`.** Type `/new`, then `/build H-03`. H-03 is the first statistics task in
[`CONTRACT.yaml`](../CONTRACT.yaml): one plain, tested function. The agent reads `SPEC.md` and
`docs/plan.md`, restates the statistic and its formula in one sentence (check it: if it is not your
method, stop it there), checks the task out with the real time, writes `tests/test_qc.py` and
`app/qc.py`, and runs the tests. It builds only; it does not review itself and never commits.
Good output shows the **real** test result:

```text
tests/test_qc.py::test_qc_known_answer PASSED
tests/test_qc.py::test_qc_degenerate_constant PASSED
2 passed
```

and numbers you can check against your hand calculation. For the bolt example (grand mean 25.0 N-m,
R-bar 0.4 N-m, spec 25 ± 1.5 N-m):

```text
X-bar chart: 25.0 ± 0.577 × 0.4 = 25.0 ± 0.231   -> LCL 24.77, UCL 25.23
R chart:     centre 0.40; LCL 0 × 0.4 = 0; UCL 2.114 × 0.4 = 0.85
sigma-hat = 0.4 / 2.326 = 0.172
Cp  = (26.5 − 23.5) / (6 × 0.172) = 3.0 / 1.032 = 2.91
Cpk = min(26.5 − 25.0, 25.0 − 23.5) / (3 × 0.172) = 1.5 / 0.516 = 2.91
```

Constant data (every reading the same) has zero spread, so Cp and Cpk are undefined: the function must
raise an error or return NaN with a message. `inf` is a wrong answer, even if a test accepts it.

**Minute 45-55: `/review H-03`.** Type `/new`, then `/review H-03`. The review is a separate step in a
fresh session on purpose: an agent that checks its own work in the same session passes its own
mistakes. The reviewer runs the code on the `SPEC.md` known answer and on constant data, edits nothing,
and reports PASS or FAIL with the numbers. On FAIL, `/new`, then `/build H-03` again with the reviewer's
one-sentence fix pasted after it. Then read the change
yourselves:

```bash
git status
git diff
```

Can each of you explain every number the test printed? If not, ask the agent to explain one function in
plain English.

**Minute 55-60: `/checkin H-03`.** It runs the task's `definition_of_done`, marks the task `done` in
`CONTRACT.yaml` with a one-line result, shows you the diff and asks "Commit these files? (yes/no)".
OpenCode also asks permission before any `git commit` or `git push` (the repo's `opencode.json` says
so): choose **allow once** only after your team has read the diff, and never **allow always** for a
commit. That permission prompt is the real yes: a free model may skip the question and go straight to
the commit. Check in `git diff CONTRACT.yaml` that only `status` and `result` changed and `owner` and
`started_at` are still there.

<!-- VERIFIED 2026-10-11: OpenCode's permission prompt fired on the `git add` + `git commit` call, and Reject blocked both; a free model skipped the "Commit these files?" question; a check-in changed only `status` and `result`. -->


Next task: `/new`, then `/build H-04`. One task per session, every time.

---

## 7. Session hygiene

- **`/new` for every task.** A fresh session sends fewer tokens per step, so you stay under the per-minute limit. (After a `429` mid-task, type `continue` in the same session instead; see [section 8](#8-when-it-stalls).)
- **`/compact` when a session gets long** and answers get slow or vague. It summarises the conversation.
- **Read the diff after every task** (`git diff`). The agent's summary is not proof; the test output is.
- **Stage files by name** (`git add app/qc.py tests/test_qc.py`), never `git add .`.

<!-- UNVERIFIED: /new and /compact are documented TUI commands but were not exercised on 2026-10-10. -->

---

## 8. When it stalls

| You see | What it means | Do this |
|---|---|---|
| `429`, `RESOURCE_EXHAUSTED` or `quota`, and the agent stops | a per-minute limit ("Please retry in ...s") or the daily one | wait one minute, then type `continue` in the **same** session (not `/new`: it would repeat every step and hit the same limit); still failing → daily limit: `/models`, next rung down ([section 5](#5-the-model-ladder-which-model-for-which-job)) |
| `This model is currently experiencing high demand` (a Google `503`) | Google is busy; it is not your quota | OpenCode retries by itself; if it stops, wait a minute and type `continue` |
| Nothing happens for over a minute, no error | no key connected | `opencode auth list`; if Google is missing, `/connect` again |
| `API key not valid` | key copied wrong, or deleted | copy it again, or make a new one |
| `Model exo-free has been deprecated` | you started OpenCode outside the repo folder | `cd` into the repo and run `opencode` again |
| The same error three times | the task is too big | stop; `/stuck`, or `/new` with a smaller task and the error message pasted in |
| It edits a file outside the task | ignoring the task's `owns` list | say "undo that; only touch the files in the task's owns list", then check `git diff` |
| `/build` prints "REVIEW: PASS" or says it reviewed its own work | it did both jobs in one session | ignore that review; `/new`, then `/review` with the task id |
| It commits without asking, or makes up a `started_at` time | it skipped a step | `git reset --soft HEAD~1` undoes the commit and keeps your files; fix the time from `date` |
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
