---
name: stats-first-steering
description: How to steer a coding agent so the statistical method stays correct and central - SPC charts, process capability, reliability models - by verifying numbers against known cases before any styling or feature work. Load at the start of any hackathon project and before accepting agent-written analysis code.
---

# Stats-first steering

**The statistics are the graded core. The app is the delivery vehicle.**

An agent will happily produce a beautiful dashboard whose control limits are
wrong. Nothing in the code will look broken. This skill exists to stop that.

## The order of work

1. **State the method in words first**, before any code exists. "We compute an
   X-bar and R chart over subgroups of size 5, with limits from the pooled
   within-subgroup range." If nobody on the team can write that sentence, no
   amount of code will fix it.
2. **Implement the statistic alone**, as a plain function with plain inputs. No
   web framework, no plotting, no styling.
3. **Verify it against a known case** (see below) before anything else happens.
4. **Only then** wrap it in an API, a package, or a front end.
5. **Style last.** Always last.

Teams that style first lose the hours they needed for step 3.

## Verify against a known case — non-negotiable

Before you accept any agent-written analysis, check it against something whose
answer you already know:

- **A textbook example.** Work a small example from the
  [SYSEN 5300 textbook](https://timothyfraser.com/sigma/) by hand or in a
  console, and assert your function reproduces it.
- **A degenerate case.** Constant data → zero variation, capability undefined or
  infinite, no out-of-control points. If your code returns a number here, it is
  wrong.
- **A planted signal.** Inject a shift you designed (e.g. +2 sigma after point
  30) and confirm the chart flags it where you put it.
- **A cross-check in the other language.** If the agent wrote it in Python,
  spot-check one number in R (or vice versa). Disagreement is information.

Write these as actual tests. Two or three assertions is enough and takes five
minutes; discovering a wrong estimator at hour 20 does not.

## Method-specific traps to name explicitly in your prompt

**Statistical process control**
- Control limits are *not* specification limits and are *not* +/- 3 standard
  deviations of the raw pooled data. State which chart (X-bar/R, X-bar/S, I-MR,
  p, np, c, u) and why, based on your data type and subgroup structure.
- Limits should be estimated from an in-control baseline period, not from the
  whole series including the excursion you are trying to detect.
- Say which run rules you apply. "Western Electric rules 1-4" is a specification;
  "flag anomalies" is not.

**Process capability**
- Cp vs Cpk is a centering question — an agent asked for "capability" will often
  give you one and label it the other.
- Capability is meaningless on an out-of-control process. Establish control
  first; say so in your tool's output.
- Both spec limits must come from the problem, not from the data.

**Reliability**
- Name the distribution and justify it (exponential = constant hazard; Weibull =
  shape parameter tells you infant mortality vs wear-out).
- MTTF is not "average of observed failures" when data are censored. State
  whether your data are censored and handle it.
- Series vs parallel system structure changes the formula completely. Draw the
  block diagram before writing the code.

## Prompts that work

Weak: *"Build me a dashboard for monitoring GPU failures."*

Strong: *"Write one Python function `xbar_r_limits(df, subgroup_col, value_col)`
returning center line and control limits for an X-bar and R chart using the
standard A2/D3/D4 constants for subgroup size n. Do not plot anything. Then write
three tests: a constant-data case, a textbook case with these values and this
expected answer, and a planted-shift case."*

Then, separately: *"Now expose that function over a FastAPI endpoint."*

Small, verifiable, one thing at a time. The agent is fast; your job is to keep it
pointed at the right thing.

## Before you demo

- Every number on screen traces to a function you can open.
- Someone on the team can answer "why is that limit there?" out loud.
- The tool behaves sensibly on your degenerate test dataset, live, in front of a
  judge.
