#!/usr/bin/env python3
"""Offline consistency check for the agent bundle (no CI needed, stdlib only).

Usage:
    python tools/check_agent_bundle.py          # checks 1-7, no network, no key
    python tools/check_agent_bundle.py --live   # also checks 8: needs opencode + a connected key

Exit code 0 = every check passed, 1 = at least one FAIL.
Each failure prints a line starting with "FAIL" that names the file and the expectation.
"""
import json
import re
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
    for f, rules in GUARDS.items():
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
    if live:
        st = check_live(model)
        if st == "skip":
            print("SKIP  8 live: opencode models list the configured and pinned models")
        else:
            results.append(("8 live", st == "pass"))
            print("%s  8 live: opencode models list the configured and pinned models"
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
