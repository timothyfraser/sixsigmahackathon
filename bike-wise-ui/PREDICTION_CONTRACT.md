# Ally → BikeSmart prediction and recommendation contract

This is the frontend's proposed integration boundary, not a claim that an R-serving API exists. All predictions are currently mock. Coordinate the final transport, official station IDs, capacity/maintenance rules, allowable horizon and ranking semantics with Ally and the R team before integration. No team dataset or R function has been changed.

## Single-station prediction

Defined in `src/services/dataAdapter.js`:

```js
getStationAvailabilityPrediction(networkId, stationId, targetTime, mode,
  { snapshot = 0, referenceTime = new Date().toISOString() } = {})
```

Required arguments:

- `networkId`: `jersey`, `milwaukee`, or `tampa` (UI IDs until official mappings are approved).
- `stationId`: stable station ID, currently `<networkId>-demo-1` through `-8`.
- `targetTime`: ISO 8601 timestamp with `Z` or an explicit numeric UTC offset. A timezone-free local string is rejected. The response normalizes valid timestamps to UTC ISO format.
- `mode`: `rent` predicts available bikes; `return` predicts free docks.

Optional fifth argument is demo context. `snapshot` selects current mock inventory (0–2). `referenceTime` is the explicit simulated planning clock against which past/future validity is checked. Omit it for current actual-clock validation outside the UI. This context must not become an implicit production forecast parameter.

Response schema (nullable fields remain null on failures):

```js
{
  networkId: 'jersey',
  stationId: 'jersey-demo-2',
  requestedPredictionTimestamp: '2026-10-16T21:06:00.000Z',
  currentAvailableBikes: 4,
  currentFreeDocks: 11,
  capacity: 15,
  predictedAvailableBikes: 9,
  predictedFreeDocks: 6,
  predictionSource: 'mock',       // future approved client: 'backend'
  predictionLabel: 'DEMO PREDICTION',
  status: 'ok',                   // 'ok' | 'error' | 'unsupported'
  availabilityStatus: 'Bikes expected',
  error: null                    // see below
}
```

The numeric example above uses snapshot 0 and a reference of `2026-10-16T16:00:00.000Z`. Current inventory and forecasts are separate. No maintenance inventory is modeled, so each pair sums to capacity. At the exact reference instant, the mock prediction equals current snapshot inventory. Successful predicted counts are integers in `[0, capacity]`. Status text distinguishes zero and limited availability. Errors are `unknown_station`, `invalid_mode`, `invalid_time`, `past_time`, or `unsupported_horizon`; errors return null predictions, never a fabricated zero. The mock horizon is 365 days from the reference clock.

**Connection point:** replace the deterministic fixture block inside `getStationAvailabilityPrediction()` with Ally's approved prediction output. Validate timestamps, IDs, capacity and response status there. Preserve null/unavailable results on failure. No endpoint is currently configured. If this becomes asynchronous, add request cancellation/stale-response protection and loading/error state in the workflow before replacing the synchronous calls. Current code is synchronous because all data is local.

## Time semantics

`src/services/networkTime.js` converts wall-clock form inputs to actual instants using each network's explicit IANA timezone: Jersey City and Tampa `America/New_York`, Milwaukee `America/Chicago`. It never parses datetime-local inputs in the browser timezone. Spring-forward nonexistent local times are rejected; fall-back repeated times require an explicit first/second choice and display EDT/EST or CDT/CST. Inputs with incomplete/invalid dates, past instants, or dates beyond the demo horizon block continuation.

The simulated planning clock starts at the real page-load instant, rounded down to a minute, and advances only through the replay button. There is no background timer/polling. Snapshot inventory repeats every three advances while the clock continues forward. This is labeled simulated replay and does not represent a measured time series. A refresh starts a new planning clock.

- Pickup target: chosen departure instant + that station's illustrative walking minutes.
- Rental return target (default): **saved pickup arrival instant** + that return station's illustrative riding minutes. Each dock can have a different prediction timestamp. Departure is never reused directly as return time.
- Direct Return now: simulated clock instant. Direct Return later: the chosen expected return instant, for each candidate dock. Do not add a second ride duration to an explicit arrival time.
- Adjusted rental return: the chosen expected return instant replaces the proposed arrival for all candidates. It must be after the pickup instant. This is a rider-provided estimate, not validated road routing. Actual travel-time feasibility still needs the team's routing/optimization contract.
- Walking, riding and total travel-duration cards remain illustrative travel durations and exclude waiting introduced by a manually adjusted return. Exact planned departure/pickup/return timestamps are displayed separately in the summary.

Leave now and Direct Return now map markers show current inventory; cards still request forecasts at their relevant arrival times. Leave later, Direct Return later and the rental return step show prediction counts, with a matching legend. All marker values and card forecasts come from the same adapter objects. Invalid times produce unavailable (`—`) prediction markers and block selection confirmation. Pickup confirmation also checks its arrival forecast in Leave now mode. An explicitly selected station remains selected across time/rank changes and may move to the extra-station detail card; a zero forecast requires choosing another station. No availability is guaranteed.

## Recommendation envelope / rank semantics

```js
getStationOptions(networkId, mode, point, planning, snapshot = 0)
```

`planning` fields:

```js
{
  referenceTime,       // ISO simulated clock
  departureTime,       // ISO selected departure or direct-return schedule
  rideStartTime,       // ISO saved pickup arrival; rental returns only
  returnTargetTime,    // ISO explicit expected return, or null for per-dock rides
  valid: true,        // false prevents forecast requests using stale form values
  scheduled: true,    // enables time-varying demonstration recommendation order
  usePredictions: true // which inventory the map emphasizes
}
```

Each option contains the current station fields plus:

- `targetTime` / `arrivalTime`: ISO forecast target; `arrivalLabel`: network-local display with date/time/zone.
- `prediction`: the full result above; `predictionValid`: whether it succeeded.
- `predictedBikes`, `predictedFreeDocks`: display aliases for that result; nullable on error.
- `rank`: current displayed demo rider-convenience rank; `riderConvenienceRank`: explicit alias.
- `networkOptimizationRank: null`: deliberately unknown until Ally supplies it.
- `rankingSource: 'curated-demo'`, `recommended`: top-five membership.
- `walkingMinutes`, `ridingMinutes`, `label`, `status`, `explanation`, community metadata and demo incentive fields.

The mock order rotates a curated fixture list by the selected 15-minute bucket to exercise reordering and top-five membership. It is **not** an optimization calculation, reliability estimate or statistical model. Ally's ordered results should replace this block in `getStationOptions()`, including separate rider-convenience and network-optimization ranks. Keep stable station IDs so selections survive reordering. Coordinate empty-result/station-removal behavior when implementing the API client.

The unchanged `getDemoReturnDiscount(riderConvenienceRank)` rule is 0%, 5%, 10%, 15%, 20%, capped at 20% beyond fifth. Do not substitute network-optimization rank for rider-convenience rank. Cards, popups and summaries render adapter fields only. Discounts remain simulated; no payment/credit is issued.

`getPickupRecommendations()` / `getReturnRecommendations()` accept the same planning context and filter the options to five recommendations. `getTripSummary()` carries `pickupTime`, `returnTime` and the selected incentive fields through without predicting again.
