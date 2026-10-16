"""Plot the selected stations and cached road network; no network requests.

Run from repository root: python3 data/plot_milwaukee.py
Requires matplotlib. Road eligibility matches prepare_networks.py.
"""
import csv
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.ticker import FormatStrFormatter

ROOT = Path(__file__).resolve().parent
with (ROOT / "stations/milwaukee.csv").open() as source:
    stations = list(csv.DictReader(source))
raw = json.loads((ROOT / "sources/milwaukee_roads.json").read_text())
nodes = {e["id"]: (e["lon"], e["lat"]) for e in raw["elements"] if e["type"] == "node"}
allowed = {"cycleway", "residential", "living_street", "unclassified", "tertiary",
           "secondary", "primary", "service", "track", "road", "tertiary_link",
           "secondary_link", "primary_link"}
roads, cycleways = [], []
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
        tags.get("highway") in {"path", "footway", "pedestrian"}
        and bike in {"yes", "designated", "permissive"}):
        continue
    points = [nodes[n] for n in way["nodes"]]
    (cycleways if tags.get("highway") in {"cycleway", "path", "footway", "pedestrian"}
     else roads).append(points)

longitude = [float(s["lon"]) for s in stations]
latitude = [float(s["lat"]) for s in stations]
assert len(stations) == 27 and len(set(s["dockID"] for s in stations)) == 27
fig = plt.figure(figsize=(16, 11), facecolor="#f7fafc")
ax = fig.add_axes([0.07, 0.22, 0.53, 0.66], facecolor="#f0f4f6")
ax.add_collection(LineCollection(roads, colors="#b5c1c9", linewidths=0.7, zorder=1))
ax.add_collection(LineCollection(cycleways, colors="#69a99a", linewidths=1.2, zorder=2))
ax.scatter(longitude, latitude, s=160, c="#cf493b", edgecolors="white", linewidths=1.5, zorder=4)
for i, (lon, lat) in enumerate(zip(longitude, latitude), 1):
    ax.text(lon, lat, str(i), ha="center", va="center", fontsize=7.5,
            weight="bold", color="white", zorder=5)
ax.set_xlim(min(longitude)-0.003, max(longitude)+0.003)
ax.set_ylim(min(latitude)-0.002, max(latitude)+0.002)
ax.set_aspect(1 / math.cos(math.radians(sum(latitude)/len(latitude))))
ax.set_xlabel("Longitude (WGS84 degrees)", labelpad=10)
ax.set_ylabel("Latitude (WGS84 degrees)", labelpad=10)
ax.xaxis.set_major_formatter(FormatStrFormatter("%.3f°"))
ax.yaxis.set_major_formatter(FormatStrFormatter("%.3f°"))
ax.tick_params(labelsize=9)
ax.grid(alpha=0.25, linestyle=":", zorder=0)
for spine in ax.spines.values():
    spine.set_color("#b5c1c9")
ax.annotate("N", xy=(0.95, 0.97), xytext=(0.95, 0.88), xycoords="axes fraction",
            ha="center", fontsize=12, weight="bold", arrowprops={"arrowstyle": "->", "color": "#243746"})
# Half-mile scale at the lower left (longitude adjusted to local latitude).
scale_degrees = 0.5 / (69.0934 * math.cos(math.radians(sum(latitude)/len(latitude))))
x0 = ax.get_xlim()[0] + 0.001
y0 = ax.get_ylim()[0] + 0.0007
ax.plot([x0, x0+scale_degrees], [y0, y0], color="#243746", linewidth=3, zorder=6)
ax.text(x0+scale_degrees/2, y0+0.00025, "0.5 mile", ha="center", fontsize=9)
fig.text(0.07, 0.94, "Milwaukee · Bublr station network", fontsize=24, weight="bold", color="#243746")
fig.text(0.07, 0.905, "27 selected downtown stations on the road/path graph used to build the distance matrix",
         fontsize=12, color="#526574")
fig.text(0.65, 0.86, "STATION KEY", fontsize=13, weight="bold", color="#243746")
for i, station in enumerate(stations, 1):
    fig.text(0.65, 0.825-(i-1)*0.024, f'{i:02d}   {station["dockID"].strip()}',
             fontsize=10.5, color="#243746")
fig.text(0.07, 0.075,
         "Red circles: selected docks    Gray: eligible roads    Green: eligible cycleways / paths\n"
         "Dotted lines are latitude/longitude guides, not roads. One-way directions and individual routes are not drawn.\n"
         "Sources: Bublr station-information feed; © OpenStreetMap contributors (openstreetmap.org/copyright).\n"
         "This is the selected 27-station subset, not every Bublr station in Milwaukee. Bike activity is synthetic.",
         fontsize=9, linespacing=1.6, color="#526574")
output = ROOT / "validation"
output.mkdir(exist_ok=True)
for extension in ("png", "svg"):
    fig.savefig(output / f"milwaukee_station_map.{extension}", dpi=180, facecolor=fig.get_facecolor())
plt.close(fig)
print(f"PASS: plotted {len(stations)} stations; {len(roads)} road ways; {len(cycleways)} cycleway/path ways")
print("Saved data/validation/milwaukee_station_map.png and .svg")
