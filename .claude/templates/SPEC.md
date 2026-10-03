# SPEC: <tool name>

What this tool IS. Where the code and this file disagree, the code is the bug: change this file first,
then the code. Keep it to one page. Replace every `<...>`.

## 1. User
<One named kind of person, e.g. "the shift lead on a bottling line". Not "everyone".>

## 2. Use case
<The one decision this tool helps them make, and when they make it. One or two sentences.>
Problem or brief this answers: <one line, or a link>

## 3. Inputs (keep these few)
Only things this user can actually measure or already knows.

| Input | Type / units | Where the user gets it |
|---|---|---|
| <e.g. measurements.csv: one row per part> | <numeric, mm> | <their gauge log> |

## 4. The statistics, and why
Say the method in words before any code exists.
- **Method:** <e.g. X-bar and R chart, subgroups of 5, limits from the average range>
- **Why this method fits the use case:** <one sentence>
- **Assumptions and how we check them:** <e.g. normality: histogram + Shapiro-Wilk in the demo>
- **Known-answer check:** <a textbook example or planted shift the function must reproduce>

## 5. Outputs
<What the user sees: a number, a chart, a pass/fail, with units, and how to read it.>

## 6. Delivery
<R package | Python library | REST API (FastAPI / plumber) | dashboard (React / Shiny)>, deployed to <where>.

## 7. Test datasets
<2-3 small CSVs and what each one demonstrates, e.g. in control / planted shift / edge case.>

## 8. Out of scope
<What we will NOT build in this round, so nobody (human or agent) builds it by accident.>
