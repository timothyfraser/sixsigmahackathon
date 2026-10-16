#!/usr/bin/env python3
"""Offline consistency check for the agent bundle (no CI needed, stdlib only).

Usage:
    python tools/check_agent_bundle.py          # checks 1-14, no network, no key
    python tools/check_agent_bundle.py --live   # also checks 15: needs opencode + a connected key

Checks 8-14 keep the /superagent bundle from drifting:
     8 superagent     the router skill exists, names every other skill, cites only real paths,
                      and every wrapper (OpenCode command and agent, AGENTS.md) points at it
     9 front-door     README, CLAUDE, AGENTS, docs/prompts-starter, docs/agents mention /superagent
    10 no-private     no private names or local paths in any tracked or new text file
    11 json-configs   .mcp.json (playwright + context7), .claude/settings.json, opencode.json `mcp`
    12 claude-agents  .claude/agents/*.md have name, description, model; implementer and
                      stats-reviewer keep their statistics rules (in check 7)
    13 root-layout    no new top-level folder (extra context lives under .claude/)
    14 check-script   .claude/skills/superagent/scripts/check.sh exits 0 (skipped without bash)

Exit code 0 = every check passed, 1 = at least one FAIL.
Each failure prints a line starting with "FAIL" that names the file and the expectation.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PINNED_MODELS = ["google/gemini-3.5-flash", "google/gemini-3.1-flash-lite"]
KEY_PATTERNS = [
    r"AIza[0-9A-Za-z_-]{20,}",
    r"sk-[A-Za-z0-9]{20,}",
    r"AQ\.[A-Za-z0-9_-]{20,}",
    r"gh[pousr]_[A-Za-z0-9]{20,}",
]

# Shell commands the agent must ask before running (it once tried to kill every python process).
KILL_PATTERNS = ["*taskkill*", "*pkill*", "*Stop-Process*", "*killall*", "*rm -rf*"]

# Rules the commands and agents must keep. Each entry: (file, label, regex). Case-insensitive.
BUILD_RULES = [
    ("every statistic", r"EVERY statistic"),
    ("R chart limits", r"R chart limits"),
    ("D3 and D4", r"D3.{0,10}D4"),
    ("sigma-hat = R-bar/d2", r"R-bar/d2"),
    ("overall SD is Pp/Ppk", r"Pp and Ppk"),
    ("out-of-control flag per subgroup", r"out-of-control flag for each subgroup"),
    ("no foreground server", r"Never run a server.{0,80}foreground"),
    ("background with a time limit", r"background with a time limit"),
    ("never kill by name", r"Never kill processes by name"),
    ("every third-party import in requirements", r"third-party package you import"),
    ("absolute imports", r"absolute package imports"),
    ("starts from the repo root", r"repo root with one\s+command"),
]
REVIEW_RULES = [
    ("every statistic", r"every statistic"),
    ("sigma-hat = R-bar/d2", r"R-bar/d2"),
    ("overall SD is Pp/Ppk", r"Pp and Ppk"),
    ("R chart limits", r"R chart limits"),
    ("out-of-control flag", r"out-of-control flag"),
    ("statistic/expected/got/verdict table", r"\|\s*statistic\s*\|\s*expected\s*\|\s*got\s*\|\s*verdict\s*\|"),
    ("bare PASS forbidden", r"bare PASS with no table is forbidden"),
]
NUMBERS_RULE = [("known answer without numbers = FILL IN",
                 r"no concrete numbers.{0,80}(counts as FILL IN|still counts as FILL IN)")]
GUARDS = {
    ".opencode/commands/build.md": BUILD_RULES + NUMBERS_RULE + [("STATISTICS in the report", r"^STATISTICS:")],
    ".opencode/agents/implementer.md": BUILD_RULES + NUMBERS_RULE + [("STATISTICS in the report", r"STATISTICS:")],
    ".opencode/commands/review.md": REVIEW_RULES,
    ".opencode/agents/stats-reviewer.md": REVIEW_RULES,
    ".opencode/commands/plan.md": NUMBERS_RULE,
}
# Claude Code subagents keep the same rules as their OpenCode twins (checked when the file exists).
OPTIONAL_GUARDS = {
    ".claude/agents/implementer.md": BUILD_RULES + NUMBERS_RULE + [("STATISTICS in the report", r"STATISTICS:")],
    ".claude/agents/stats-reviewer.md": REVIEW_RULES,
}

SUPERAGENT = ".claude/skills/superagent/SKILL.md"
SUPERAGENT_EXTRA = [".claude/skills/superagent/setup.md", ".claude/skills/superagent/reference/playbook.md"]
CANONICAL_LINE = "Read .claude/skills/superagent/SKILL.md completely"
CLAUDE_SUBAGENTS = ["implementer", "stats-reviewer"]
FRONT_DOORS = ["README.md", "CLAUDE.md", "AGENTS.md", "docs/prompts-starter.md", "docs/agents.md"]
# Repo paths the router cites; the lookbehind skips a match inside a URL or a longer path.
# Cited by the router but written by the team during the hackathon, so they may not exist yet.
# (app/, tests/, data/ are team project folders too; CITED_PATH never matches them.)
TEAM_WRITES = {"docs/plan.md"}
CITED_PATH = re.compile(r"(?<![\w./-])((?:\.claude/(?:skills|agents)|demos|docs)/[A-Za-z0-9_./-]*)")
# Private names and local paths that must never appear in this public repo (case-insensitive).
PRIVATE_PATTERNS = ["sysen_instructors", "research-mcp", "FRASER-LABS/design", "design hub",
                    "broker_whoami", "C:/Users/", "C:\\Users\\"]
PRIVATE_SKIP = {"tools/check_agent_bundle.py", "tools/tests/test_check_agent_bundle.py"}
ROOT_DIRS = [".claude", ".opencode", "demos", "docs", "tools"]
ROOT_DIRS_IF_ON_MAIN = [".github"]
CHECK_SCRIPT = ".claude/skills/superagent/scripts/check.sh"
NESTED_ENV = "CHECK_AGENT_BUNDLE_NESTED"  # set while check.sh runs, so a check.sh that calls us cannot loop


failures = []  # list of (check name, message)


def fail(check, msg):
    failures.append((check, msg))
    print("FAIL [%s] %s" % (check, msg))


def rel(p):
    return p.relative_to(ROOT).as_posix()


def read_text(p):
    """Read a text file as UTF-8 with line endings normalised to LF."""
    return p.read_bytes().decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def split_frontmatter(text):
    """Return (dict, body) or (None, text) when there is no frontmatter block.

    Simple parser: top-level `key: value` lines; indented or `- ` lines under a key
    (a list, or a folded scalar) are attached to the previous key and not parsed further.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, text
    fm = {}
    last = None
    for ln in lines[1:end]:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", ln)
        if m and not ln.startswith((" ", "\t")):
            last = m.group(1)
            fm[last] = m.group(2).strip()
        elif last is not None and (ln.startswith((" ", "\t")) or ln.startswith("- ")):
            fm[last] = (fm[last] + " " + ln.strip()).strip()
        else:
            return {}, "\n".join(lines[end + 1:])  # unparseable line
    body = "\n".join(lines[end + 1:])
    return fm, body


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        if v[0] == '"':
            try:
                return json.loads(v)
            except ValueError:
                return v[1:-1]
        return v[1:-1]
    return v


