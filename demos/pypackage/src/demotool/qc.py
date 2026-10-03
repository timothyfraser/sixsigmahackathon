"""Quality-control statistics: individuals-chart limits and process capability.

Each function is plain Python with plain inputs (a list of numbers) and plain
outputs, so it can be tested on its own and then wrapped in an API or a
dashboard. Only the standard library is used.
"""

from __future__ import annotations

import math
import statistics
from typing import Iterable, NamedTuple

#: Bias-correction constant d2 for a moving range of span 2 (n = 2).
D2_N2 = 1.128


class Limits(NamedTuple):
    """Control limits for an individuals (I) chart.

    Use ``limits._asdict()`` to turn it into a dict (handy for a JSON API).
    """

    center: float
    lower: float
    upper: float
    sigma_hat: float


def _clean(values: Iterable[float], minimum: int) -> list[float]:
    """Convert to a list of floats and refuse bad input loudly."""
    try:
        xs = [float(v) for v in values]
    except (TypeError, ValueError) as err:
        raise ValueError(f"values must all be numbers: {err}") from None
    if len(xs) < minimum:
        raise ValueError(f"need at least {minimum} values, got {len(xs)}")
    if not all(math.isfinite(x) for x in xs):
        raise ValueError("values must be finite (no NaN or infinity)")
    return xs


def control_limits(values: Iterable[float], sigma: float = 3) -> Limits:
    """Center line and control limits for an individuals (I-MR) chart.

    Parameters
    ----------
    values : iterable of float
        Individual measurements in time order, one per sample (subgroup size
        1). At least 2 values. Order matters: the moving range compares each
        value to the one before it.
    sigma : float, default 3
        How many estimated standard deviations the limits sit from the center.
        Must be positive. 3 is the Shewhart convention.

    Returns
    -------
    Limits
        Named tuple ``(center, lower, upper, sigma_hat)`` where
        ``center`` is the mean of the values,
        ``sigma_hat = MR_bar / 1.128`` (MR_bar is the mean absolute difference
        between consecutive values; 1.128 is the d2 constant for n = 2), and
        ``lower, upper = center -/+ sigma * sigma_hat``.

    Assumptions
    -----------
    * The values come from an in-control baseline period. Compute limits on
      the baseline, then judge new points against them; limits computed on
      data that contains the shift you want to detect are too wide.
    * Measurements are roughly normal and not strongly autocorrelated.
    * These are CONTROL limits (what the process does), not SPECIFICATION
      limits (what the customer wants). Do not mix them up.

    Raises
    ------
    ValueError
        Fewer than 2 values, a non-number, NaN/infinity, or ``sigma <= 0``.

    Examples
    --------
    Values 10, 12, 11, 13, 14: mean = 12, moving ranges 2, 1, 2, 1 so
    MR_bar = 1.5 and sigma_hat = 1.5 / 1.128 = 1.3298; limits are
    12 -/+ 3 * 1.3298 = 8.0106 and 15.9894.

    >>> lim = control_limits([10, 12, 11, 13, 14])
    >>> round(lim.center, 4), round(lim.lower, 4), round(lim.upper, 4)
    (12.0, 8.0106, 15.9894)
    """
    if not (isinstance(sigma, (int, float)) and math.isfinite(sigma) and sigma > 0):
        raise ValueError(f"sigma must be a positive number, got {sigma!r}")
    xs = _clean(values, minimum=2)
    center = statistics.fmean(xs)
    mr_bar = statistics.fmean(abs(b - a) for a, b in zip(xs, xs[1:]))
    sigma_hat = mr_bar / D2_N2
    return Limits(
        center=center,
        lower=center - sigma * sigma_hat,
        upper=center + sigma * sigma_hat,
        sigma_hat=sigma_hat,
    )


def cpk(values: Iterable[float], lsl: float, usl: float) -> float:
    """Process capability index Cpk against two specification limits.

    Parameters
    ----------
    values : iterable of float
        Measurements of the quality characteristic. At least 2 values.
    lsl, usl : float
        Lower and upper specification limits. They come from the problem (the
        customer or the design), never from the data. ``lsl < usl``.

    Returns
    -------
    float
        ``Cpk = min(usl - mean, mean - lsl) / (3 * s)``, where ``s`` is the
        sample standard deviation (n - 1 denominator). Cpk >= 1.33 is a common
        "capable" target; a negative Cpk means the mean is outside the specs.

    Assumptions
    -----------
    * The process is in statistical control. Check a control chart FIRST;
      capability of an out-of-control process is meaningless.
    * Measurements are roughly normal.
    * ``s`` here is the overall sample standard deviation. Some texts call the
      index computed this way Ppk and reserve Cpk for a within-subgroup sigma
      (such as ``sigma_hat`` from :func:`control_limits`). Say which one you
      report.

    Raises
    ------
    ValueError
        Fewer than 2 values, a non-number, NaN/infinity, ``lsl >= usl``, or
        zero spread (all values identical), where Cpk is undefined.

    Examples
    --------
    Values 10, 12, 11, 13, 14 with specs 6 to 20: mean = 12,
    s = sqrt(10 / 4) = 1.5811, nearest spec is the lower one (12 - 6 = 6 vs
    20 - 12 = 8, so 6 wins), Cpk = 6 / (3 * 1.5811) = 1.2649.

    >>> round(cpk([10, 12, 11, 13, 14], lsl=6, usl=20), 4)
    1.2649
    """
    if not (math.isfinite(lsl) and math.isfinite(usl)) or lsl >= usl:
        raise ValueError(f"need finite lsl < usl, got lsl={lsl!r}, usl={usl!r}")
    xs = _clean(values, minimum=2)
    s = statistics.stdev(xs)
    if s == 0:
        raise ValueError("all values are identical: zero spread, Cpk is undefined")
    mean = statistics.fmean(xs)
    return min(usl - mean, mean - lsl) / (3 * s)
