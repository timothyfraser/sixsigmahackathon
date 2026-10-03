"""demotool - a tiny quality-control package for the Six Sigma Hackathon.

Everything a user should be able to call is imported here, so they can write
``from demotool import control_limits, cpk``.
"""

from demotool.qc import Limits, control_limits, cpk

__all__ = ["Limits", "control_limits", "cpk"]
__version__ = "1.0.0"
