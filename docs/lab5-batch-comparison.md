# Lab 5 batch comparison

NorthStar scores every active customer once a week for 90-day churn. Offers and the service agent are the real-time systems. This run is the weekly scoring job: the same 9,999-customer manifest was scored by the incumbent and by the candidate, and the candidate output was not published.

The incumbent is the Lab 3 model, served from `northstar-churn-incumbent`. The candidate is approved Model Registry version 1 (AUC 0.7854), served from `northstar-churn-candidate`. Both jobs are `ml.m5.large`, one instance, `Completed`. The shared manifest is `s3://northstar-dev-data-998631802064/artifacts/batch/manifest.json`. Customer id stays in the output and is stripped from the model input with `$[1:]`.

A customer disagrees when the absolute difference in churn probability is greater than 0.05. `deployment/configs/rollback-alarm.json` rolls the candidate back when that rate is greater than 0.10. The candidate scores then stay unpublished and the incumbent scores remain the production scores.

## Score distributions

9,999 aligned rows. Counts are customers in each probability bin.

| Probability | Incumbent | Candidate |
|---|---:|---:|
| 0.0–0.1 | 632 | 0 |
| 0.1–0.2 | 1,160 | 0 |
| 0.2–0.3 | 1,404 | 589 |
| 0.3–0.4 | 1,486 | 2,177 |
| 0.4–0.5 | 1,783 | 3,650 |
| 0.5–0.6 | 1,940 | 2,900 |
| 0.6–0.7 | 872 | 138 |
| 0.7–0.8 | 105 | 545 |
| 0.8–0.9 | 103 | 0 |
| 0.9–1.0 | 514 | 0 |

| | Incumbent | Candidate |
|---|---:|---:|
| Mean | 0.417 | 0.464 |
| Median | 0.417 | 0.470 |
| 95th percentile | 0.909 | 0.719 |

## Disagreement

Mean absolute difference: 0.106.

Customers with an absolute difference above 0.05: 7,062 of 9,999, a rate of **0.706**.

0.706 is above the 0.10 threshold, so the rollback control fires. The candidate output at `artifacts/batch/candidate-scores/` is not copied to a production prefix. The incumbent output remains the score that would feed outreach.
