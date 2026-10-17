"""Export directed bicycle street geometry using the distance-matrix graph model.
Uses the same access/one-way filters, station snapping and miles as prepare_networks.
The OSM extracts are cached locally; the generated geometry runs fully offline.
"""
import csv
import heapq
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'data'))
import prepare_networks as preparation


def shortest_paths(graph, start):
    distance, parents, queue = {start: 0.0}, {}, [(0.0, start)]
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distance[node]:
            continue
        for nxt, weight in graph[node].items():
            candidate = cost + weight
            if candidate < distance.get(nxt, float('inf')):
                distance[nxt], parents[nxt] = candidate, node
                heapq.heappush(queue, (candidate, nxt))
    return distance, parents


def export(city):
    stations = list(csv.DictReader((ROOT / f'data/stations/{city}.csv').open()))
    for station in stations:
        station['lat'], station['lon'] = float(station['lat']), float(station['lon'])
    # Reuse the actual matrix builder, including its graph filters and largest
    # strongly connected component. Its final 27 searches are station origins.
    calls = []
    original = preparation.shortest
    def capture(graph, start):
        calls.append((graph, start))
        return original(graph, start)
    preparation.shortest = capture
    try:
        matrix, max_gap = preparation.road_matrix(city, stations)
    finally:
        preparation.shortest = original
    graph = calls[-1][0]
    snaps = [start for _, start in calls[-len(stations):]]
    raw = json.loads((ROOT / f'data/sources/{city}_roads.json').read_text())
    nodes = {row['id']: (row['lat'], row['lon']) for row in raw['elements'] if row['type'] == 'node'}
    recorded = {(r['dockID1'], r['dockID2']): float(r['distance']) for r in csv.DictReader((ROOT / f'data/distances/{city}.csv').open())}
    computed = {(r['dockID1'], r['dockID2']): r['distance'] for r in matrix}
    routes, differences = {}, []
    for i, origin in enumerate(stations):
        distances, parents = shortest_paths(graph, snaps[i])
        for j, target in enumerate(stations):
            if i == j:
                continue
            chain, cursor = [snaps[j]], snaps[j]
            while cursor != snaps[i]:
                cursor = parents[cursor]
                chain.append(cursor)
            chain.reverse()
            assert all(b in graph[a] for a, b in zip(chain, chain[1:])), 'Non-street route segment'
            points = [(origin['lat'], origin['lon']), *[nodes[n] for n in chain], (target['lat'], target['lon'])]
            clean = [points[0]]
            for point in points[1:]:
                if preparation.miles(clean[-1], point) > 1e-9:
                    clean.append(point)
            cumulative = [0.0]
            for a, b in zip(clean, clean[1:]):
                cumulative.append(cumulative[-1] + preparation.miles(a, b))
            pair = (origin['dockID'], target['dockID'])
            length = cumulative[-1]
            assert abs(length - computed[pair]) < 1e-7
            old = recorded[pair]
            differences.append(abs(length - old))
            # Extracts can have changed since the matrix was committed. Keep both
            # distances and report differences rather than stretching geometry.
            routes[f'{i}_{j}'] = dict(lats=[p[0] for p in clean], lons=[p[1] for p in clean],
                n=len(clean), cumulative=[c / length for c in cumulative],
                miles=length, matrix_miles=old, street_node_ids=chain)
    output = ROOT / f'bike-wise-ui/server/data/fleet/{city}/streets.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dict(city=city, routes=routes, source='OpenStreetMap bicycle graph; data/prepare_networks.py',
        osm_timestamp=raw.get('osm3s', {}).get('timestamp_osm_base'), max_connector_miles=max_gap,
        max_matrix_difference_miles=max(differences), routes_validated=len(routes)), separators=(',', ':')))
    print(f'PASS street routes {city}: {len(routes)} directed pairs, every graph edge validated; max matrix difference {max(differences):.6f} mi; max dock connector {max_gap:.4f} mi', flush=True)


if __name__ == '__main__':
    for city in sys.argv[1:] or ['jersey_city', 'milwaukee', 'tampa']:
        export(city)
