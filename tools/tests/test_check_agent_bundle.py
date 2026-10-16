"""Tests for tools/check_agent_bundle.py: the real bundle passes, and each guard fails loudly when removed."""
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("check_agent_bundle", ROOT / "tools" / "check_agent_bundle.py")
cab = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cab)


@pytest.fixture(autouse=True)
def clear_failures():
    cab.failures.clear()
    yield
    cab.failures.clear()


def real_texts():
    return {f: cab.read_text(ROOT / f) for f in cab.GUARDS}


def messages():
    return [m for _, m in cab.failures]


def test_real_bundle_passes_every_offline_check():
    cab.check_skills()
    cab.check_prompts()
    cab.check_config()
    cab.check_frontmatter()
    cab.check_which_command()
    cab.check_kill_permissions()
    cab.check_guards()
    assert cab.failures == []


@pytest.mark.parametrize("pattern", cab.KILL_PATTERNS)
def test_missing_kill_rule_fails(pattern):
    data = {"permissions": [{"action": "shell", "resource": p, "effect": "ask"}
                            for p in cab.KILL_PATTERNS if p != pattern]}
    cab.check_kill_permissions(data)
    assert any(pattern in m for m in messages()), messages()


def test_kill_rule_overridden_by_later_allow_fails():
    rules = [{"action": "shell", "resource": p, "effect": "ask"} for p in cab.KILL_PATTERNS]
    rules.append({"action": "shell", "resource": "*taskkill*", "effect": "allow"})
    cab.check_kill_permissions({"permissions": rules})
    assert any("last rule" in m and "*taskkill*" in m for m in messages()), messages()


def test_v1_permission_object_shape_fails():
    cab.check_kill_permissions({"permission": {"bash": {"*taskkill*": "ask"}}})
    assert any("`permissions` array" in m for m in messages()), messages()


@pytest.mark.parametrize("f, phrase", [
    (".opencode/commands/build.md", "R-bar/d2"),
    (".opencode/commands/build.md", "R chart limits"),
    (".opencode/commands/build.md", "Never kill processes by name"),
    (".opencode/commands/build.md", "background with a time limit"),
    (".opencode/commands/build.md", "absolute package imports"),
    (".opencode/agents/implementer.md", "R-bar/d2"),
    (".opencode/agents/implementer.md", "Never kill processes by name"),
    (".opencode/commands/review.md", "bare PASS with no table is forbidden"),
    (".opencode/agents/stats-reviewer.md", "bare PASS with no table is forbidden"),
    (".opencode/commands/review.md", "R-bar/d2"),
])
def test_removing_a_rule_fails(f, phrase):
    texts = real_texts()
    assert phrase.lower() in texts[f].lower(), "test setup: %s should contain %r" % (f, phrase)
    texts[f] = texts[f].replace(phrase, "").replace(phrase.lower(), "")
    cab.check_guards(texts)
    assert any(m.startswith(f) for m in messages()), messages()


@pytest.mark.parametrize("f", [".opencode/commands/plan.md", ".opencode/commands/build.md",
                               ".opencode/agents/implementer.md"])
def test_known_answer_without_numbers_rule_required(f):
    texts = real_texts()
    texts[f] = texts[f].replace("no concrete numbers", "no numbers")
    cab.check_guards(texts)
    assert any(m.startswith(f) and "FILL IN" in m for m in messages()), messages()


def test_review_table_header_required():
    texts = real_texts()
    f = ".opencode/commands/review.md"
    texts[f] = texts[f].replace("| statistic | expected | got | verdict |", "| check | PASS/FAIL |")
    cab.check_guards(texts)
    assert any(m.startswith(f) and "table" in m for m in messages()), messages()


# ---- checks 8-14: the /superagent bundle, on temp fixtures (ROOT is patched to tmp_path) ----

ROUTER = """---
name: superagent
description: One front door. Routes to every other skill.
---
# superagent
| need | load |
|---|---|
| words | `.claude/skills/glossary/SKILL.md` |
| demo | `demos/fastapi/` and docs/agents.md |
Subagents: implementer, stats-reviewer (`.claude/agents/implementer.md`).
"""
CANON = ("Read .claude/skills/superagent/SKILL.md completely, then follow it, starting at its section 0.\n\n"
         "Our app, in our own words (may be blank): $ARGUMENTS\n")


def write(root, path, text):
    p = root / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    return p


