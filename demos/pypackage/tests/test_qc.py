"""Tests for demotool.qc. Every expected number below was worked by hand.

Run from demos/pypackage with:  pytest
"""

import math

import pytest

from demotool import Limits, control_limits, cpk

DATA = [10, 12, 11, 13, 14]


# ---- control_limits ---------------------------------------------------------

def test_control_limits_hand_checked():
    # mean = 60 / 5 = 12
    # moving ranges |12-10|, |11-12|, |13-11|, |14-13| = 2, 1, 2, 1 -> MR_bar = 1.5
    # sigma_hat = 1.5 / 1.128 = 1.329787...
    # limits = 12 -/+ 3 * 1.329787 = 8.010638, 15.989362
    lim = control_limits(DATA)
    assert isinstance(lim, Limits)
    assert lim.center == pytest.approx(12.0)
    assert lim.sigma_hat == pytest.approx(1.5 / 1.128)
    assert lim.lower == pytest.approx(8.010638, abs=1e-6)
    assert lim.upper == pytest.approx(15.989362, abs=1e-6)


def test_control_limits_sigma_argument_scales_width():
    # 2-sigma limits: 12 -/+ 2 * 1.329787 = 9.340426, 14.659574
    lim = control_limits(DATA, sigma=2)
    assert lim.lower == pytest.approx(9.340426, abs=1e-6)
    assert lim.upper == pytest.approx(14.659574, abs=1e-6)


def test_control_limits_order_matters():
    # Same values, different order -> different moving ranges -> different limits.
    # 10, 14, 11, 13, 12: ranges 4, 3, 2, 1 -> MR_bar = 2.5, wider than 1.5.
    assert control_limits([10, 14, 11, 13, 12]).sigma_hat > control_limits(DATA).sigma_hat


def test_control_limits_constant_data_edge_case():
    # Degenerate case: no variation -> sigma_hat 0, limits collapse onto center.
    lim = control_limits([5, 5, 5, 5])
    assert lim == Limits(center=5.0, lower=5.0, upper=5.0, sigma_hat=0.0)


@pytest.mark.parametrize("bad", [[], [1.0], [1, "x", 3], [1, float("nan"), 3]])
def test_control_limits_rejects_bad_values(bad):
    with pytest.raises(ValueError):
        control_limits(bad)


@pytest.mark.parametrize("bad_sigma", [0, -3, float("inf")])
def test_control_limits_rejects_bad_sigma(bad_sigma):
    with pytest.raises(ValueError):
        control_limits(DATA, sigma=bad_sigma)


# ---- cpk --------------------------------------------------------------------

def test_cpk_hand_checked():
    # mean = 12; squared deviations 4, 0, 1, 1, 4 -> sum 10 -> s = sqrt(10/4) = 1.581139
    # min(20 - 12, 12 - 6) = 6 -> Cpk = 6 / (3 * 1.581139) = 1.264911
    assert cpk(DATA, lsl=6, usl=20) == pytest.approx(1.264911, abs=1e-6)


def test_cpk_centered_process_equals_cp():
    # Specs 6 to 18 are centered on the mean 12, so Cpk = Cp = 12 / (6 s) = 1.264911
    s = math.sqrt(2.5)
    assert cpk(DATA, lsl=6, usl=18) == pytest.approx(12 / (6 * s))


def test_cpk_negative_when_mean_outside_specs():
    # mean 12 is above usl 11: min(11 - 12, 12 - 0) = -1 -> Cpk = -1 / 4.743416 = -0.210819
    assert cpk(DATA, lsl=0, usl=11) == pytest.approx(-0.210819, abs=1e-6)


def test_cpk_constant_data_is_undefined():
    # Degenerate case: zero spread. Returning a number here would be wrong.
    with pytest.raises(ValueError, match="zero spread"):
        cpk([5, 5, 5], lsl=0, usl=10)


@pytest.mark.parametrize("lsl, usl", [(20, 6), (6, 6)])
def test_cpk_rejects_bad_spec_limits(lsl, usl):
    with pytest.raises(ValueError):
        cpk(DATA, lsl=lsl, usl=usl)


def test_cpk_rejects_too_few_values():
    with pytest.raises(ValueError):
        cpk([12.0], lsl=6, usl=20)
