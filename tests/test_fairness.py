"""Flag a loyalty-tier recall gap. This check does not block promotion.

The build runs this file beside tests/test_model.py and passes the same
EVAL_METRICS_PATH. train() records one recall per tier under "slices".
A gap above 10 percentage points is a warning for the approver.
"""

import json
import os
import warnings
from pathlib import Path

import pytest


@pytest.fixture(scope="module")
def eval_metrics():
    metrics_path = os.environ.get("EVAL_METRICS_PATH", "/tmp/eval_metrics.json")
    if not Path(metrics_path).exists():
        pytest.skip(f"Evaluation metrics not found at {metrics_path}.")
    with open(metrics_path) as handle:
        return json.load(handle)


def _slices(eval_metrics):
    slices = eval_metrics.get("slices")
    assert slices, "metrics['slices'] is missing. train() must record per-tier recall."
    return slices


def test_slice_recalls_cover_more_than_one_tier(eval_metrics):
    tiers = {row["tier"] for row in _slices(eval_metrics)}
    assert len(tiers) >= 2, f"Need at least two tiers to compare recall, found {sorted(tiers)}"


def test_recall_gap_is_flagged_not_blocking(eval_metrics):
    """Warn when the best and worst tier recalls differ by more than 10 points.

    The assertion only checks that the recalls were recorded. The gap itself
    does not fail the test.
    """
    recalls = {row["tier"]: float(row["recall"]) for row in _slices(eval_metrics)}
    highest = max(recalls, key=recalls.get)
    lowest = min(recalls, key=recalls.get)
    gap = recalls[highest] - recalls[lowest]
    assert 0.0 <= gap <= 1.0, f"Recall gap {gap} is not a rate"
    if gap > 0.10:
        warnings.warn(
            f"fairness flag: recall gap {gap:.1%} between {highest} "
            f"({recalls[highest]:.3f}) and {lowest} ({recalls[lowest]:.3f}) "
            f"exceeds 10 percentage points"
        )
