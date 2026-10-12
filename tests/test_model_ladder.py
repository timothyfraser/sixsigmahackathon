"""Offline tests for the model ladder plugin (.opencode/plugins/model-ladder.*). Needs Node 18+."""
import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
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


def test_end_of_ladder_message():
    assert js("L.nextModel(L.LADDER[L.LADDER.length-1], [])") is None
    msg = js("L.END_OF_LADDER")
    assert "used up for today" in msg and "midnight Pacific" in msg
    assert "teammate" in msg and "Zen" in msg


def test_exhausted_resets_on_new_pacific_day():
    assert js('L.exhaustedToday({day:"2000-01-01",exhausted:["x"]})') == []
    assert js('L.exhaustedToday({day:L.pacificDay(),exhausted:["x"]})') == ["x"]


def test_plugin_entry_point_switches_and_resumes(tmp_path):
    (tmp_path / ".opencode").mkdir()
    data = json.dumps({"sessionID": "ses_test", "error": {"name": "APIError", "data": {
        "message": "429 Too Many Requests", "statusCode": 429, "isRetryable": False, "responseBody": DAILY}}})
    out = subprocess.run([NODE, "tests/test_model_ladder_harness.mjs", str(tmp_path), data],
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
    assert "google/gemini-3.1-flash-lite" in state["exhausted"]


def test_per_minute_error_does_not_switch(tmp_path):
    (tmp_path / ".opencode").mkdir()
    data = json.dumps({"sessionID": "ses_m", "error": {"name": "APIError", "data": {"statusCode": 429,
                                                                                   "responseBody": MINUTE}}})
    out = subprocess.run([NODE, "tests/test_model_ladder_harness.mjs", str(tmp_path), data],
                         capture_output=True, text=True, cwd=ROOT)
    assert json.loads(out.stdout)["calls"] == []