@pytest.fixture
def bundle(tmp_path, monkeypatch):
    monkeypatch.setattr(cab, "ROOT", tmp_path)
    write(tmp_path, ".claude/skills/superagent/SKILL.md", ROUTER)
    write(tmp_path, ".claude/skills/glossary/SKILL.md", "---\nname: glossary\ndescription: words\n---\n")
    write(tmp_path, "demos/fastapi/app.py", "print(1)\n")
    for f in cab.FRONT_DOORS:
        write(tmp_path, f, "Type /superagent. See .claude/skills/superagent/SKILL.md\n")
    write(tmp_path, ".opencode/commands/superagent.md", "---\ndescription: x\n---\n" + CANON)
    write(tmp_path, ".opencode/agents/superagent.md", "---\ndescription: x\n---\n" + CANON)
    write(tmp_path, ".mcp.json", '{"mcpServers": {"playwright": {"command": "npx"}, '
                                 '"context7": {"type": "http", "url": "https://mcp.context7.com/mcp"}}}')
    write(tmp_path, "opencode.json", '{"model": "google/x", "mcp": {"playwright": {"type": "local"}, '
                                     '"context7": {"type": "remote"}}}')
    write(tmp_path, ".claude/settings.json", '{"permissions": {"allow": []}}')
    for a in cab.CLAUDE_SUBAGENTS:
        write(tmp_path, ".claude/agents/%s.md" % a, "---\nname: %s\ndescription: d\nmodel: sonnet\n---\nbody\n" % a)
    return tmp_path


def test_superagent_fixture_passes(bundle):
    assert cab.check_superagent() >= 3
    assert cab.failures == []


def test_superagent_missing_router_fails(bundle):
    (bundle / cab.SUPERAGENT).unlink()
    cab.check_superagent()
    assert any("router skill" in m for m in messages()), messages()


def test_superagent_wrong_name_fails(bundle):
    write(bundle, cab.SUPERAGENT, ROUTER.replace("name: superagent", "name: router"))
    cab.check_superagent()
    assert any("expected `superagent`" in m for m in messages()), messages()


def test_superagent_unnamed_skill_fails(bundle):
    write(bundle, ".claude/skills/new-thing/SKILL.md", "---\nname: new-thing\ndescription: d\n---\n")
    cab.check_superagent()
    assert any("`new-thing`" in m for m in messages()), messages()


def test_superagent_dead_cited_path_fails(bundle):
    write(bundle, cab.SUPERAGENT, ROUTER + "Also read docs/nope.md.\n")
    cab.check_superagent()
    assert any("cites `docs/nope.md`" in m for m in messages()), messages()


def test_superagent_dead_path_in_setup_fails(bundle):
    write(bundle, ".claude/skills/superagent/setup.md", "Run `.claude/skills/superagent/scripts/gone.sh`.\n")
    cab.check_superagent()
    assert any(m.startswith(".claude/skills/superagent/setup.md:1") for m in messages()), messages()


def test_superagent_missing_subagent_mention_fails(bundle):
    write(bundle, cab.SUPERAGENT, ROUTER.replace(", stats-reviewer", ""))
    cab.check_superagent()
    assert any("subagent `stats-reviewer`" in m for m in messages()), messages()


def test_superagent_wrapper_without_canonical_line_fails(bundle):
    write(bundle, ".opencode/commands/superagent.md", "---\ndescription: x\n---\nDo the thing.\n")
    cab.check_superagent()
    assert any(m.startswith(".opencode/commands/superagent.md") for m in messages()), messages()


def test_superagent_agents_md_without_pointer_fails(bundle):
    write(bundle, "AGENTS.md", "Type /superagent.\n")
    cab.check_superagent()
    assert any(m.startswith("AGENTS.md") for m in messages()), messages()


def test_front_door_passes_and_fails(bundle):
    cab.check_front_door()
    assert cab.failures == []
    write(bundle, "docs/agents.md", "no front door here\n")
    cab.check_front_door()
    assert any(m.startswith("docs/agents.md") for m in messages()), messages()


@pytest.mark.parametrize("bad", ["see C:/Users/someone/x", "the Design Hub", "sysen_instructors repo",
                                 "C:\\Users\\someone"])
def test_no_private_fails(bundle, bad):
    ok = write(bundle, "docs/ok.md", "clean text\n")
    leak = write(bundle, "docs/leak.md", "line one\n" + bad + "\n")
    cab.check_no_private([ok])
    assert cab.failures == []
    cab.check_no_private([ok, leak])
    assert any(m.startswith("docs/leak.md:2") for m in messages()), messages()


