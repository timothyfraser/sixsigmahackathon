"""Verify Tampa intersection provenance and road-distance plausibility offline."""
import csv
import json
from pathlib import Path
from prepare_networks import miles, shortest

root = Path(__file__).resolve().parent
with (root / "stations/tampa.csv").open() as f:
    stations = list(csv.DictReader(f))
raw = json.loads((root / "sources/tampa_roads.json").read_text())
nodes = {e["id"]: e for e in raw["elements"] if e["type"] == "node"}
names, neighbors = {}, {}
for way in raw["elements"]:
    if way["type"] != "way" or not way.get("tags", {}).get("name"):
        continue
    for node in way["nodes"]:
        names.setdefault(node, set()).add(way["tags"]["name"])
    for a, b in zip(way["nodes"], way["nodes"][1:]):
        neighbors.setdefault(a, set()).add(b)
        neighbors.setdefault(b, set()).add(a)
assert len(stations) == 27
assert len({s["station_id"] for s in stations}) == 27
assert len({s["dockID"] for s in stations}) == 27
coordinates = {}
for s in stations:
    node = int(s["station_id"].removeprefix("osm-node-"))
    assert node in nodes
    lat, lon = float(s["lat"]), float(s["lon"])
    assert (lat, lon) == (nodes[node]["lat"], nodes[node]["lon"])
    assert 27.9086 <= lat <= 27.9886 and -82.4972 <= lon <= -82.4172
    assert len(names[node]) >= 2 and len(neighbors[node]) >= 3
    assert set(s["dockID"].split(" & ")) <= names[node]
    coordinates[s["dockID"]] = (lat, lon)
with (root / "distances/tampa.csv").open() as f:
    distances = list(csv.DictReader(f))
assert len(distances) == 729
for row in distances:
    lower_bound = miles(coordinates[row["dockID1"]], coordinates[row["dockID2"]])
    assert float(row["distance"]) + 1e-8 >= lower_bound
assert shortest({1: {2: 2, 3: 10}, 2: {3: 3}, 3: {}}, 1)[3] == 5
print("PASS Tampa: 27 unique real OSM intersections; exact source coordinates; at least two named streets and three road branches each")
print("PASS Tampa: all 729 modeled road distances >= straight-line distances; shortest-path known answer = 5 miles")
