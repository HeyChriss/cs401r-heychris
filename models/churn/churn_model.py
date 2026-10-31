"""Your Lab 3 churn model, packaged for the Lab 4 pipeline.

The pipeline's training job runs train_sagemaker.py (beside this file; do not
edit it), which imports this module and calls train(). Only models/churn/ is
uploaded to the training job, so these functions are copied from
churn_training_skeleton.py. Importing that script works on a laptop and fails
in the container.

The XGBoost 1.7 image ships pandas, numpy, scikit-learn, and xgboost. It does
not ship mlflow or sagemaker, so this file does not import them. MLflow
tracking stays in the Lab 3 script.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

# Same columns and order as the Lab 3 depth-6 model.
FEATURE_COLUMNS = [
    "days_since_last_purchase",
    "customer_tenure_days",
    "purchase_frequency_30d",
    "purchase_frequency_90d",
    "purchase_frequency_180d",
    "avg_order_value",
    "total_spend_90d",
    "total_lifetime_value",
    "avg_basket_size_6m",
    "category_diversity_score",
    "online_to_store_ratio",
]

LABEL = "churn_label"
SLICE_COLUMN = "loyalty_tier"
BASELINE_FEATURE = "days_since_last_purchase"

# Lab 3 graded run: depth 6, eta 0.1, 200 rounds, early stop on AUC.
MAX_DEPTH = 6
ETA = 0.1
NUM_ROUND = 200
MIN_CHILD_WEIGHT = 5
SUBSAMPLE = 0.8
COLSAMPLE_BYTREE = 0.8
EARLY_STOPPING_ROUNDS = 20

EVAL_THRESHOLDS = {
    "precision_top10": 0.50,
    "recall_top10": 0.25,
}
BOOTSTRAP_N = 2000
BOOTSTRAP_SEED = 42


def preprocess_features(df: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    """Return (X, y). Missing feature values become the Lab 3 sentinel, -1."""
    print(f"Preprocessing {len(df):,} samples...")
    frame = df.dropna(subset=[LABEL])
    X = frame[FEATURE_COLUMNS].apply(pd.to_numeric, errors="coerce").fillna(-1).to_numpy(dtype=float)
    y = frame[LABEL].to_numpy(dtype=int)
    print(f"  Positive class rate: {y.mean():.1%}")
    print(f"  Feature matrix shape: {X.shape}")
    return X, y


def train_model(X_train: np.ndarray,
                y_train: np.ndarray,
                X_val: np.ndarray,
                y_val: np.ndarray,
                seed: int) -> xgb.Booster:
    """Train the depth-6 churn model. Early stopping uses the last eval metric."""
    dtrain = xgb.DMatrix(X_train, label=y_train, feature_names=FEATURE_COLUMNS)
    dval = xgb.DMatrix(X_val, label=y_val, feature_names=FEATURE_COLUMNS)
    negatives = int((y_train == 0).sum())
    positives = int((y_train == 1).sum())
    if positives < 1:
        positives = 1
    scale_pos_weight = float(negatives / positives)
    params = {
        "objective": "binary:logistic",
        # auc must stay last. XGBoost early-stops on the last metric.
        "eval_metric": ["logloss", "auc"],
        "max_depth": MAX_DEPTH,
        "eta": ETA,
        "min_child_weight": MIN_CHILD_WEIGHT,
        "subsample": SUBSAMPLE,
        "colsample_bytree": COLSAMPLE_BYTREE,
        "scale_pos_weight": scale_pos_weight,
        "seed": seed,
        "verbosity": 1,
    }
    print(f"\nTraining XGBoost with params: {json.dumps(params)}")
    return xgb.train(
        params=params,
        dtrain=dtrain,
        num_boost_round=NUM_ROUND,
        evals=[(dtrain, "train"), (dval, "validation")],
        early_stopping_rounds=EARLY_STOPPING_ROUNDS,
        verbose_eval=25,
    )


def train_recency_baseline(X_train: np.ndarray,
                           y_train: np.ndarray,
                           X_val: np.ndarray,
                           seed: int) -> np.ndarray:
    """Score the validation rows with a model of days_since_last_purchase only."""
    i = FEATURE_COLUMNS.index(BASELINE_FEATURE)
    dtr = xgb.DMatrix(X_train[:, [i]], label=y_train, feature_names=[BASELINE_FEATURE])
    dva = xgb.DMatrix(X_val[:, [i]], feature_names=[BASELINE_FEATURE])
    negatives = int((y_train == 0).sum())
    positives = int((y_train == 1).sum())
    if positives < 1:
        positives = 1
    scale_pos_weight = float(negatives / positives)
    params = {
        "objective": "binary:logistic",
        "eval_metric": "auc",
        "max_depth": 4,
        "eta": 0.1,
        "subsample": 0.9,
        "colsample_bytree": 0.9,
        "scale_pos_weight": scale_pos_weight,
        "seed": seed,
    }
    return xgb.train(params, dtr, num_boost_round=200).predict(dva)


def bootstrap_lift_ci(y_true: np.ndarray,
                      proba: np.ndarray,
                      baseline_proba: np.ndarray,
                      n: int = BOOTSTRAP_N,
                      seed: int = BOOTSTRAP_SEED,
                      alpha: float = 0.05) -> tuple[float, float]:
    """Paired percentile CI for (model AUC - recency AUC)."""
    rng = np.random.default_rng(seed)
    y_true = np.asarray(y_true)
    idx = np.arange(len(y_true))
    diffs = []
    for _ in range(n):
        sample = rng.choice(idx, size=len(idx), replace=True)
        ys = y_true[sample]
        if len(np.unique(ys)) < 2:
            continue
        diffs.append(roc_auc_score(ys, proba[sample]) - roc_auc_score(ys, baseline_proba[sample]))
    if len(diffs) < n // 2:
        raise ValueError(
            "Too few usable bootstrap replicates to form a confidence interval. "
            "The validation set is too small or too imbalanced."
        )
    ordered = np.sort(diffs)
    return float(np.quantile(ordered, alpha / 2)), float(np.quantile(ordered, 1 - alpha / 2))


def evaluate_model(model: xgb.Booster,
                   X_val: np.ndarray,
                   y_val: np.ndarray,
                   baseline_proba: np.ndarray) -> dict:
    """Return the Lab 3 metrics. Raise if a promotion gate fails."""
    y_pred_proba = model.predict(xgb.DMatrix(X_val, feature_names=FEATURE_COLUMNS))
    auc_roc = roc_auc_score(y_val, y_pred_proba)

    top10_threshold = np.percentile(y_pred_proba, 90)
    top10_mask = y_pred_proba >= top10_threshold
    precision_top10 = y_val[top10_mask].mean() if top10_mask.sum() > 0 else 0.0
    recall_top10 = y_val[top10_mask].sum() / y_val.sum() if y_val.sum() > 0 else 0.0

    baseline_auc = roc_auc_score(y_val, baseline_proba)
    auc_vs_baseline = auc_roc - baseline_auc
    lift_ci_low, lift_ci_high = bootstrap_lift_ci(y_val, y_pred_proba, baseline_proba)

    metrics = {
        "auc_roc": round(float(auc_roc), 4),
        "precision_top10": round(float(precision_top10), 4),
        "recall_top10": round(float(recall_top10), 4),
        "auc_vs_baseline": round(float(auc_vs_baseline), 4),
        "baseline_auc": round(float(baseline_auc), 4),
        "lift_ci_low": round(float(lift_ci_low), 4),
        "lift_ci_high": round(float(lift_ci_high), 4),
        "positive_rate_val": round(float(y_val.mean()), 4),
        "n_val_samples": int(len(y_val)),
        "eval_timestamp": datetime.now(timezone.utc).isoformat(),
    }

    print("\n-- Evaluation Results --")
    failures = []
    for metric, threshold in EVAL_THRESHOLDS.items():
        value = metrics[metric]
        status = "PASS" if value >= threshold else "FAIL"
        print(f"  {metric:25s}: {value:.4f}  (threshold: {threshold:.4f})  {status}")
        if value < threshold:
            failures.append(f"{metric}={value:.4f} < {threshold}")

    ci_status = "PASS" if lift_ci_low > 0 else "FAIL"
    print(f"  {'auc_lift 95% CI':25s}: [{lift_ci_low:.4f}, {lift_ci_high:.4f}]"
          f"  (must exclude 0)  {ci_status}")
    if lift_ci_low <= 0:
        failures.append(
            f"auc_lift 95% CI [{lift_ci_low:.4f}, {lift_ci_high:.4f}] includes zero"
        )
    if failures:
        raise ValueError(
            "Model failed evaluation thresholds: " + "; ".join(failures)
            + ". Do not promote to Model Registry."
        )
    print("  All thresholds passed")
    return metrics


def recall(y_true: np.ndarray, proba: np.ndarray) -> float:
    """Recall among the top 10% of scores."""
    y_true = np.asarray(y_true)
    proba = np.asarray(proba)
    positives = y_true.sum()
    if positives == 0:
        return 0.0
    top = proba >= np.percentile(proba, 90)
    return float(y_true[top].sum() / positives)


def evaluate_slices(model: xgb.Booster,
                    X_val: np.ndarray,
                    y_val: np.ndarray,
                    slice_column: pd.Series) -> list[dict]:
    """Per-tier recall. A tier is flagged when it sits more than 10 points below the whole set."""
    y_pred_proba = model.predict(xgb.DMatrix(X_val, feature_names=FEATURE_COLUMNS))
    aggregate_recall = recall(y_val, y_pred_proba)
    tiers = pd.Series(slice_column).reset_index(drop=True)
    results = []
    for slice_value in tiers.unique():
        mask = (tiers == slice_value).to_numpy()
        y_slice = y_val[mask]
        proba_slice = y_pred_proba[mask]
        slice_recall = recall(y_slice, proba_slice)
        results.append({
            "tier": str(slice_value),
            "n": int(mask.sum()),
            "positives": int(np.asarray(y_slice).sum()),
            "auc": (float(roc_auc_score(y_slice, proba_slice))
                    if len(np.unique(y_slice)) > 1 else None),
            "recall": slice_recall,
            "flagged": bool(slice_recall < aggregate_recall - 0.10),
        })
    return results


def train(df: pd.DataFrame, seed: int = 42):
    """Train on the labeled feature table and return (booster, metrics)."""
    before = len(df)
    frame = df.dropna(subset=[LABEL]).reset_index(drop=True)
    if len(frame) < before:
        print(f"Dropped {before - len(frame):,} rows with a missing {LABEL}")
    if SLICE_COLUMN not in frame.columns:
        raise ValueError(f"{SLICE_COLUMN} is required for the slice evaluation.")

    X, y = preprocess_features(frame)
    X_train, X_val, y_train, y_val, _tier_train, tier_val = train_test_split(
        X, y, frame[SLICE_COLUMN], test_size=0.30, random_state=seed, stratify=y,
    )
    print(f"\nTrain: {len(X_train):,} | Validation: {len(X_val):,}")

    model = train_model(X_train, y_train, X_val, y_val, seed)
    baseline_proba = train_recency_baseline(X_train, y_train, X_val, seed)
    metrics = evaluate_model(model, X_val, y_val, baseline_proba)
    metrics["slices"] = evaluate_slices(model, X_val, y_val, tier_val)
    return model, metrics
