"""Check the model ladder in .opencode/plugins/model-ladder.lib.mjs.

Offline:  python tools/check_model_ladder.py           (no Gemma, flash-lite before flash, no repeats)
Live:     python tools/check_model_ladder.py --live    (asks Google which ladder models answer on YOUR key;
          reads GEMINI_API_KEY from the environment and sends it only in the x-goog-api-key header)
"""
import json, os, re, sys, urllib.request, urllib.error
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / ".opencode/plugins/model-ladder.lib.mjs"


def ladder():
    block = re.search(r"export const LADDER = \[(.*?)\];", LIB.read_text(encoding="utf8"), re.S).group(1)
    return re.findall(r'"(google/[^"]+)"', block)


def main():
    rungs, bad = ladder(), []
    if any("gemma" in m for m in rungs): bad.append("FAIL: a Gemma model is on the ladder")
    lite = [i for i, m in enumerate(rungs) if "flash-lite" in m]
    if lite and max(lite) > min([i for i, m in enumerate(rungs) if "flash-lite" not in m] or [99]):
        bad.append("FAIL: a flash rung comes before a flash-lite rung")
    if len(set(rungs)) != len(rungs): bad.append("FAIL: a model appears twice")
    for i, m in enumerate(rungs, 1): print(f"{i}. {m}")
    if "--live" in sys.argv:
        key = os.environ.get("GEMINI_API_KEY") or sys.exit("FAIL: set GEMINI_API_KEY first")
        for m in rungs:
            req = urllib.request.Request(
                f"https://generativelanguage.googleapis.com/v1beta/models/{m.split('/', 1)[1]}:generateContent",
                data=json.dumps({"contents": [{"parts": [{"text": "reply with the word ok"}]}]}).encode(),
                headers={"x-goog-api-key": key, "Content-Type": "application/json"})
            try:
                urllib.request.urlopen(req, timeout=60); print(f"  OK   {m}")
            except urllib.error.HTTPError as e:
                print(f"  {e.code}  {m}  {json.loads(e.read() or b'{}').get('error', {}).get('message', '')[:100]}")
    print("\n".join(bad) or "PASS: ladder is well formed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
