# BikeSmart Fleet Monitor — Standalone Maintenance Demo

A live, continuous backend monitoring tool for maintenance operators to visualize bike fleet movements, analyze system bottlenecks, and trace ride paths across Tampa.

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

## Key Features & Architecture

### 1. 🚀 Zero-Flicker Continuous Animation Engine
- The visual overlay renders via a **synchronized HTML5 Canvas layer** attached directly to Leaflet's `overlayPane`.
- In-memory 2D double-buffering updates frames at 60 FPS in **under 1 millisecond** with zero DOM destruction:
  - **No blinking or flashing** at any timestep.
  - Smooth rendering whether auto-playing or scrubbing the timeline.
  - Interactive clicks and hover detection on all 27 stations remain fully responsive.

### 2. 🛣️ Turn-by-Turn Tampa Street Network Routing
- We parsed Tampa's orthogonal downtown street grid across all 27 stations (East-West streets: *Washington, Jackson, Kennedy, Madison, Twiggs, Zack, Polk*; North-South avenues: *Ashley, Tampa, Franklin, Florida, Morgan, Pierce*):
  - Every station pair is pre-routed along the street network:
    - **Same Street/Avenue:** Rides travel directly straight down that road.
    - **Different Streets:** Rides follow the street, turn at the real corner intersection station, and continue along the connecting avenue.
  - As time elapses, the extending line **physically turns the corner at the intersection and tracks the real street path**!

### 3. 🏢 Station Circles Color-Coded by Zoning Type
- All station circles have a uniform radius (`radius = 10px`) with a clean white rim:
  - 🔵 **Blue (`#2563eb`):** Office Station
  - 🟢 **Green (`#10b981`):** Residential Station
  - 🟠 **Amber (`#f59e0b`):** Retail Station
- Real-time station inventory, stockout outage minutes, full-dock outage minutes, and 24-hour time-series are inspected by clicking any station or opening the **🔍 Station Inspector** tab.

### 4. 🔍 Single Bike Journey & Fleet Path Modes
- **All 405 Bikes:** Visualizes the full citywide movement with extending cyan lines (`#00b4d8`) and dark navy bike heads (`#023e8a`).
- **Single Bike Mode:**
  - Select any bike ID to inspect its specific journey throughout the day.
  - Shows its active ride in bright glowing cyan (`#00f0ff`, width 4px) and past routes at `0.75` opacity.
  - When the bike is docked, a glowing cyan halo highlights the exact station where it is waiting.
  - Status card displays real-time state: *Riding (Station A ➔ Station B)* or *Docked at (Station)* with completed trip count.

### 5. 📅 Seamless Day Navigation
- Switch days using the dropdown or ◀ Prev / Next ▶ buttons.
- High-efficiency columnar streaming ensures all ~8,500 trips populate instantly without lag or dropped frames.
- **Display Path History** renders past completed paths today at **0.50 opacity** (`rgba(0, 119, 182, 0.50)`).