def folded(v):
    """A `>` or `|` block scalar has its text on following lines; the parser joined them."""
    return v[1:].strip() if v[:1] in (">", "|") else v


def check_skills():
    name = "skills"
    files = sorted((ROOT / ".claude" / "skills").glob("*/SKILL.md"))
    if not files:
        fail(name, ".claude/skills/*/SKILL.md: expected at least one skill, found none")
    for f in files:
        fm, _ = split_frontmatter(read_text(f))
        if not fm:
            fail(name, "%s: expected YAML frontmatter (--- ... ---) with name and description" % rel(f))
            continue
        for key in ("name", "description"):
            if not unquote(folded(fm.get(key, ""))):
                fail(name, "%s: frontmatter is missing a non-empty `%s`" % (rel(f), key))
        desc = unquote(folded(fm.get("description", "")))
        if len(desc) > 1024:
            fail(name, "%s: description is %d chars, expected <= 1024" % (rel(f), len(desc)))
        nm = unquote(fm.get("name", ""))
        if nm and nm != f.parent.name:
            fail(name, "%s: name `%s` should equal its folder name `%s`" % (rel(f), nm, f.parent.name))
    return len(files)


def prompt_blocks():
    doc = ROOT / "docs" / "prompts-starter.md"
    text = read_text(doc)
    blocks = {}
    pat = re.compile(r"<!-- prompt: ([A-Za-z0-9_-]+) -->\n```text\n(.*?)\n```", re.S)
    for m in pat.finditer(text):
        blocks[m.group(1)] = m.group(2)
    n_markers = len(re.findall(r"<!-- prompt: ", text))
    return doc, blocks, n_markers


