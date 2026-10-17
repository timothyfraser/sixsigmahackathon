"""Compatibility entry point: refresh rider projections with the BikeSmart R package."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    subprocess.run(['Rscript', 'tools/export_bikesmart_ui.R', '--rider-only'], cwd=ROOT, check=True)
