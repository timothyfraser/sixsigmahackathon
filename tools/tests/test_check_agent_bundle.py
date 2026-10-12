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