def check_prompts():
    name = "prompts"
    doc, blocks, n_markers = prompt_blocks()
    if n_markers != len(blocks):
        fail(name, "%s: %d `<!-- prompt: NAME -->` markers but only %d are followed by a ```text block"
             % (rel(doc), n_markers, len(blocks)))
    cmd_dir = ROOT / ".opencode" / "commands"
    cmds = {}
    for f in sorted(cmd_dir.glob("*.md")):
        fm, body = split_frontmatter(read_text(f))
        cmds[f.stem] = (f, body.strip() if fm is not None else None)
    for cname, (f, body) in cmds.items():
        if body is None:
            fail(name, "%s: no frontmatter, cannot extract the command body" % rel(f))
            continue
        if cname not in blocks:
            fail(name, "%s: no `<!-- prompt: %s -->` block in %s" % (rel(f), cname, rel(doc)))
            continue
        a = "\n".join(l.rstrip() for l in body.split("\n")).strip()
        b = "\n".join(l.rstrip() for l in blocks[cname].split("\n")).strip()
        if a != b:
            al, bl = a.split("\n"), b.split("\n")
            line = next((i + 1 for i in range(min(len(al), len(bl))) if al[i] != bl[i]),
                        min(len(al), len(bl)) + 1)
            fail(name, "%s: body differs from the `%s` block in %s (first difference at body line %d)"
                 % (rel(f), cname, rel(doc), line))
    for bname in blocks:
        if bname not in cmds:
            fail(name, "%s: block `%s` has no matching .opencode/commands/%s.md" % (rel(doc), bname, bname))
    return len(cmds)


def check_config():
    name = "config"
    f = ROOT / "opencode.json"
    try:
        data = json.loads(read_text(f))
    except (OSError, ValueError) as e:
        fail(name, "opencode.json: expected valid JSON (%s)" % e)
        return None
    model = data.get("model")
    if not isinstance(model, str) or not model.startswith("google/"):
        fail(name, "opencode.json: expected a `model` string starting with \"google/\", got %r" % (model,))
        return None
    return model


def check_frontmatter():
    name = "frontmatter"
    files = sorted((ROOT / ".opencode" / "agents").glob("*.md")) + \
        sorted((ROOT / ".opencode" / "commands").glob("*.md"))
    if not files:
        fail(name, ".opencode/{agents,commands}/*.md: expected files, found none")
    for f in files:
        fm, _ = split_frontmatter(read_text(f))
        if fm is None:
            fail(name, "%s: expected frontmatter (--- ... ---) at the top of the file" % rel(f))
        elif not fm:
            fail(name, "%s: frontmatter does not parse as key: value lines" % rel(f))
        elif not unquote(fm.get("description", "")):
            fail(name, "%s: frontmatter is missing a non-empty `description`" % rel(f))
    return len(files)


def check_kill_permissions(data=None):
    """opencode.json must `ask` before any process kill or rm -rf (permissions: [{action, resource, effect}])."""
    name = "kill-guards"
    if data is None:
        try:
            data = json.loads(read_text(ROOT / "opencode.json"))
        except (OSError, ValueError) as e:
            fail(name, "opencode.json: expected valid JSON (%s)" % e)
            return 0
    rules = data.get("permissions")
    if not isinstance(rules, list):
        fail(name, "opencode.json: expected a `permissions` array of {action, resource, effect}, got %r"
             % type(rules).__name__)
        return 0
    asks = set()
    for r in rules:
        if not isinstance(r, dict) or set(r) != {"action", "resource", "effect"}:
            fail(name, "opencode.json: permission rule %r should have exactly action, resource, effect" % (r,))
            continue
        if r["action"] == "shell" and r["effect"] in ("ask", "deny"):
            asks.add(r["resource"])
    for pat in KILL_PATTERNS:
        if pat not in asks:
            fail(name, "opencode.json: expected a shell rule {resource: %r, effect: ask} in `permissions`" % pat)
        else:
            # The last matching rule wins: a later allow on the same resource would undo the ask.
            last = [r for r in rules if isinstance(r, dict) and r.get("action") == "shell"
                    and r.get("resource") == pat][-1]
            if last.get("effect") == "allow":
                fail(name, "opencode.json: the last rule for %r is allow, expected ask" % pat)
    return len(KILL_PATTERNS)


