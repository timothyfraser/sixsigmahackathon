# Rush Hour Autopilot (app)

An R Shiny dashboard for the municipal bikeshare dispatcher's weekday morning rush
(07:00-10:00 New York). All data are simulated. H-07 will finish this page.

Every statistic comes from `qc.R` (tested in `../tests/`); `prep.R` shapes data;
`plots.R` draws; `app.R` is screen and wiring only.

## Run

From the repo root: `Rscript app/testme.R`, then open http://127.0.0.1:5763/

Other scripts: `Rscript app/manifestme.R` (writes `manifest.json`), `Rscript app/deployme.R`
(needs the `CONNECT_SERVER` and `CONNECT_API_KEY` environment variables).

## Input

One scenario CSV (long form, with a `table` column: stations, status, attempts, tasks; see
`../docs/methods.md` section 7). Upload it in the sidebar. Without an upload the app uses
`../data/baseline.csv`, then `../tests/fixtures/edge_small.csv`; if neither exists it shows an
upload panel.

## Tabs

- Overview: station map by state at the chosen date and minute, KPIs, ranking, data issues
- Stations: inventory trend, unusable minutes, heatmap, Pareto
- Quality: p charts (rent, return), I-MR chart, excluded windows
- Rebalancing: greedy plan (heuristic, not an optimum)
