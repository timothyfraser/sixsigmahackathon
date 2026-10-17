"""Fetch station metadata and build shortest paths on a bicycle road graph.

Standard library only. Run from repository root. Does not fetch real bike activity.
"""
import csv
import heapq
import json
import math
from pathlib import Path
import urllib.parse
import urllib.request
import urllib.error
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent


def fetch(url, data=None):
    request = urllib.request.Request(url, data=data, headers={
        "User-Agent": "BikeWise-hackathon-synthetic-data/1.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError):
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))


def miles(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    v = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 3958.7613 * 2 * math.asin(min(1, math.sqrt(v)))


def write_csv(path, rows, fields):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def station_selection(city, url, center):
    cache = ROOT / "sources" / (city + "_stations.json")
    if cache.exists():
        return json.loads(cache.read_text())
    stations = fetch(url)["data"]["stations"]
    if city == "jersey_city":
        # Citi Bike's region feed identifies municipal regions.
        regions = fetch("https://gbfs.lyft.com/gbfs/2.3/bkn/en/system_regions.json")["data"]["regions"]
        ids = {str(r["region_id"]) for r in regions if r["name"].lower() in {"jersey city", "jc district"}}
        if not ids:
            raise ValueError("Jersey City region not found; do not guess a boundary")
        stations = [s for s in stations if str(s.get("region_id")) in ids]
    # Milwaukee selection is downtown-centered; the selected names are printed for review.
    stations.sort(key=lambda s: (miles(center, (s["lat"], s["lon"])), str(s["station_id"])))
    if len(stations) < 27:
        raise ValueError(f"Only {len(stations)} eligible stations in {city}")
    rows = [{"station_id": str(s["station_id"]), "dockID": s["name"],
             "lat": s["lat"], "lon": s["lon"]} for s in stations[:27]]
    if len({s["dockID"] for s in rows}) != 27:
        raise ValueError("Duplicate station names; need a naming decision")
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps({"source": url, "retrieved_utc": datetime.now(timezone.utc).isoformat(),
                                 "center": center, "stations": rows}, indent=2))
    return json.loads(cache.read_text())


