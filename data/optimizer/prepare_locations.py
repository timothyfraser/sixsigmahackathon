"""Seeded real three-city user inputs and mode-specific shortest road distances.

Offline; requires the three data/sources/<city>_roads.json caches (download
with data/prepare_networks.py if absent). Standard library only.
"""
import csv
import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent))
from prepare_networks import miles, shortest

def prepare_city(city, center, prefix, seed):
    raw = json.loads((ROOT.parent / f"sources/{city}_roads.json").read_text())
    nodes = {e["id"]: e for e in raw["elements"] if e["type"] == "node"}
    names, neighbors = {}, {}
    for way in raw["elements"]:
        if way["type"] != "way":
            continue
        tags = way.get("tags", {})
        if (tags.get("highway") not in {"residential", "living_street", "unclassified", "tertiary", "secondary", "primary"}
                or not tags.get("name") or tags.get("bicycle") in {"no", "private"}
                or tags.get("access") in {"no", "private"}):
            continue
        for node in way["nodes"]:
            names.setdefault(node, set()).add(tags["name"])
        for a, b in zip(way["nodes"], way["nodes"][1:]):
            neighbors.setdefault(a, set()).add(b)
            neighbors.setdefault(b, set()).add(a)
    with (ROOT.parent / f"stations/{city}.csv").open() as f:
        docks = list(csv.DictReader(f))
    candidates = [n for n in sorted(names) if len(names[n]) >= 2 and len(neighbors[n]) >= 3
                  and miles(center, (nodes[n]["lat"], nodes[n]["lon"])) <= 0.75
                  and min(miles((nodes[n]["lat"], nodes[n]["lon"]),
                                (float(d["lat"]), float(d["lon"]))) for d in docks) >= 0.03]
    random.Random(seed).shuffle(candidates)
    selected = []
    for n in candidates:
        if any(miles((nodes[n]["lat"], nodes[n]["lon"]),
                     (nodes[p]["lat"], nodes[p]["lon"])) < 0.04 for p in selected):
            continue
        selected.append(n)
        if len(selected) == 10:
            break
    assert len(selected) == 10
    locations = [{"city": city, "location_id": f"{prefix}-U{i:02d}", "name": " & ".join(sorted(names[n])),
                  "lat": nodes[n]["lat"], "lon": nodes[n]["lon"], "osm_node_id": n,
                  "source_url": f"https://www.openstreetmap.org/node/{n}"}
                 for i, n in enumerate(selected, 1)]


    for r in locations:
        print(r["location_id"], r["name"], flush=True)


    def graph_for(mode):
        graph = {}
        ordinary = {"residential", "living_street", "unclassified", "tertiary", "secondary",
                    "primary", "service", "track", "road", "tertiary_link", "secondary_link", "primary_link"}
        for way in raw["elements"]:
            if way["type"] != "way":
                continue
            t = way.get("tags", {})
            highway = t.get("highway")
            access = t.get("foot" if mode == "pickup" else "bicycle", "")
            if access in {"no", "private"} or (mode == "return" and access == "use_sidepath"):
                continue
            if t.get("access") in {"no", "private"} and access not in {"yes", "designated", "permissive"}:
                continue
            if mode == "pickup":
                if highway not in ordinary | {"footway", "pedestrian", "path", "steps"} and not (
                        highway == "cycleway" and access in {"yes", "designated", "permissive"}):
                    continue
                direction = t.get("oneway:foot", "no")
            else:
                if highway not in ordinary | {"cycleway"} and not (
                        highway in {"path", "footway", "pedestrian"} and access in {"yes", "designated", "permissive"}):
                    continue
                direction = t.get("oneway:bicycle", t.get("oneway", "yes" if t.get("junction") == "roundabout" else "no"))
                if any(t.get(k, "").startswith("opposite") for k in ("cycleway", "cycleway:left", "cycleway:right")):
                    direction = "no"
            for a, b in zip(way["nodes"], way["nodes"][1:]):
                distance = miles((nodes[a]["lat"], nodes[a]["lon"]), (nodes[b]["lat"], nodes[b]["lon"]))
                pairs = [(b, a)] if direction == "-1" else [(a, b)] if direction in {"yes", "1", "true"} else [(a, b), (b, a)]
                for u, v in pairs:
                    graph.setdefault(u, {})[v] = min(distance, graph.get(u, {}).get(v, math.inf))
                    graph.setdefault(v, {})
        reverse = {n: {} for n in graph}
        for a, edges in graph.items():
            for b, weight in edges.items():
                reverse[b][a] = weight
        remaining, largest = set(graph), set()
        while remaining:
            seed = min(remaining)
            component = set(shortest(graph, seed)) & set(shortest(reverse, seed))
            if len(component) > len(largest):
                largest = component
            remaining.difference_update(component)
            if len(remaining) <= len(largest):
                break
        return graph, largest


    rows, connectors = [], []
    for mode in ("pickup", "return"):
        graph, component = graph_for(mode)
        def snap(point):
            coordinate = (float(point["lat"]), float(point["lon"]))
            node = min(component, key=lambda n: miles(coordinate, (nodes[n]["lat"], nodes[n]["lon"])))
            gap = miles(coordinate, (nodes[node]["lat"], nodes[node]["lon"]))
            assert gap <= 0.15, f"Excessive station/road gap: {gap} miles"
            connectors.append(gap)
            return node, gap
        dock_snaps = [snap(d) for d in docks]
        for user in locations:
            origin, gap = snap(user)
            distances = shortest(graph, origin)
            for dock, (node, dock_gap) in zip(docks, dock_snaps):
                distance = gap + distances[node] + dock_gap
                lower = miles((user["lat"], user["lon"]), (float(dock["lat"]), float(dock["lon"])))
                assert distance + 1e-8 >= lower
                rows.append({"city": city, "location_id": user["location_id"], "mode": mode,
                             "dockID": dock["dockID"], "distance": distance})
        print(f"PASS {mode}: 270 shortest-path distances in miles", flush=True)
    assert len(rows) == 540
    print(f"PASS: 10 sourced real junctions, 540 routes; max connector {max(connectors):.4f} miles")

    return locations, rows


def main():
    all_locations, all_routes = [], []
    cities = [("jersey_city", (40.7178, -74.0431), "JC", 5309),
              ("milwaukee", (43.0389, -87.9065), "MKE", 5310),
              ("tampa", (27.9486, -82.4572), "TPA", 5311)]
    for city, center, prefix, seed in cities:
        locations, routes = prepare_city(city, center, prefix, seed)
        all_locations.extend(locations)
        all_routes.extend(routes)
    for filename, rows in [("user_locations.csv", all_locations),
                           ("user_dock_distances.csv", all_routes)]:
        with (ROOT / filename).open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print("PASS: 30 real user locations and 1620 road/path distances across three cities")


if __name__ == "__main__":
    main()
