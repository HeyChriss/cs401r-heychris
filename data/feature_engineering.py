"""Pandas port of the Lab 2 feature job.

The Glue job in glue-scripts/feature_engineer.py is the source of these
definitions. Windows are measured backward from the cutoff that the caller
passes in, and rows after that cutoff are ignored. avg_basket_size_6m is
items per order over 180 days, not dollars. category_diversity_score is the
number of real categories divided by 8, and the imputed value "unknown" does
not count.
"""

from __future__ import annotations

import pandas as pd

N_CATEGORIES = 8.0
NO_HISTORY_RECENCY = 999.0

_FREQUENCY_COLUMNS = [
    "purchase_frequency_30d",
    "purchase_frequency_90d",
    "purchase_frequency_180d",
]
_MONETARY_COLUMNS = [
    "avg_order_value",
    "total_spend_90d",
    "total_lifetime_value",
    "avg_basket_size_6m",
]
_BEHAVIOR_COLUMNS = ["category_diversity_score", "online_to_store_ratio"]
_RECENCY_COLUMNS = ["days_since_last_purchase", "customer_tenure_days"]


def _history(transactions: pd.DataFrame, snapshot_date) -> tuple[pd.DataFrame, pd.Timestamp]:
    """Purchases on or before the cutoff. Later rows belong to the holdout."""
    cutoff = pd.Timestamp(snapshot_date).normalize()
    if transactions is None or len(transactions) == 0:
        return transactions.iloc[0:0].copy(), cutoff
    frame = transactions.copy()
    frame["purchase_date"] = pd.to_datetime(frame["purchase_date"])
    day = frame["purchase_date"].dt.normalize()
    return frame.loc[day <= cutoff].copy(), cutoff


def _in_window(frame: pd.DataFrame, cutoff: pd.Timestamp, days: int) -> pd.Series:
    start = cutoff - pd.Timedelta(days=days)
    day = frame["purchase_date"].dt.normalize()
    return day >= start


def compute_recency_features(transactions: pd.DataFrame,
                             snapshot_date,
                             customers: pd.DataFrame | None = None) -> pd.DataFrame:
    """Days since the last purchase, and tenure, both measured to the cutoff.

    A customer id passed in with no purchases gets 999. That is the boundary
    the unit test locks in, and it stays out of the model because the feature
    job only emits customers who bought inside the observation window.
    """
    history, cutoff = _history(transactions, snapshot_date)
    columns = ["customer_id", *_RECENCY_COLUMNS]
    if len(history) == 0:
        features = pd.DataFrame(columns=columns)
    else:
        last = history.groupby("customer_id")["purchase_date"].max()
        first = history.groupby("customer_id")["purchase_date"].min()
        features = pd.DataFrame({
            "customer_id": last.index,
            "days_since_last_purchase": (cutoff - last.dt.normalize()).dt.days.to_numpy(dtype=float),
            "customer_tenure_days": (cutoff - first.dt.normalize()).dt.days.to_numpy(dtype=float),
        })
    if customers is not None:
        ids = customers[["customer_id"]].drop_duplicates()
        features = ids.merge(features, on="customer_id", how="left")
        features[_RECENCY_COLUMNS] = features[_RECENCY_COLUMNS].fillna(NO_HISTORY_RECENCY)
    return features


def compute_frequency_features(transactions: pd.DataFrame, snapshot_date) -> pd.DataFrame:
    """Order counts in the 30, 90, and 180 days before the cutoff."""
    history, cutoff = _history(transactions, snapshot_date)
    columns = ["customer_id", *_FREQUENCY_COLUMNS]
    if len(history) == 0:
        return pd.DataFrame(columns=columns)
    frame = history.copy()
    frame["_d30"] = _in_window(frame, cutoff, 30)
    frame["_d90"] = _in_window(frame, cutoff, 90)
    frame["_d180"] = _in_window(frame, cutoff, 180)
    features = frame.groupby("customer_id", as_index=False).agg(
        purchase_frequency_30d=("_d30", "sum"),
        purchase_frequency_90d=("_d90", "sum"),
        purchase_frequency_180d=("_d180", "sum"),
    )
    for column in _FREQUENCY_COLUMNS:
        features[column] = features[column].astype(float)
    return features


def compute_monetary_features(transactions: pd.DataFrame, snapshot_date) -> pd.DataFrame:
    """Spend and basket size. Basket size is mean items per order over 180 days."""
    history, cutoff = _history(transactions, snapshot_date)
    columns = ["customer_id", *_MONETARY_COLUMNS]
    if len(history) == 0:
        return pd.DataFrame(columns=columns)
    frame = history.copy()
    frame["_in90"] = _in_window(frame, cutoff, 90)
    frame["_in180"] = _in_window(frame, cutoff, 180)
    frame["_spend90"] = frame["order_value"].where(frame["_in90"], 0.0)
    basket = (
        frame.loc[frame["_in180"]]
        .groupby("customer_id")["num_items"]
        .mean()
    )
    features = frame.groupby("customer_id", as_index=False).agg(
        avg_order_value=("order_value", "mean"),
        total_spend_90d=("_spend90", "sum"),
        total_lifetime_value=("order_value", "sum"),
    )
    features["avg_basket_size_6m"] = (
        features["customer_id"].map(basket).fillna(0.0).astype(float)
    )
    return features


def compute_behavioral_features(transactions: pd.DataFrame,
                                snapshot_date=None) -> pd.DataFrame:
    """Diversity across the eight categories, and the share of online orders.

    snapshot_date is optional so the unit tests can call this with the
    transaction frame alone. When it is set, post-cutoff rows are dropped.
    """
    if snapshot_date is None:
        history = transactions.copy()
        if len(history):
            history["purchase_date"] = pd.to_datetime(history["purchase_date"])
    else:
        history, _cutoff = _history(transactions, snapshot_date)
    columns = ["customer_id", *_BEHAVIOR_COLUMNS]
    if len(history) == 0:
        return pd.DataFrame(columns=columns)
    known = history["product_category"].where(history["product_category"] != "unknown")
    diversity = known.groupby(history["customer_id"]).nunique(dropna=True) / N_CATEGORIES
    online = (
        history.assign(_online=(history["channel"] == "online").astype(float))
        .groupby("customer_id")["_online"]
        .mean()
    )
    features = pd.DataFrame({"customer_id": history["customer_id"].drop_duplicates()})
    features["category_diversity_score"] = features["customer_id"].map(diversity).fillna(0.0)
    features["online_to_store_ratio"] = features["customer_id"].map(online).fillna(0.0)
    return features


def build_churn_feature_set(customers: pd.DataFrame,
                            transactions: pd.DataFrame,
                            snapshot_date) -> pd.DataFrame:
    """One row per customer. Customers who never purchased keep the 999 recency sentinel."""
    recency = compute_recency_features(transactions, snapshot_date, customers)
    frequency = compute_frequency_features(transactions, snapshot_date)
    monetary = compute_monetary_features(transactions, snapshot_date)
    behavior = compute_behavioral_features(transactions, snapshot_date)
    features = recency
    for part in (frequency, monetary, behavior):
        features = features.merge(part, on="customer_id", how="left")
    fill = {column: 0.0 for column in _FREQUENCY_COLUMNS + _MONETARY_COLUMNS + _BEHAVIOR_COLUMNS}
    features = features.fillna(fill)
    keep = [column for column in ("loyalty_tier", "churn_label") if column in customers.columns]
    if keep:
        features = features.merge(customers[["customer_id", *keep]], on="customer_id", how="left")
    return features
