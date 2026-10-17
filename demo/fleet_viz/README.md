# BikeSmart Fleet Monitor — Multi-City Maintenance Demo

A live, continuous backend monitoring tool for maintenance operators to visualize bike fleet movements, analyze system bottlenecks, and trace ride paths across **Tampa (FL)**, **Jersey City (NJ)**, and **Milwaukee (WI)**.

Inspired by the **Hero's Path** feature in *The Legend of Zelda: Breath of the Wild*, this dashboard animates the continuous journeys of all 405 bikes across 27 docking stations at **5-minute resolution** over any selected day in the 30-day history.

---

## Quick Start

From the repository root in an R terminal or RStudio:

```r
shiny::runApp("demo/fleet_viz")
```

Or run directly using Rscript:

```bash
Rscript demo/fleet_viz/run.R
```

---

## Key Features & Multi-City Architecture

### 1. 🏙️ Instant Multi-City Cut (No FlyTo Animation Delay)
- Switch instantly between all three simulated cities using the sidebar dropdown:
  - **🌴 Tampa, FL:** 27 stations, 405 bikes, orthogonal street grid.
  - **🏙️ Jersey City, NJ:** 27 stations, 405 bikes, downtown Hudson waterfront grid.
  - **🍺 Milwaukee, WI:** 27 stations, 405 bikes, downtown Milwaukee grid (Central Time).
- **Instant Cut:** Replaced slow continental `flyTo` animation with instant `setView(..., animate = false)`. The map snaps directly to the target city with zero lag.
- **In-Memory Caching:** City bundles are loaded and cached in memory, making toggling between cities sub-second.

### 2. 🛣️ Real Street Network Corner-Turn Routing (All 3 Cities)
- **Tampa:** Uses the orthogonal intersection grid where turns occur at real intersection stations.
- **Jersey City & Milwaukee:** Uses shortest-path intermediate corner routing calculated from the verified road network distance matrices (`data/distances/jersey_city.csv` and `data/distances/milwaukee.csv`).
- **Result:** Instead of diagonal straight lines through buildings or parks, trips follow actual street corridors and turn at real station corners along the street grid.

### 3. 🏢 Urban Zoning Display Across All Cities
- Stations are color-coded by urban zoning with uniform `10px` circles and white borders:
  - 🔵 **Blue (`#2563eb`):** Office Station
  - 🟢 **Green (`#10b981`):** Residential Station
  - 🟠 **Amber (`#f59e0b`):** Retail Station
- Stations are formatted as clean typed objects during WebSocket transfer, ensuring all 27 station circles and zone colors render immediately in every city.

### 4. 🚨 100% Hit Area KPI Cards (Empty / Full Outages)
- The **Stations Empty (0)** and **Stations Full (30)** KPI cards are direct clickable buttons where 100% of the box area is interactive.
- Displays `(Click to show)` by default, changing to `● Showing` when active.
- Toggling highlights matching stations with bold alert rings and labels on the map:
  - 🔴 **Empty Stations:** Glowing red alert ring with an `EMPTY (0)` tag.
  - 🟠 **Full Stations:** Glowing amber alert ring with a `FULL (30)` tag.

### 5. ⚡ Smooth 60-FPS Micro-Interpolation (No Teleporting)
- Eliminates discrete 5-minute teleport jumps.
- A client-side `requestAnimationFrame` interpolation engine smoothly glides bike markers and extending paths down streets and around corners at 60 FPS between slider steps.
- Quick timeline scrubbing across hours snaps instantaneously.

### 6. 🚲 Streamlined Fleet vs. Single Bike Journey Views
- **All 405 Bikes View:** Displays clean, real-time active moving bikes with extending cyan trails (`#00b4d8`) and dark navy bike heads (`#023e8a`).
- **Single Bike Journey View:**
  - Select any bike ID to inspect its specific journey throughout the day.
  - Displays that bike's path history at `0.75` opacity with a dedicated toggle.
  - Highlights its active ride in bright glowing cyan (`#00f0ff`, 4px).
  - Displays a glowing cyan halo around the station when the bike is currently docked.
  - Real-time status card details departure/destination and completed trip count.
