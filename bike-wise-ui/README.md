# BikeSmart rider website

Smarter rides. Better-balanced cities.

Standalone React + Vite + React Leaflet prototype for the Big Red Crew. All application files, fixtures, dependencies and tests are isolated in this directory. No shared team dataset, simulation, architecture, R package or ledger is imported or changed.

## Preview locally

Requires Node.js 20.19+ or 22.12+ (developed with Node 24).

```sh
cd bike-wise-ui
npm ci
npm run dev
```

Open the localhost address printed by Vite (normally http://127.0.0.1:5173).

```sh
npm test
npm run build
npm run preview
# Browser verification, first install the test browser if needed:
npx playwright install chromium
npm run test:browser
```

Browser screenshots are written to ignored `test-results/`. `npm run build` produces ignored `dist/`. The project follows the professor's `demos/reactfront` React 18 / Vite / Vitest starter conventions, with relative asset paths (`base: './'`) suitable for static content under a Posit Connect content URL. Preview and development scripts serve locally; neither deploys anything.

## Review walkthrough

1. Home offers Rent and Return; the header switches mock networks.
2. Rent opens five curated pickup cards. Map numbers represent bikes available now. Select a card or marker; the selected state is synchronized. Marker popups show both bikes and docks, capacity, and arrival expectations.
3. Advance 5 minutes advances the simulated planning clock and cycles three mock inventory snapshots. Cards, popups and markers read the same snapshot; scheduled predictions also update. This is replay, not polling.
4. Choose a pickup, choose a preset destination, then find return docks. Pickup remains saved. Rental return numbers represent predicted free docks at each dock’s estimated arrival; Direct Return now still shows current free docks.
5. Return cards show No discount / 5% / 10% / 15% / 20% by current recommendation rank. Choose a return dock and inspect its demo discount in the summary. Change individual selections or restart. Direct Return skips pickup entirely.
6. Test Milwaukee and Tampa. Changing network clears incompatible station selections. All three networks use the same OpenStreetMap tile URL, attribution and Leaflet map controls.
7. All networks have eight selectable stations. Five teal markers are recommended; three muted markers are additional choices. Click an extra station to see its selected detail card, then continue through pickup or return as usual. The main list remains five recommendations. Replay preserves the selected station; if a forecast becomes unavailable, choose another station.
8. Inspect at phone width: controls and map precede the recommendation cards, with no functionality removed.

The banner is persistent. No GPS, address geocoding, accounts, reservations, payments, redeemable credits or backend requests exist. Return cards, popups and summaries show clearly labeled demo discounts only; nothing is issued or applied to a fare. Real-city basemaps use OpenStreetMap public tiles and attribution; those tiles need internet. Controls, fixtures and map markers work without tiles. Fonts request Google Fonts, with local sans-serif fallbacks.

## Mock data and assumptions

`src/data/mockStations.js` contains only UI fixtures. Station identities/coordinates in Jersey City, Milwaukee and Tampa are illustrative, not official station metadata. IDs are prefixed with the mock network and `demo`. Tampa uses a fictional bikeshare network placed on the real Tampa, Florida basemap. The station names, IDs, capacities and inventory are not an official Tampa operator’s data. Explicit per-station UI coordinates place examples in the downtown, Riverwalk, Water Street, Tampa Heights and Ybor City areas. No Lexi data or backup simulation was copied.

Each network has eight UI-only stations. Every station has capacity 15. Maintenance/unrentable bikes are not modeled, so bikes + free docks = capacity in every snapshot and prediction. Time-aware arrival inventory uses deterministic demo buckets, not a statistical model. Rankings are curated demonstration orders, varied by selected preset and scheduled-time bucket, not optimized routes. All walking/riding times and distances are fixed illustrative estimates; no road-routing engine is connected. Total walking adds access to pickup (rental only) and walking from the return dock. Total journey time adds walking and cycling, excluding waiting introduced by an adjusted return time; planned timestamps are displayed separately. Direct Return uses only cycling and walking from the return dock. Replay changes inventory and never runs in the background.

Community labels appear only at the two fixture stations that have few bikes in all three snapshots. These describe a mock restocking opportunity, not measured fleet improvement. A zero-bike option is explicitly labeled unavailable now; expectations never guarantee future inventory. Current fixtures do not have zero free docks, but future demo predictions can have zero bikes or zero docks and require reselection.

## Time-aware planning

Rent → choose a starting location → **Leave now** or **Leave later**. Later reveals a network-local date/time input. Try today at 5:00 PM or tomorrow at 8:30 AM. Cards show current inventory separately from **DEMO PREDICTION** values at each station’s arrival time; future maps emphasize predictions. Choose a pickup and destination to see each return dock’s expected arrival. **Adjust return time** can replace that estimate. Direct Return has independent **Return now / Return later** controls. Summaries show exact planned timestamps.

The network timezone is always explicit (Eastern for Jersey City/Tampa, Central for Milwaukee). Invalid/past dates block continuation. Repeated daylight-saving times require first/second occurrence; nonexistent spring-forward times are rejected. The simulated clock is frozen between replay advances; refresh to initialize it again. Predictions support up to 365 days in this demo. The R package is not yet connected.

## Adapter contract and later integration

React consumes `src/services/dataAdapter.js`; components do not import fixture arrays.

- `getNetworks()` → networks with `id`, `name`, `timeZone`, `[lat,lng] center`, optional `stationCoordinates`, and preset `places` (`name`, `lat`, `lng`).
- `getStations(networkId, snapshot=0)` → stations: `id`, `name`, `lat`, `lng`, `capacity`, `availableBikes`, `freeDocks`, `predictedBikes`, `predictedFreeDocks`, nullable `communityImpact`.
- `getPickupRecommendations(networkId, origin, planning, snapshot=0)` and `getReturnRecommendations(networkId, destination, planning, snapshot=0)` → station objects plus `rank`, `recommended`, `discountPercent`, `discountLabel`, `incentiveSource`, `label`, `walkingMinutes`, `walkingMeters`, `ridingMinutes`, `arrivalTime`, `status`, `explanation`.
- `getStationOptions(networkId, mode, point, planning, snapshot=0)` → all eight choices with the same recommendation schema. The app uses these options to resolve saved selections; the recommendation methods return only the top five.
- `getDemoReturnDiscount(rank)` → isolated demo policy: 0, 5, 10, 15, 20 percent for ranks 1–5, capped at 20 percent beyond rank 5. Missing, fractional or invalid ranks return 0.
- `getStationDetails(networkId, stationId, snapshot=0)` → station or null.
- `getTripSummary({origin,destination,pickup,returnStation,direct})` → selections, total walking/cycling/overall minutes and optional community message plus selected `discountPercent`, `discountLabel` and `incentiveSource`.

Objects use decimal-degree coordinates, integer counts, meters and minutes. Arrival timestamps are computed per station from the departure, walking and riding estimates, or an explicit expected return time. See [PREDICTION_CONTRACT.md](PREDICTION_CONTRACT.md) for the exact prediction interface, timezone rules, failure statuses and Ally’s connection points. Current methods are synchronous. Later, replace the adapter with an approved API client, add asynchronous loading/error/empty states to the workflow, validate responses, and define prediction horizons, timezone, reliability, capacity/maintenance semantics and official IDs with the R team. No API or URL is assumed today. Backend ranking, predictions and statistics remain the team's responsibility. Integrate Lexi's approved dataset through that contract; do not use the backup simulation.

## Tampa demo network and shared basemap

Jersey City, Milwaukee and Tampa all use the identical Leaflet `TileLayer`, OpenStreetMap tile service, map styling and “© OpenStreetMap contributors” attribution. Tampa is a real geographical backdrop for a simulated bikeshare scenario; it is not a fictional city. No custom map renderer or synthetic city artwork is used. Tiles need internet; cards and marker data remain available without a backend.

Tampa replaces the former third network in this UI. Only UI fixtures and documentation have changed. The team must coordinate the new network’s official dataset, station IDs/coordinates and optimization output separately; this prototype has not migrated or regenerated any shared dataset, statistical package, simulation, architecture, SPEC or ledger.

## Connecting Ally’s optimization results

All incentive logic lives in `src/services/dataAdapter.js`: `getDemoReturnDiscount(rank)` is the current fallback; `getStationOptions()` attaches `discountPercent`, `discountLabel` and `incentiveSource: 'demo-rank-policy'`. Cards and popups only render those fields; `getTripSummary()` carries them through without recalculating. Ranks are the current curated UI return order, including destination- and time-based changes. Discounts use `riderConvenienceRank`; `networkOptimizationRank` remains null until Ally supplies it. Picks outside the top five receive 20% in this fixture policy and never exceed the cap. These percentages have no link to a price, payment, entitlement, reservation or redemption service.

When Ally supplies results, map her official station IDs, ordered ranks and approved incentives into these fields at the adapter boundary. Replace the fallback with validated output there, including the agreed 20% cap and missing-output behavior. Keep optimization/statistics on the team backend, coordinate availability snapshots and prediction horizons with Lexi’s dataset and the R team, and add async loading/error handling. No new production endpoint is invented or configured here. The original community labels remain independent scenario metadata; the demo discount does not claim a quantified rebalancing benefit.

The product name is **BikeSmart** throughout the local UI, title, package metadata and documentation. The `bike-wise-ui/` folder path is intentionally retained to preserve the agreed ownership boundary and local preview commands.

## Pending team decisions / delivery

- The UI now combines community impact with the user-approved ranking-based demo discounts. The current rank does not prove inconvenience or system benefit; this is a visual placeholder pending Ally’s optimization output. No fare calculation or financial transaction is implemented.
- Task ownership is pending: H-04 currently owns `app/`, not `bike-wise-ui/`. User authorized local UI implementation without editing the ledger. No H-01–H-08 ownership or status has been changed, and no ledger task is claimed complete.
- SPEC still has placeholders; completion belongs to the team, not this isolated UI work.
- Static publishing: build this directory and publish `dist/` through the professor's `connect-publish` React static workflow once approved. Configure its application directory for this folder. Shared CI, publisher scripts, manifest generation, credentials and deployment are intentionally deferred until authorized. No deploy script that could publish accidentally is included.
- Production integration and deployment require coordinated review. No staging, commit, push, merge or deployment is part of local development.

References: repository `demos/reactfront`, [React Leaflet](https://react-leaflet.js.org/docs/start-introduction/), [Leaflet](https://leafletjs.com/), [Vite static deployment](https://vite.dev/guide/static-deploy.html), and [OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Icons: Lucide (ISC license). Fonts: DM Sans and Manrope via Google Fonts (SIL Open Font License).
