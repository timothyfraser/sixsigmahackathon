"""Plot validated hourly zone inventories. Requires matplotlib; offline."""
import csv
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent
with (root / "validation/zone_inventory_by_hour.csv").open() as f:
    rows = list(csv.DictReader(f))
colors = {"residential": "#2978b5", "office": "#c45b32", "retail": "#398257"}
cities = ["jersey_city", "milwaukee", "tampa"]
fig, axes = plt.subplots(2, 3, figsize=(15, 8), sharex=True, sharey=True)
for col, city in enumerate(cities):
    for row, day in enumerate(["weekday", "weekend"]):
        ax = axes[row, col]
        for zone, color in colors.items():
            selected = sorted((r for r in rows if r["city"] == city and r["day_type"] == day
                               and r["zone"] == zone), key=lambda r: int(r["hour"]))
            assert len(selected) == 24
            ax.plot([int(r["hour"]) + 0.5 for r in selected],
                    [float(r["mean_bikes_per_station"]) for r in selected],
                    color=color, label=zone.title(), linewidth=2.2)
        if day == "weekday":
            for hour in (8.5, 17.5):
                ax.axvline(hour, color="#777777", linestyle=":", linewidth=1)
            ax.axvspan(11.5, 14, color="#777777", alpha=0.08)
        ax.set_title(f"{city.replace('_', ' ').title()} · {day.title()}")
        ax.set_xlim(0, 24)
        ax.set_ylim(0, 30)
        ax.set_xticks([0, 4, 8, 12, 16, 20, 24])
        ax.grid(alpha=0.2)
        if col == 0:
            ax.set_ylabel("Mean docked bikes per station (capacity 30)")
        if row == 1:
            ax.set_xlabel("Local hour of day")
fig.suptitle("Synthetic zoning creates station imbalance", fontsize=19, weight="bold", y=0.98)
handles, labels = axes[0, 0].get_legend_handles_labels()
fig.legend(handles, labels, loc="upper center", bbox_to_anchor=(0.5, 0.94), ncol=3, frameon=False)
fig.text(0.5, 0.025,
         "Nine stations per zone per city · 30-day averages · Dotted lines: 08:30 / 17:30 · Shading: lunch\n"
         "Zone labels and all bike movements are synthetic; averages hide individual station extremes.",
         ha="center", fontsize=10, color="#555555")
fig.subplots_adjust(top=0.83, bottom=0.14, wspace=0.13, hspace=0.25)
for ext in ("png", "svg"):
    fig.savefig(root / f"validation/zone_imbalance.{ext}", dpi=180, bbox_inches="tight")
plt.close(fig)
print("PASS: six panels, three zones each, 24 hourly observations per zone; PNG/SVG saved")
