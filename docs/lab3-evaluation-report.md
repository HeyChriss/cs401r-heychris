# Lab 3 evaluation report

The registered model is the depth-6 XGBoost run `depth6-eta0.1`, version 1 of `northstar-churn-models`, status `PendingManualApproval`. It was trained on 6,999 customers and scored on 3,000, a 70/30 stratified split of the 9,999 rows in `northstar-dev-customer-features`. The positive rate on the validation set is 22.0%.

## Decision

Contact the top 10% of validation scores. That cutoff is a predicted probability of 0.6341. Of the 300 customers contacted, 212 had churned and 88 had not.

|  | Predicted stay | Predicted churn |
|---|---:|---:|
| Stayed | 2,252 | 88 |
| Churned | 448 | 212 |

Precision at that cutoff is 0.7067 and recall is 0.3212. Both clear the gates of 0.50 and 0.25. The confusion matrix is `docs/lab3-evidence/confusion-matrix.png`.

## Baseline

A model trained on `days_since_last_purchase` alone has validation AUC 0.7225. The full model has AUC 0.7791, a lift of 0.0566. The 95% bootstrap interval on that lift is 0.0370 to 0.0756, which excludes zero.

## What was varied

Three runs, same data and split, learning rate 0.1. The only change is `max_depth`.

| Run | Depth | AUC | Precision @ top 10% | Recall @ top 10% | Lift 95% CI |
|---|---:|---:|---:|---:|---|
| depth4-eta0.1 | 4 | 0.7796 | 0.7267 | 0.3303 | 0.0388 to 0.0760 |
| depth6-eta0.1 | 6 | 0.7791 | 0.7067 | 0.3212 | 0.0370 to 0.0756 |
| depth8-eta0.1 | 8 | 0.7701 | 0.7300 | 0.3318 | 0.0280 to 0.0662 |

Depth 4 and depth 6 are the same model for practical purposes: 0.0005 AUC apart. Depth 8 is worse. Its training AUC reached 0.933 while validation AUC fell to 0.770, so the extra depth fit the training rows and did not generalize. Depth 6 is the registered run because it is the pre-set default and depth 4 does not beat it.

## Slices

Recall is computed inside each loyalty tier, on that tier's own top 10% of scores. A tier is flagged when its recall is more than 10 percentage points below the overall recall of 0.3212. None are.

| Tier | n | Positives | AUC | Recall @ top 10% |
|---|---:|---:|---:|---:|
| Bronze | 1,071 | 361 | 0.757 | 0.291 |
| Silver | 1,139 | 226 | 0.707 | 0.252 |
| Gold | 483 | 52 | 0.745 | 0.288 |
| Platinum | 307 | 21 | 0.872 | 0.524 |

Silver is the weak tier: AUC 0.707 and recall 0.252, about 7 points under the overall recall, short of the flag. Platinum's AUC is high, and it rests on 21 churners, so that number is thin.

## Features

Gain importance on the registered model is led by `days_since_last_purchase` (66.6) and `purchase_frequency_180d` (62.5). The other nine features sit between 9.3 and 19.8. The plot is `docs/lab3-evidence/feature-importance.png`. Recency dominates, which is why the lift over the recency-only baseline is real but modest. The frequency and spend features are what produce that lift.
