# BikeSmart rider website

React + Vite + React Leaflet guided rider planner for Jersey City, Milwaukee
and Tampa. Start by choosing pickup or return, then select a location and a dock.
All steps use the same R optimizer results and the same mounted city map.
The five highest-ranked eligible docks appear in the default list and occupancy
chart, with green map markers. Other docks appear only as yellow map markers;
any eligible one can be selected and confirmed. Excluded docks keep their
reasons and cannot be confirmed. The planner sits above a map-left, list-right
layout, and the final page shows the user’s itinerary beside the map.

## Run locally

```sh
cd bike-wise-ui
npm ci
npm run dev
```

Open the local URL printed by Vite (normally http://127.0.0.1:5173).

```sh
npm test
npm run build
# Full suite: supply MAINTENANCE_TEST_PASSWORD as described below.
npm run test:browser
```

Browser checks require Playwright Chromium (`npx playwright install chromium`).
Screenshots are written to ignored `test-results/`; build output goes to `dist/`.

## Demo walkthrough

1. Choose a city, then **Rent a Bike** or **Return a Bike**.
2. Select one of ten sourced user locations and click **Find pickup docks**
   or **Find return docks**. Recommendations appear only after this step.
3. Start with the five nearest eligible docks in the list, or select another
   eligible yellow marker from the map. Other eligible docks stay out of the
   recommendation list; their details appear in the planner. Selecting a card,
   map marker, or chart bar updates the same selected dock. Confirm with **Choose this
   pickup station** or **Choose this return dock**.
4. Rentals continue to a destination-area selector, then five eligible return
   docks, then a summary containing the saved pickup and return choices.
   Direct returns go straight from the return choice to a summary.
5. Use Back, Change location, Change pickup, or Change return dock to revise
   the plan. Plan another ride returns to the initial function selection.
6. The Excluded tab shows removed docks with their reasons. They cannot be
   confirmed. Eligible options are sorted by the original R rank before
   taking the first five; incentive percentages do not change their order.
7. The bottom chart shows the same five recommended eligible docks (or excluded
   docks when that tab is open), with 25% and 50% threshold lines. The map keeps
   all docks visible: green recommendations, yellow other docks, and dashed
   outlines for excluded docks. Markers also support Enter and Space.
8. Review the itinerary beside the map on the final page. Pickup, starting
   location, return area and chosen return dock match your saved selections.
   Use its edit buttons to revise either dock.

Dock cards emphasize station name and walk/ride time; projected availability
is secondary text. The “Your next ride” planner stays above the map and list.

Changing city restarts the flow and clears incompatible selections. Selecting
another function starts at location selection. Navigation within a city keeps
the same map mounted; choosing a location updates its bounds.

## Data and assumptions

`src/services/optimizer.js` reads the exported R results in
`src/data/optimizer.json`. The source files are
`data/optimizer/demo_recommendations.csv`, `demo_exclusions.csv`,
`user_locations.csv`, and city station/zoning CSVs. The export contains 27 docks per city; the list shows up to five recommended eligible choices, with
30 saved user locations, and 1,620 recorded results (60 input combinations).
The old eight-station fixture results are not used in the guided journey;
legacy service utilities remain isolated from the optimizer screen.

Each dock's arrival uses saved walking/cycling road distance at 3/10 mph.
Return discounts are copied from R: occupancy below 25% earns 20%, 25% to
below 50% earns 10%, and at least 50% earns zero. Occupancy is measured before
the rider's bike is added. Discounts never change distance rank.

The reference instant is October 15, 2026 at 23:55 EDT (22:55 CDT in Milwaukee),
shown in the selected city's timezone. Inventory is simulated, and projections
are historical model expectations. The export cannot predict arbitrary new
planning times. Pickup and return recommendations are separate saved legs from
the same reference instant. Return distance is from the selected area, not from
the pickup dock; the summary does not claim a combined route or journey arrival. No bikes/docks are reserved and no credits are issued.

Refresh after rerunning the R optimizer demo, from the repository root:

```sh
Rscript data/optimizer/run_demo.R
python3 tools/export_optimizer_ui.py
npm --prefix bike-wise-ui run build
```

The export validates record counts/uniqueness without refitting the R model.
See `data/optimizer/README.md` for route sources, assumptions, and model details.
OpenStreetMap tiles need internet; controls, dock markers and results work without
tiles. Basemap © OpenStreetMap contributors. Icons: Lucide. Fonts: DM Sans and
Manrope with system fallbacks. No GPS, accounts, payments, or deployment required.

## Completed BikeSmart package integration

The rider export now calls the completed `bikesmart/` package's
`compute_dock_rates()`, `predict_dock()` and `optimize_docks()` functions.
The existing guided rider journey, green top-five recommendations, selectable
yellow alternatives, exclusions, incentives and itinerary use those results.
The exported metadata identifies the package and reference instant.

Refresh rider and maintenance reports from the repository root:

```sh
Rscript bikesmart/tests/test_all.R
Rscript tools/export_bikesmart_ui.R
```

R needs `dplyr` and `jsonlite`. The exporter runs one city per child process to
limit memory use. It uses the full saved movement history up to the recorded
reference, excludes the reference snapshot from the projection fit, and calls
package functions without duplicating the statistical formulas in the UI.
`python3 tools/export_optimizer_ui.py` now delegates to the R package exporter
with `--rider-only`; it no longer republishes the older root-script CSV outputs.

## Maintenance workspace

The header's **maintenance login here** button opens a separate sign-in screen.
Use the maintenance credentials supplied for this demo. Validation happens in
`server/api.mjs`, not in browser JavaScript. A successful login creates an
HttpOnly, SameSite=Strict session cookie; logout invalidates the server session.
Reports are served only through authenticated API routes. The raw maintenance
JSON and server source are denied by the Vite file server and excluded from the
frontend build.

The workspace supports all three cities:

- **Fleet monitor (landing view):** recorded daily fleet playback from `demo/fleet_viz`, with date/time controls, speed, all-bike animation, single-bike history, empty/full highlights and a station inventory inspector. Cyan paths and navy bike markers render above the map; Play moves bikes smoothly between snapshots at the selected speed. Routes follow directed bicycle-accessible OpenStreetMap streets using the same graph filters and dock snapping as the distance matrices. They are inferred from dock observations, not GPS.
- **Service log:** record completed maintenance or import a CSV; saved service events update accumulated ride hours, the due queue and dispatch rankings through BikeSmart.
- **Dispatch priorities:** package-ranked station visits by due bikes and overdue
  hours, a station map, and links to each station's service queue.
- **Service due:** package service statuses with bike search, station filters,
  ride hours, due timestamps and current recorded location.
- **In-transit alerts:** only rows whose package `flagged` value is true by
  default; optionally inspect all open trips, including those below threshold.
- **Quality chart:** package daily counts, P-chart center and three-sigma limits,
  out-of-control signals, and the underlying values for every day.
- **Fleet reliability:** editable hypothetical defect shares and projected bike
  count. The server calls the R package for usable share, inventory scaling and
  the ordered defect breakdown. Independence of defects is an assumption.

The saved maintenance scenarios use a **60 ride-hour service interval**,
**90-minute trip alert**, and reproducible staggered starting hours (seed 42).
The Jersey City report includes the team's 405 simulated service records and supplied starting hours. Milwaukee and Tampa retain seeded starting hours without recorded service logs. All cities use the updated package default: assumed servicing every 70 ride hours, with bikes due at 60 hours in the current cycle. The P-chart counts daily service-cycle
crossings; it is distinct from the current overdue queue. All movement records
are simulated. Viewing reports does not mark bikes serviced or dispatch a van.

`npm run dev` and `npm run preview` include the maintenance API through the Vite
plugin. To run a built site with the API:

```sh
npm run build
npm start
```

This serves the built UI and API together on local port 4173 (override `PORT`
if needed). Login and R reliability calculations require this server; a purely
static upload of `dist/` does not run them. The R package and server report file
must remain available alongside the built frontend.

Optional server configuration is `MAINTENANCE_EMAIL` and
`MAINTENANCE_PASSWORD_SHA256` (a SHA-256 digest). Keep overrides in the server
environment. When serving HTTPS through a proxy, set
`MAINTENANCE_COOKIE_SECURE=true`. The checked-in demo verifier is a digest; the plaintext login
password is not shipped in frontend files.

For the full browser suite, supply the known demo password only in the test
process environment:

```sh
MAINTENANCE_TEST_PASSWORD='<demo password>' npm run test:browser
```

The checks cover invalid login, authenticated report access, session/logout,
city-specific package output, the reliability known answer, direct file access,
mobile layout, and preservation of an in-progress rider selection.

### Service records

Select **Service log** after maintenance login. Manual timestamps use the selected
city's clock. CSVs require `BIKEID,service_time`; optional columns are `note,city`.
Use ISO timestamps with seconds and a timezone offset, such as
`2026-10-16T03:55:00Z`. Each import accepts up to 500 rows / 128 KB. Unknown bike
IDs, city mismatches and invalid timestamps are rejected atomically. A repeated
bike/time event is stored once. Jersey City includes the team-supplied simulated service history from `data/service_log_jersey_city.csv`; cities without supplied logs start empty.

The server combines the supplied baseline records with operator entries. It persists entries in the gitignored `server/data/service-log.json`.
Set `MAINTENANCE_SERVICE_LOG_FILE` to an absolute persistent path for deployment.
Keep that file across server restarts. Events after the report snapshot are saved
but do not change historical status. Fleet replay and the historical quality
chart retain their original observations. For earlier events the server calls
package `service_status(..., service_log=...)` and `rank_stations`; a service
exactly at the snapshot has zero elapsed ride hours, handled by the adapter
because the package cannot process an entirely filtered history.

Run `npm run fleet:refresh` to regenerate the protected, compressed daily replay
files. The exporter reuses the demo's data-loading and trip helpers, replaces corner routes with complete street paths, and validates every snapshot in all three cities. Street geometry is built by `tools/export_fleet_roads.py` from cached `data/sources/*_roads.json` extracts; it reuses `data/prepare_networks.py` so bicycle access, one-way rules, connected components, snapping, and edge weights match the distance matrices. All 702 directed pairs per city match the committed matrix distances within floating point precision. Short dock-to-street connectors remain part of that model. The generated network bundles are private and need no routing network requests during playback. `npm run data:refresh` regenerates
rider and maintenance reports plus the fleet replay. R, the package source,
source RDS data and the private generated report files must be present on the
server for service-log updates.

Mutation tests must use a disposable journal. Start a separate server with
`MAINTENANCE_SERVICE_LOG_FILE` pointing to a fresh temporary path, then run
`service-log.spec.js` with `SERVICE_LOG_TEST_ISOLATED=true` and
`BIKESMART_TEST_BASE_URL` set to that server. The regular browser suite skips
journal mutations to preserve operator records.

The fleet monitor has explicit **Jersey City / Tampa / Milwaukee** city buttons.
These synchronize with the header selector and maintenance reports. Bike movement
uses cumulative street length, preserving smooth speed around every street bend.

Latest maintenance inputs were synchronized from `origin/main` at `29e5fce`:
`service_status` now defaults to `assume_service_h=70`; actual service events take
precedence. The baseline Jersey City log is visibly labeled as team-supplied
simulated data. Its source file and `data/start_hours_jersey_city2.csv` remain
unchanged. The new upstream assumed-service test was converted to equivalent
base-R assertions to run with the package's existing standalone test runner.
The historical P-chart continues to use package `daily_service_counts` (60-hour
cycle crossings), independently of the current due queue and assumed 70-hour
servicing; it does not invent historical completion events.