def check_guards(texts=None):
    """The command and agent prompts keep the statistics, review and process-safety rules."""
    name = "guards"
    n = 0
    items = list(GUARDS.items()) + [(f, r) for f, r in OPTIONAL_GUARDS.items()
                                    if (f in texts if texts is not None else (ROOT / f).is_file())]
    for f, rules in items:
        if texts is not None:
            text = texts.get(f)
        else:
            try:
                text = read_text(ROOT / f)
            except OSError:
                text = None
        if text is None:
            fail(name, "%s: file missing, expected it to hold %d rules" % (f, len(rules)))
            continue
        flat = re.sub(r"\s+", " ", text)
        for label, rx in rules:
            n += 1
            src = text if rx.startswith("^") else flat
            if not re.search(rx, src, re.I | re.M):
                fail(name, "%s: lost the rule `%s` (expected text matching /%s/)" % (f, label, rx))
    return n


def section(text, heading):
    m = re.search(r"^## %s\s*$" % re.escape(heading), text, re.M)
    if not m:
        return None
    rest = text[m.end():]
    n = re.search(r"^## ", rest, re.M)
    body = rest[:n.start()] if n else rest
    return "\n".join(l.rstrip() for l in body.split("\n")).strip()


def check_which_command():
    name = "which-command"
    heading = "Which command, when"
    secs = {}
    for fn in ("CLAUDE.md", "AGENTS.md"):
        secs[fn] = section(read_text(ROOT / fn), heading)
        if secs[fn] is None:
            fail(name, "%s: expected a `## %s` section" % (fn, heading))
    if all(v is not None for v in secs.values()) and secs["CLAUDE.md"] != secs["AGENTS.md"]:
        a, b = secs["CLAUDE.md"].split("\n"), secs["AGENTS.md"].split("\n")
        line = next((i + 1 for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)) + 1)
        fail(name, "CLAUDE.md vs AGENTS.md: `## %s` sections differ (first difference at section line %d)"
             % (heading, line))


def tracked_files():
    try:
        out = subprocess.run(["git", "ls-files", "-z"], cwd=str(ROOT), check=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
        return [ROOT / p for p in out.decode("utf-8").split("\0") if p]
    except (OSError, subprocess.CalledProcessError) as e:
        # Not a git checkout (for example a plain copy): fall back to walking the tree.
        print("NOTE  [secrets] git ls-files unavailable (%s); scanning all files except .git" % e)
        return [p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.relative_to(ROOT).parts]


def check_secrets():
    name = "secrets"
    regs = [re.compile(p) for p in KEY_PATTERNS]
    scanned = 0
    for p in tracked_files():
        if not p.is_file():
            continue
        try:
            raw = p.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:8192]:
            continue  # binary
        scanned += 1
        text = raw.decode("utf-8", errors="replace")
        for r in regs:
            m = r.search(text)
            if m:
                line = text.count("\n", 0, m.start()) + 1
                shown = m.group(0)[:4] + "..." + " (%d chars)" % len(m.group(0))
                fail(name, "%s:%d: key-shaped string %s matches /%s/, expected none"
                     % (rel(p), line, shown, r.pattern))
    return scanned


