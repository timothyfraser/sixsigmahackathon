# README `demos/pypackage`

A tiny, tested **Python package** template: `demotool`, with two quality-control
functions. It is the Python twin of [`../rpackage/`](../rpackage/).

## What a package is, and why

A package is a folder of functions that anyone can **install** and **import**,
like `numpy`. Turning your analysis into one means the statistics live in one
place, have tests, and can be reused by your API, your dashboard, and a judge.

Files: `pyproject.toml` (name, version, dependencies: R's `DESCRIPTION`),
`src/demotool/qc.py` (functions + docstrings), `tests/test_qc.py` (tests).

## Install it (editable)

From this folder, ideally inside a virtual environment:

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[test]"     # -e = edits to src/ take effect without reinstalling
```

## Use it

```python
from demotool import control_limits, cpk

lim = control_limits([10, 12, 11, 13, 14])   # individuals (I-MR) chart limits
print(lim.center, lim.lower, lim.upper)      # 12.0  8.0106...  15.9893...
print(cpk([10, 12, 11, 13, 14], lsl=6, usl=20))   # 1.2649...
help(control_limits)                          # the docstring: inputs, outputs, assumptions
```

## Test it

```bash
pytest -q
```

## Add your own function

1. Write the method in one sentence (which chart or index, which formula).
2. Ask your AI agent to **write the test first**, with a small example you can
   check by hand, a degenerate case (e.g. constant data), and a bad-input case.
3. Then ask for the function, in `src/demotool/qc.py` (or a new module).
4. Export it in `src/demotool/__init__.py` and run `pytest` until it passes.

Rename the package by renaming `src/demotool/` and `name` in `pyproject.toml`.

## Use it from an app

Install the package into the app's environment, then import it like any library.
In a FastAPI app (see [`../fastapi/`](../fastapi/)):

```python
from demotool import control_limits

@app.post("/limits")
async def limits(values: list[float]):
    return control_limits(values)._asdict()
```

A Shiny for Python app does the same `from demotool import ...`. For deployment,
add the package to the app's `requirements.txt` (the `git+https` line below).

## Publish it on GitHub

Push this folder as its own public repo. Anyone can then run:

```bash
pip install "git+https://github.com/<your-user>/<your-repo>.git"
```

If the package sits in a subfolder: add `#subdirectory=path/to/folder` to the URL.
