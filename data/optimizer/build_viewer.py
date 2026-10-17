"""Build an offline-capable HTML viewer from the saved optimizer CSV results."""
import csv
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "viewer"
OUT.mkdir(exist_ok=True)
VENDOR = OUT / "vendor"
VENDOR.mkdir(exist_ok=True)
leaflet = ROOT.parents[1] / "bike-wise-ui/node_modules/leaflet"
for source, target in [("dist/leaflet.js", "leaflet.js"),
                       ("dist/leaflet.css", "leaflet.css"), ("LICENSE", "LEAFLET-LICENSE")]:
    dest = VENDOR / target
    if not dest.exists():
        if not (leaflet / source).exists():
            raise SystemExit("Leaflet assets missing: run npm ci inside bike-wise-ui first")
        shutil.copyfile(leaflet / source, dest)

def read(name):
    with (ROOT / name).open() as f:
        return list(csv.DictReader(f))

numeric = {"rank", "distance_miles", "live_bikes", "capacity", "travel_minutes",
           "projected_spaces", "projected_bikes", "projected_occupancy", "discount_percent"}
records = []
for filename, eligible in [("demo_recommendations.csv", True), ("demo_exclusions.csv", False)]:
    for row in read(filename):
        for key in numeric & row.keys():
            row[key] = None if row[key] in {"", "NA"} else float(row[key])
        row["eligible"] = eligible
        records.append(row)
locations = read("user_locations.csv")
for row in locations:
    row["lat"], row["lon"] = float(row["lat"]), float(row["lon"])
stations = []
roads = {}
for city in ["jersey_city", "milwaukee", "tampa"]:
    with (ROOT.parent / f"zoning/{city}.csv").open() as f:
        zones = {r["dockID"]: r["zone"] for r in csv.DictReader(f)}
    with (ROOT.parent / f"stations/{city}.csv").open() as f:
        for row in csv.DictReader(f):
            stations.append({"city": city, "dockID": row["dockID"], "lat": float(row["lat"]),
                             "lon": float(row["lon"]), "zone": zones[row["dockID"]]})
    cache = ROOT.parent / f"sources/{city}_roads.json"
    roads[city] = []
    if cache.exists():
        raw = json.loads(cache.read_text())
        nodes = {e["id"]: (e["lat"], e["lon"]) for e in raw["elements"] if e["type"] == "node"}
        points = [p for p in stations + locations if p["city"] == city]
        south, north = min(p["lat"] for p in points)-0.003, max(p["lat"] for p in points)+0.003
        west, east = min(p["lon"] for p in points)-0.003, max(p["lon"] for p in points)+0.003
        for way in raw["elements"]:
            if way["type"] != "way":
                continue
            tags = way.get("tags", {})
            if tags.get("highway") not in {"residential", "living_street", "unclassified", "tertiary", "secondary", "primary", "service", "cycleway", "footway", "path", "pedestrian", "steps"} or tags.get("access") in {"no", "private"}:
                continue
            geometry = [nodes[n] for n in way["nodes"]]
            if any(south <= lat <= north and west <= lon <= east for lat, lon in geometry):
                roads[city].append({"type": tags["highway"], "points": geometry})
assert len(locations) == 30 and len(stations) == 81 and len(records) == 1620
assert len({(r["city"], r["location_id"], r["mode"], r["dockID"]) for r in records}) == 1620
payload = json.dumps({"locations": locations, "stations": stations, "records": records, "roads": roads},
                     allow_nan=False).replace("<", "\\u003c")
template = (ROOT / "viewer_template.html").read_text()
assert template.count("__OPTIMIZER_DATA__") == 1
(OUT / "index.html").write_text(template.replace("__OPTIMIZER_DATA__", payload))
print("PASS: viewer embeds 30 user locations, 81 stations, and 1620 eligible/excluded results")
print("Open data/optimizer/viewer/index.html in your browser; no server required")