def git_lines(args):
    """Run git in ROOT and return its output lines, or None when git or the repo is unavailable."""
    try:
        out = subprocess.run(["git"] + args, cwd=str(ROOT), check=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return [l for l in out.decode("utf-8").replace("\0", "\n").split("\n") if l]


def candidate_files():
    """Tracked files plus new, not-ignored files: everything the next commit could publish."""
    lines = git_lines(["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
    if lines is None:
        print("NOTE  [no-private] git ls-files unavailable; scanning all files except .git")
        return [p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.relative_to(ROOT).parts]
    return [ROOT / l for l in sorted(set(lines))]


def try_read(p):
    try:
        return read_text(p)
    except (OSError, UnicodeDecodeError):
        return None


def names_word(text, word):
    return re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(word), text) is not None


def check_superagent():
    """The router exists, names every other skill, cites only real paths; every wrapper points at it."""
    name = "superagent"
    text = try_read(ROOT / SUPERAGENT)
    if text is None:
        fail(name, "%s: missing, expected the /superagent router skill" % SUPERAGENT)
        return 0
    fm, _ = split_frontmatter(text)
    if not fm:
        fail(name, "%s: expected YAML frontmatter (--- ... ---) with name and description" % SUPERAGENT)
    else:
        if unquote(fm.get("name", "")) != "superagent":
            fail(name, "%s: frontmatter `name` is %r, expected `superagent`" % (SUPERAGENT, fm.get("name")))
        desc = unquote(folded(fm.get("description", "")))
        if not desc:
            fail(name, "%s: frontmatter is missing a non-empty `description`" % SUPERAGENT)
        elif len(desc) > 1024:
            fail(name, "%s: description is %d chars, expected <= 1024" % (SUPERAGENT, len(desc)))
    for d in sorted(p for p in (ROOT / ".claude" / "skills").iterdir() if p.is_dir() and p.name != "superagent"):
        if not names_word(text, d.name):
            fail(name, "%s: does not name the skill `%s` (expected `.claude/skills/%s/` or `%s` in the router)"
                 % (SUPERAGENT, d.name, d.name, d.name))
    for sub in CLAUDE_SUBAGENTS:
        if not names_word(text, sub):
            fail(name, "%s: does not mention the Claude Code subagent `%s` (.claude/agents/%s.md)"
                 % (SUPERAGENT, sub, sub))
    n = 0
    for src in [SUPERAGENT] + SUPERAGENT_EXTRA:
        t = text if src == SUPERAGENT else try_read(ROOT / src)
        if t is None:
            continue
        for m in CITED_PATH.finditer(t):
            path = m.group(1).rstrip(".,:;)")
            if path.rstrip("/") in ("docs", "demos", ".claude/skills", ".claude/agents") or path in TEAM_WRITES:
                continue
            n += 1
            if not (ROOT / path).exists():
                fail(name, "%s:%d: cites `%s`, expected that path to exist"
                     % (src, t.count("\n", 0, m.start()) + 1, path))
    cmd = ".opencode/commands/superagent.md"
    t = try_read(ROOT / cmd)
    if t is None:
        fail(name, "%s: missing, expected the OpenCode wrapper for /superagent" % cmd)
    elif CANONICAL_LINE not in t:
        fail(name, "%s: expected the canonical line `%s`" % (cmd, CANONICAL_LINE))
    agent = ".opencode/agents/superagent.md"
    t = try_read(ROOT / agent)
    if t is None:
        fail(name, "%s: missing, expected the OpenCode superagent agent" % agent)
    elif CANONICAL_LINE not in t and SUPERAGENT not in t:
        fail(name, "%s: expected the canonical line `%s` or a pointer to %s" % (agent, CANONICAL_LINE, SUPERAGENT))
    t = try_read(ROOT / "AGENTS.md")
    if t is None or SUPERAGENT not in t:
        fail(name, "AGENTS.md: expected it to name %s (Cursor, Codex and Copilot read AGENTS.md)" % SUPERAGENT)
    return n


def check_front_door():
    name = "front-door"
    for f in FRONT_DOORS:
        t = try_read(ROOT / f)
        if t is None:
            fail(name, "%s: missing, expected it to mention `/superagent`" % f)
        elif "/superagent" not in t:
            fail(name, "%s: expected it to mention `/superagent` (the one front door)" % f)
    return len(FRONT_DOORS)


def check_no_private(files=None):
    name = "no-private"
    regs = [(p, re.compile(re.escape(p), re.I)) for p in PRIVATE_PATTERNS]
    scanned = 0
    for p in (candidate_files() if files is None else files):
        if rel(p) in PRIVATE_SKIP or not p.is_file():
            continue
        try:
            raw = p.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:8192]:
            continue  # binary
        scanned += 1
        text = raw.decode("utf-8", errors="replace")
        for pat, r in regs:
            m = r.search(text)
            if m:
                fail(name, "%s:%d: contains the private string %r, expected none in this public repo"
                     % (rel(p), text.count("\n", 0, m.start()) + 1, pat))
    return scanned


def load_json(name, f, required):
    p = ROOT / f
    if not p.is_file():
        if required:
            fail(name, "%s: missing, expected it to exist and parse as JSON" % f)
        return None
    try:
        return json.loads(read_text(p))
    except ValueError as e:
        fail(name, "%s: expected valid JSON (%s)" % (f, e))
        return None


def check_json_configs():
    name = "json-configs"
    mcp = load_json(name, ".mcp.json", True)
    if mcp is not None:
        servers = mcp.get("mcpServers") if isinstance(mcp, dict) else None
        if not isinstance(servers, dict):
            fail(name, ".mcp.json: expected an `mcpServers` object")
        else:
            for s in ("playwright", "context7"):
                if s not in servers:
                    fail(name, ".mcp.json: expected `mcpServers.%s`" % s)
    load_json(name, ".claude/settings.json", False)
    oc = load_json(name, "opencode.json", True)
    if isinstance(oc, dict) and "mcp" in oc:
        block = oc["mcp"]
        if not isinstance(block, dict):
            fail(name, "opencode.json: `mcp` should be an object of servers, got %s" % type(block).__name__)
        else:
            for k, v in block.items():
                t = v.get("type") if isinstance(v, dict) else None
                if t not in ("local", "remote"):
                    fail(name, "opencode.json: `mcp.%s.type` is %r, expected \"local\" or \"remote\"" % (k, t))


def check_claude_agents():
    name = "claude-agents"
    d = ROOT / ".claude" / "agents"
    files = sorted(d.glob("*.md")) if d.is_dir() else []
    have = {f.stem for f in files}
    for sub in CLAUDE_SUBAGENTS:
        if sub not in have:
            fail(name, ".claude/agents/%s.md: missing, expected a Claude Code subagent" % sub)
    for f in files:
        fm, _ = split_frontmatter(read_text(f))
        if not fm:
            fail(name, "%s: expected frontmatter (--- ... ---) with name, description, model" % rel(f))
            continue
        for key in ("name", "description", "model"):
            if not unquote(folded(fm.get(key, ""))):
                fail(name, "%s: frontmatter is missing a non-empty `%s`" % (rel(f), key))
        nm = unquote(fm.get("name", ""))
        if nm and nm != f.stem:
            fail(name, "%s: name `%s` should equal the file name `%s`" % (rel(f), nm, f.stem))
    return len(files)


def check_root_layout(paths=None, allowed=None):
    """No top-level folder beyond the allowlist (no new root folders; new context goes under .claude/)."""
    name = "root-layout"
    if allowed is None:
        allowed = set(ROOT_DIRS)
        for ref in ("main", "origin/main", "HEAD"):
            main_dirs = git_lines(["ls-tree", "-d", "--name-only", ref])
            if main_dirs is not None:
                allowed |= set(ROOT_DIRS_IF_ON_MAIN) & set(main_dirs)
                break
    if paths is None:
        paths = git_lines(["ls-files", "--cached", "--others", "--exclude-standard"])
        if paths is None:
            print("NOTE  [root-layout] git ls-files unavailable; listing top-level folders on disk")
            paths = [p.name + "/" for p in ROOT.iterdir() if p.is_dir() and p.name != ".git"]
    tops = sorted({p.split("/", 1)[0] for p in paths if "/" in p})
    for t in tops:
        if t not in allowed:
            fail(name, "%s/: new top-level folder, expected only %s (put new context under .claude/)"
                 % (t, ", ".join(sorted(allowed))))
    return len(tops)


def check_check_script():
    """Run the superagent's own check.sh from the repo root; returns pass, fail or skip."""
    name = "check-script"
    if os.environ.get(NESTED_ENV):
        print("NOTE  [check-script] called from inside check.sh; not running it again")
        return "skip"
    if not (ROOT / CHECK_SCRIPT).is_file():
        print("NOTE  [check-script] %s not present; skipping" % CHECK_SCRIPT)
        return "skip"
    bash = shutil.which("bash")
    if not bash:
        print("NOTE  [check-script] bash is not on PATH; skipping %s" % CHECK_SCRIPT)
        return "skip"
    env = dict(os.environ, **{NESTED_ENV: "1"})
    try:
        res = subprocess.run([bash, CHECK_SCRIPT], cwd=str(ROOT), env=env, timeout=300,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except subprocess.TimeoutExpired:
        fail(name, "%s: did not finish within 300 s, expected exit 0" % CHECK_SCRIPT)
        return "fail"
    if res.returncode != 0:
        tail = res.stdout.decode("utf-8", errors="replace").strip().splitlines()[-5:]
        fail(name, "%s: exited %d, expected 0. Last lines: %s" % (CHECK_SCRIPT, res.returncode, " | ".join(tail)))
        return "fail"
    return "pass"


def check_live(model):
    name = "live"
    try:
        res = subprocess.run(["opencode", "models"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             timeout=60, shell=(sys.platform == "win32"))
    except FileNotFoundError:
        print("NOTE  [live] opencode is not installed; skipping the live model check")
        return "skip"
    except subprocess.TimeoutExpired:
        fail(name, "`opencode models` did not finish within 60 s")
        return "fail"
    out = res.stdout.decode("utf-8", errors="replace")
    listed = set(l.strip() for l in out.splitlines() if l.strip())
    if res.returncode != 0 and not listed:
        print("NOTE  [live] `opencode models` exited %d; skipping" % res.returncode)
        return "skip"
    if not any(m.startswith("google/") for m in listed):
        print("NOTE  [live] opencode lists no google/ models (no key connected? run /connect); skipping")
        return "skip"
    ok = True
    wanted = [model] if model else []
    wanted += [m for m in PINNED_MODELS if m not in wanted]
    for m in wanted:
        if m not in listed:
            fail(name, "`opencode models` does not list %s (expected it from opencode.json or the pinned models)" % m)
            ok = False
    return "pass" if ok else "fail"


def main():
    live = "--live" in sys.argv[1:]
    results = []

    def run(label, fn, *a, detail=None):
        before = len(failures)
        r = fn(*a)
        ok = len(failures) == before
        results.append((label, ok))
        print("%s  %s%s" % ("PASS" if ok else "FAIL", label, (" (%s)" % detail(r)) if (ok and detail) else ""))
        return r

    run("1 skills have name + description <= 1024", check_skills, detail=lambda r: "%d skills" % r)
    run("2 command bodies equal prompts-starter.md blocks", check_prompts, detail=lambda r: "%d commands" % r)
    model = run("3 opencode.json parses, model is google/*", check_config, detail=lambda r: r)
    run("4 agent + command frontmatter parses with description", check_frontmatter,
        detail=lambda r: "%d files" % r)
    run("5 CLAUDE.md and AGENTS.md `Which command, when` identical", check_which_command)
    run("6 no key-shaped strings in tracked text files", check_secrets, detail=lambda r: "%d files scanned" % r)
    run("7 bundle guards: kill rules ask, statistics/review/known-answer rules present",
        lambda: (check_kill_permissions(), check_guards())[1], detail=lambda r: "%d rules" % (r + len(KILL_PATTERNS)))
    run("8 superagent router: frontmatter, every skill named, cited paths exist, wrappers point at it",
        check_superagent, detail=lambda r: "%d cited paths" % r)
    run("9 front doors mention /superagent", check_front_door, detail=lambda r: "%d files" % r)
    run("10 no private names or local paths in tracked or new text files", check_no_private,
        detail=lambda r: "%d files scanned" % r)
    run("11 .mcp.json, .claude/settings.json, opencode.json mcp parse", check_json_configs)
    run("12 .claude/agents frontmatter has name, description, model", check_claude_agents,
        detail=lambda r: "%d agents" % r)
    run("13 no new top-level folders", check_root_layout, detail=lambda r: "%d folders" % r)
    st = check_check_script()
    if st == "skip":
        print("SKIP  14 superagent scripts/check.sh exits 0")
    else:
        results.append(("14 check.sh", st == "pass"))
        print("%s  14 superagent scripts/check.sh exits 0" % ("PASS" if st == "pass" else "FAIL"))
    if live:
        st = check_live(model)
        if st == "skip":
            print("SKIP  15 live: opencode models list the configured and pinned models")
        else:
            results.append(("15 live", st == "pass"))
            print("%s  15 live: opencode models list the configured and pinned models"
                  % ("PASS" if st == "pass" else "FAIL"))
    bad = [l for l, ok in results if not ok]
    print("")
    if bad:
        print("SUMMARY: FAIL - %d of %d checks failed: %s" % (len(bad), len(results), "; ".join(bad)))
        return 1
    print("SUMMARY: PASS - all %d checks passed" % len(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