def test_no_private_skips_the_checker_itself(bundle):
    f = write(bundle, "tools/check_agent_bundle.py", "PRIVATE = ['research-mcp']\n")
    cab.check_no_private([f])
    assert cab.failures == []


def test_json_configs_pass(bundle):
    cab.check_json_configs()
    assert cab.failures == []


@pytest.mark.parametrize("path, text, expect", [
    (".mcp.json", '{"mcpServers": {"playwright": {}}}', "mcpServers.context7"),
    (".mcp.json", "{not json", "valid JSON"),
    (".claude/settings.json", "{,}", ".claude/settings.json"),
    ("opencode.json", '{"model": "google/x", "mcp": {"pw": {"type": "stdio"}}}', "mcp.pw.type"),
])
def test_json_configs_fail(bundle, path, text, expect):
    write(bundle, path, text)
    cab.check_json_configs()
    assert any(expect in m for m in messages()), messages()


def test_json_configs_missing_mcp_json_fails(bundle):
    (bundle / ".mcp.json").unlink()
    cab.check_json_configs()
    assert any(m.startswith(".mcp.json: missing") for m in messages()), messages()


def test_claude_agents_pass_and_missing_model_fails(bundle):
    assert cab.check_claude_agents() == 2
    assert cab.failures == []
    write(bundle, ".claude/agents/implementer.md", "---\nname: implementer\ndescription: d\n---\n")
    cab.check_claude_agents()
    assert any("implementer.md" in m and "`model`" in m for m in messages()), messages()


def test_claude_agents_missing_file_fails(bundle):
    (bundle / ".claude/agents/stats-reviewer.md").unlink()
    cab.check_claude_agents()
    assert any("stats-reviewer.md: missing" in m for m in messages()), messages()


def test_optional_guards_apply_to_claude_agents():
    texts = real_texts()
    texts[".claude/agents/stats-reviewer.md"] = "a reviewer with no rules"
    cab.check_guards(texts)
    assert any(m.startswith(".claude/agents/stats-reviewer.md") for m in messages()), messages()
    cab.failures.clear()
    texts[".claude/agents/stats-reviewer.md"] = real_texts()[".opencode/agents/stats-reviewer.md"]
    cab.check_guards(texts)
    assert cab.failures == []


def test_root_layout_pass_and_new_folder_fails():
    ok = ["README.md", ".claude/skills/x/SKILL.md", "docs/a.md", "tools/t.py", "demos/d/x", ".opencode/a.md"]
    cab.check_root_layout(ok, set(cab.ROOT_DIRS))
    assert cab.failures == []
    cab.check_root_layout(ok + ["superagent/SKILL.md"], set(cab.ROOT_DIRS))
    assert any(m.startswith("superagent/: new top-level folder") for m in messages()), messages()


def test_root_layout_github_needs_to_be_on_main():
    cab.check_root_layout([".github/workflows/x.yml"], set(cab.ROOT_DIRS))
    assert any(m.startswith(".github/") for m in messages()), messages()


@pytest.mark.skipif(cab.shutil.which("bash") is None, reason="bash not on PATH")
@pytest.mark.parametrize("code, ok", [(0, True), (3, False)])
def test_check_script_exit_code(bundle, monkeypatch, code, ok):
    monkeypatch.delenv(cab.NESTED_ENV, raising=False)
    write(bundle, cab.CHECK_SCRIPT, "echo running\nexit %d\n" % code)
    assert cab.check_check_script() == ("pass" if ok else "fail")
    assert (cab.failures == []) is ok


def test_check_script_absent_or_nested_skips(bundle, monkeypatch):
    monkeypatch.delenv(cab.NESTED_ENV, raising=False)
    assert cab.check_check_script() == "skip"
    write(bundle, cab.CHECK_SCRIPT, "exit 1\n")
    monkeypatch.setenv(cab.NESTED_ENV, "1")
    assert cab.check_check_script() == "skip"
    assert cab.failures == []


def test_real_bundle_passes_superagent_checks():
    """The wave's gate: the real repo passes checks 8-13 once every unit has landed."""
    cab.check_superagent()
    cab.check_front_door()
    cab.check_no_private()
    cab.check_json_configs()
    cab.check_claude_agents()
    cab.check_root_layout()
    cab.check_guards()
    assert cab.failures == [], "\n".join(messages())
