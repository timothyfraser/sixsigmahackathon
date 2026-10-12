"""Offline tests for the model ladder plugin (.opencode/plugins/model-ladder.*). Needs Node 18+."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
LIB = (ROOT / ".opencode/plugins/model-ladder.lib.mjs").as_uri()
NODE = shutil.which("node")
pytestmark = pytest.mark.skipif(NODE is None, reason="node not installed")

DAILY = ('{"error":{"code":429,"message":"You exceeded your current quota. * Quota exceeded for metric: '
         'generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 500, model: '
         'gemini-3.1-flash-lite\nPlease retry in 1h1m15s.","status":"RESOURCE_EXHAUSTED","details":[{"@type":'
         '"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaId":'
         '"GenerateRequestsPerDayPerProjectPerModel-FreeTier"}]},{"@type":"type.googleapis.com/google.rpc.RetryInfo",'
         '"retryDelay":"3675s"}]}}')
MINUTE = ('{"error":{"code":429,"message":"Quota exceeded for metric: generate_content_free_tier_requests, '
          'limit: 15, model: gemini-3.5-flash-lite\nPlease retry in 41.2s.","status":"RESOURCE_EXHAUSTED",'
          '"details":[{"violations":[{"quotaId":"GenerateRequestsPerMinutePerProjectPerModel-FreeTier"}]},'
          '{"retryDelay":"41s"}]}}')
LONG_NO_ID = '{"error":{"code":429,"message":"Resource exhausted. Please retry in 2h3m.","status":"RESOURCE_EXHAUSTED"}}'
HIGH_DEMAND = ('{"error":{"code":503,"message":"This model is currently experiencing high demand. '
               'Please try again later.","status":"UNAVAILABLE"}}')


def js(expr: str):
    code = f'import * as L from "{LIB}"; console.log(JSON.stringify({expr}));'
    out = subprocess.run([NODE, "--input-type=module", "-e", code], capture_output=True, text=True, cwd=ROOT)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def test_ladder_order_flash_lite_first_no_gemma():
    ladder = js("L.LADDER")
    assert ladder[0] == "google/gemini-3.5-flash-lite"
    lite = [i for i, m in enumerate(ladder) if "flash-lite" in m]
    flash = [i for i, m in enumerate(ladder) if "flash-lite" not in m]
    assert max(lite) < min(flash), "every flash-lite rung must come before every flash rung"
    assert not any("gemma" in m for m in ladder)
    assert len(set(ladder)) == len(ladder)


@pytest.mark.parametrize("payload,expected", [
    (DAILY, "daily"), (MINUTE, "minute"), (LONG_NO_ID, "daily"), (HIGH_DEMAND, "other"),
    ('{"error":{"code":401,"message":"API key not valid"}}', "other"),
])
def test_classify(payload, expected):
    assert js(f"L.classify({json.dumps(payload)})") == expected


def test_retry_seconds_and_model_name():
    assert js(f"L.retrySeconds({json.dumps(DAILY)})") == 3675
    assert js(f"L.modelFromError({json.dumps(DAILY)})") == "google/gemini-3.1-flash-lite"


def test_next_skips_exhausted_rungs():
    assert js('L.nextModel("google/gemini-3.5-flash-lite", [])') == "google/gemini-3.1-flash-lite"
    got = js('L.nextModel("google/gemini-3.5-flash-lite", '
             '["google/gemini-3.1-flash-lite","google/gemini-3.1-flash-lite-preview"])')
    assert got == "google/gemini-3.8-flash"
    assert js('L.nextModel("google/not-on-ladder", ["google/gemini-3.5-flash-lite"])') == "google/gemini-3.1-flash-lite"


def test_next_wraps_around_to_rungs_above():
    # repo default is rung 2; when it and everything below is used up, rung 1 is still fresh
    below = js("L.LADDER.slice(2)")
    assert js(f'L.nextModel("google/gemini-3.1-flash-lite", {json.dumps(below)})') == "google/gemini-3.5-flash-lite"
    # last rung, nothing used up -> wraps to the top rung
    assert js("L.nextModel(L.LADDER[L.LADDER.length-1], [])") == "google/gemini-3.5-flash-lite"
    # rungs below come before rungs above
    assert js('L.nextModel("google/gemini-3.1-flash-lite", [])') == "google/gemini-3.1-flash-lite-preview"
    # never returns current, even when current is not listed as exhausted
    assert js('L.nextModel("google/gemini-3.5-flash-lite", L.LADDER.slice(1))') is None


def test_next_null_only_when_every_rung_is_exhausted():
    assert js('L.nextModel("google/gemini-3.1-flash-lite", L.LADDER)') is None
    assert js('L.nextModel("google/not-on-ladder", L.LADDER)') is None
    assert js('L.nextModel("google/gemini-3.1-flash-lite", L.LADDER.slice(1))') == "google/gemini-3.5-flash-lite"


def test_end_of_ladder_message():
    msg = js("L.END_OF_LADDER")
    assert "used up for today" in msg and "midnight Pacific" in msg
    assert "teammate" in msg and "Zen" in msg


def test_old_state_format_resets_on_new_pacific_day():
    assert js('L.exhaustedNow({day:"2000-01-01",exhausted:["x"]})') == []
    assert js('L.exhaustedNow({day:L.pacificDay(),exhausted:["x"]})') == ["x"]


NOW = 'new Date("2026-10-11T18:00:00Z")'  # 11:00 Pacific (PDT), 13 h before the reset


def test_next_midnight_pacific():
    assert js(f"L.nextMidnightPacific({NOW}).toISOString()") == "2026-10-12T07:00:00.000Z"
    # winter (PST, UTC-8)
    assert js('L.nextMidnightPacific(new Date("2026-12-01T20:00:00Z")).toISOString()') == "2026-12-02T08:00:00.000Z"
    # daylight-saving day: early 2026-11-01 PDT, next midnight is in PST
    assert js('L.nextMidnightPacific(new Date("2026-11-01T08:30:00Z")).toISOString()') == "2026-11-02T08:00:00.000Z"


def test_expiry_uses_retry_time_when_given():
    # "retry in 1h1m15s" / retryDelay 3675s -> back in about an hour, not at midnight
    assert js(f"L.expiryFor({json.dumps(DAILY)}, {NOW}).toISOString()") == "2026-10-11T19:01:15.000Z"


def test_expiry_capped_at_midnight_pacific():
    long_wait = '{"error":{"code":429,"message":"limit: 500 per day. Please retry in 20h.","status":"RESOURCE_EXHAUSTED"}}'
    assert js(f"L.expiryFor({json.dumps(long_wait)}, {NOW}).toISOString()") == "2026-10-12T07:00:00.000Z"


def test_expiry_falls_back_to_midnight_without_retry_time():
    no_wait = '{"error":{"code":429,"message":"GenerateRequestsPerDayPerProjectPerModel","status":"RESOURCE_EXHAUSTED"}}'
    assert js(f"L.expiryFor({json.dumps(no_wait)}, {NOW}).toISOString()") == "2026-10-12T07:00:00.000Z"


def test_state_entries_expire_at_their_own_time():
    st = js(f'L.markInState(null, "google/a", new Date("2026-10-11T19:00:00Z"), {NOW})')
    assert st == {"version": 2, "exhausted": {"google/a": "2026-10-11T19:00:00.000Z"}}
    st_js = json.dumps(st)
    assert js(f"L.exhaustedNow({st_js}, {NOW})") == ["google/a"]
    assert js(f'L.exhaustedNow({st_js}, new Date("2026-10-11T19:00:01Z"))') == []
    # marking a second model keeps live entries and drops expired ones
    st2 = js(f'L.markInState({st_js}, "google/b", new Date("2026-10-12T07:00:00Z"), new Date("2026-10-11T19:30:00Z"))')
    assert st2["exhausted"] == {"google/b": "2026-10-12T07:00:00.000Z"}


def test_plugin_entry_point_switches_and_resumes(tmp_path):
    (tmp_path / ".opencode").mkdir()
    data = json.dumps({"sessionID": "ses_test", "error": {"name": "APIError", "data": {
        "message": "429 Too Many Requests", "statusCode": 429, "isRetryable": False, "responseBody": DAILY}}})
    out = subprocess.run([NODE, "tools/tests/test_model_ladder_harness.mjs", str(tmp_path), data],
                         capture_output=True, text=True, cwd=ROOT)
    assert out.returncode == 0, out.stderr
    res = json.loads(out.stdout)
    assert res["id"] == "model-ladder"
    sw = res["calls"][0]["switchModel"]
    assert sw == {"sessionID": "ses_test", "model": {"providerID": "google", "id": "gemini-3.8-flash"}} or \
        sw["model"]["id"] == "gemini-3.1-flash-lite-preview"
    syn = res["calls"][1]["synthetic"]
    assert syn["resume"] is True and syn["text"].startswith("Daily limit reached on google/gemini-3.1-flash-lite")
    state = json.loads((tmp_path / ".opencode/model-ladder-state.json").read_text())
    assert state["version"] == 2 and "google/gemini-3.1-flash-lite" in state["exhausted"]
    # the error said "retry in 1h1m15s": the model comes back in about an hour, not at midnight
    until = js(f'Date.parse({json.dumps(state["exhausted"]["google/gemini-3.1-flash-lite"])}) - Date.now()')
    assert 3600_000 < until <= 3675_000


def test_per_minute_error_does_not_switch(tmp_path):
    (tmp_path / ".opencode").mkdir()
    data = json.dumps({"sessionID": "ses_m", "error": {"name": "APIError", "data": {"statusCode": 429,
                                                                                   "responseBody": MINUTE}}})
    out = subprocess.run([NODE, "tools/tests/test_model_ladder_harness.mjs", str(tmp_path), data],
                         capture_output=True, text=True, cwd=ROOT)
    assert json.loads(out.stdout)["calls"] == []