def shortest(graph, start):
    distances = {start: 0.0}
    queue = [(0.0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for nxt, weight in graph.get(node, {}).items():
            candidate = distance + weight
            if candidate < distances.get(nxt, math.inf):
                distances[nxt] = candidate
                heapq.heappush(queue, (candidate, nxt))
    return distances


def tampa_intersections():
    """Place hypothetical docks at verified shared nodes of named Tampa streets."""
    center = (27.9486, -82.4572)
    road_cache = ROOT / "sources/tampa_roads.json"
    road_cache.parent.mkdir(parents=True, exist_ok=True)
    if not road_cache.exists():
        query = '[out:json][timeout:150];way["highway"](27.9086,-82.4972,27.9886,-82.4172);(._;>;);out body;'
        raw = fetch("https://overpass-api.de/api/interpreter",
                    urllib.parse.urlencode({"data": query}).encode())
        if "remark" in raw:
            raise ValueError(raw["remark"])
        road_cache.write_text(json.dumps(raw))
    raw = json.loads(road_cache.read_text())
    cache = ROOT / "sources/tampa_stations.json"
    if cache.exists():
        return json.loads(cache.read_text())
    nodes = {e["id"]: e for e in raw["elements"] if e["type"] == "node"}
    streets = {}
    neighbors = {}
    for way in raw["elements"]:
        if way["type"] != "way":
            continue
        tags = way.get("tags", {})
        if (tags.get("highway") not in {"residential", "living_street", "unclassified", "tertiary", "secondary", "primary"}
                or not tags.get("name") or tags.get("bicycle") in {"no", "private", "use_sidepath"}
                or tags.get("access") in {"no", "private"}):
            continue
        for node in way["nodes"]:
            streets.setdefault(node, set()).add(tags["name"])
        for a, b in zip(way["nodes"], way["nodes"][1:]):
            neighbors.setdefault(a, set()).add(b)
            neighbors.setdefault(b, set()).add(a)
    candidates = []
    for node, names in streets.items():
        if len(names) < 2 or len(neighbors.get(node, set())) < 3:
            continue
        n = nodes[node]
        candidates.append((miles(center, (n["lat"], n["lon"])), node, sorted(names)))
    rows = []
    used_names = set()
    for distance, node, names in sorted(candidates):
        name = " & ".join(names)
        if name in used_names:
            continue
        used_names.add(name)
        rows.append({"station_id": f"osm-node-{node}", "dockID": name,
                     "lat": nodes[node]["lat"], "lon": nodes[node]["lon"]})
        if len(rows) == 27:
            break
    if len(rows) != 27:
        raise ValueError("Could not verify 27 unique Tampa intersections")
    selected = {"source": "https://www.openstreetmap.org/", "retrieved_utc": datetime.now(timezone.utc).isoformat(),
                "osm_base_timestamp": raw.get("osm3s", {}).get("timestamp_osm_base"),
                "center": center, "location_type": "real intersections; hypothetical bike docks",
                "stations": rows}
    cache.write_text(json.dumps(selected, indent=2))
    return selected


def road_matrix(city, stations):
    cache = ROOT / "sources" / (city + "_roads.json")
    if cache.exists():
        raw = json.loads(cache.read_text())
    else:
        # A 0.04-degree margin allows paths outside the station envelope.
        south = min(s["lat"] for s in stations)-0.04
        north = max(s["lat"] for s in stations)+0.04
        west = min(s["lon"] for s in stations)-0.04
        east = max(s["lon"] for s in stations)+0.04
        query = f'[out:json][timeout:150];way["highway"]({south},{west},{north},{east});(._;>;);out body;'
        raw = fetch("https://overpass-api.de/api/interpreter",
                    urllib.parse.urlencode({"data": query}).encode())
        if "remark" in raw:
            raise ValueError(raw["remark"])
        cache.write_text(json.dumps(raw))
    nodes = {x["id"]: (x["lat"], x["lon"]) for x in raw["elements"] if x["type"] == "node"}
    graph = {}
    allowed = {"cycleway", "residential", "living_street", "unclassified", "tertiary", "secondary",
               "primary", "service", "track", "road", "tertiary_link", "secondary_link", "primary_link"}
    for way in raw["elements"]:
        if way["type"] != "way":
            continue
        tags = way.get("tags", {})
        bike = tags.get("bicycle", "")
        if bike in {"no", "private", "use_sidepath"}:
            continue
        if tags.get("access") in {"no", "private"} and bike not in {"yes", "designated", "permissive"}:
            continue
        if tags.get("highway") not in allowed and not (
                tags.get("highway") in {"path", "footway", "pedestrian"} and bike in {"yes", "designated", "permissive"}):
            continue
        oneway = tags.get("oneway:bicycle", tags.get("oneway", "yes" if tags.get("junction") == "roundabout" else "no"))
        if any(tags.get(k, "").startswith("opposite") for k in ("cycleway", "cycleway:left", "cycleway:right")):
            oneway = "no"
        for a, b in zip(way["nodes"], way["nodes"][1:]):
            weight = miles(nodes[a], nodes[b])
            for u, v in ([(b, a)] if oneway == "-1" else [(a, b)] if oneway in {"yes", "1", "true"} else [(a, b), (b, a)]):
                graph.setdefault(u, {})[v] = min(weight, graph.get(u, {}).get(v, math.inf))
                graph.setdefault(v, {})
    # Snap to nodes of the largest mutually reachable component, avoiding isolated driveways.
    # Determine it by a forward/backward intersection around a central node.
    reverse = {n: {} for n in graph}
    for a, edges in graph.items():
        for b, w in edges.items():
            reverse[b][a] = w
    unassigned = set(graph)
    largest = set()
    while unassigned:
        seed = min(unassigned)
        component = set(shortest(graph, seed)) & set(shortest(reverse, seed))
        if len(component) > len(largest):
            largest = component
        unassigned.difference_update(component)
        if len(unassigned) <= len(largest):
            break
    snaps = []
    for s in stations:
        node = min(largest, key=lambda n: miles((s["lat"], s["lon"]), nodes[n]))
        gap = miles((s["lat"], s["lon"]), nodes[node])
        if gap > 0.15:
            raise ValueError(f'{s["dockID"]}: road connection {gap:.3f} miles exceeds 0.15; review required')
        snaps.append((node, gap))
    rows = []
    for i, a in enumerate(stations):
        distances = shortest(graph, snaps[i][0])
        for j, b in enumerate(stations):
            distance = 0.0 if i == j else snaps[i][1] + distances[snaps[j][0]] + snaps[j][1]
            rows.append({"dockID1": a["dockID"], "dockID2": b["dockID"], "distance": distance})
    return rows, max(gap for _, gap in snaps)


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--stations-only", action="store_true")
    args = parser.parse_args()
    cities = [
        ("jersey_city", "https://gbfs.lyft.com/gbfs/2.3/bkn/en/station_information.json", (40.7178, -74.0431)),
        ("milwaukee", "https://gbfs.bcycle.com/1/bcycle_bublr/station_information.json", (43.0389, -87.9065)),
        ("tampa", None, (27.9486, -82.4572))]
    for city, url, center in cities:
        selected = tampa_intersections() if city == "tampa" else station_selection(city, url, center)
        stations = selected["stations"]
        write_csv(ROOT / "stations" / (city + ".csv"), stations, ["station_id", "dockID", "lat", "lon"])
        print(city + ": " + "; ".join(s["dockID"] for s in stations), flush=True)
        if not args.stations_only:
            matrix, gap = road_matrix(city, stations)
            write_csv(ROOT / "distances" / (city + ".csv"), matrix, ["dockID1", "dockID2", "distance"])
            print(f"{city}: 729 distances; largest station connector {gap:.4f} miles", flush=True)


if __name__ == "__main__":
    main()
