# Lab 5 deployment plan

## 1. Deployment strategy and rationale

I scored churn with a weekly batch job. NorthStar wants a 90-day probability for every active customer, and retention only works the top 10 percent. The POS file lands overnight and the feature job runs after it, so the score can wait. An endpoint up all week would bill the whole time for a score I only need once.

I ran the new model next to the old one, same manifest, and I left the production file alone. `northstar-churn-incumbent` is the Lab 3 model. `northstar-churn-candidate` is registry version 1, which I approved. Each job is one `ml.m5.large`. The candidate scores stayed in their own prefix because section 3 failed.

## 2. Pre-deployment checklist

I ran this from the repo root in `us-east-1`. Account id:

```bash
aws sts get-caller-identity --query Account --output text
```

The bucket is `northstar-dev-data-` plus that id. Mine is `northstar-dev-data-998631802064`.

1. Transform quota has to be at least 1. A new account is 0 for `ml.m5.large` transform. Mine was already 8.

```bash
aws service-quotas get-service-quota --service-code sagemaker --quota-code L-236AE59F --region us-east-1 --query Quota.Value --output text
```

2. Features have to exist. Glue job `northstar-dev-feature-engineer` had succeeded, and `aws s3 ls s3://<bucket>/features/customers/` showed parquet.

3. One CSV, no header. Column 1 is `customer_id`, then the 11 `FEATURE_COLUMNS` in `models/churn/churn_model.py`, in that order. Manifest: `s3://<bucket>/artifacts/batch/manifest.json`. `$[1:]` hides the id. `JoinSource` `Input` writes it back so the two files line up.

4. The pipeline only registers `PendingManualApproval`. The Model Approver has to set `Approved`. I did that as IAM user `cs401r-lab` on 2026-11-11, for version 1. AUC 0.7854, baseline 0.7208, precision in the top 10 percent 0.7167, recall in the top 10 percent 0.3258, lift interval 0.0451 to 0.084. No loyalty tier was flagged.

```bash
aws sagemaker list-model-packages --model-package-group-name northstar-churn-models --region us-east-1 --query "ModelPackageSummaryList[].[ModelPackageVersion,ModelApprovalStatus,ModelPackageArn]" --output table
aws sagemaker update-model-package --model-package-arn <package-arn> --model-approval-status Approved --region us-east-1
```

5. I wrote `deployment/configs/rollback-alarm.json` before I looked at the scores and left the threshold alone.

Then I created the models and started the jobs. Change `TransformJobName` in both job files before a rerun, because a finished name cannot be reused.

```bash
aws sagemaker create-model --cli-input-json file://deployment/configs/model-incumbent.json --region us-east-1
aws sagemaker create-model --cli-input-json file://deployment/configs/model-candidate.json --region us-east-1
aws sagemaker create-transform-job --cli-input-json file://deployment/configs/transform-job-incumbent.json --region us-east-1
aws sagemaker create-transform-job --cli-input-json file://deployment/configs/transform-job-candidate.json --region us-east-1
```

I waited until `describe-transform-job` said `Completed` for `northstar-churn-incumbent-v2` and `northstar-churn-candidate-v2`. Scores are `s3://<bucket>/artifacts/batch/incumbent-scores/customers.csv.out` and the same name under `candidate-scores/`. The last column is the probability.

## 3. Rollback criteria

The metric is `ScoreDisagreementRate`. A customer disagrees when the two probabilities differ by more than 0.05 (`ProbabilityDelta`). The rate is that count divided by every customer. I roll back above 0.10. The unit is `Rate`. That is what is in `deployment/configs/rollback-alarm.json`.

The Model Approver makes the call. From the repo root:

```bash
bash deployment/configs/rollback-action.sh <rate>
```

Over 0.10 the script prints `ROLLBACK` and exits 1. I do not copy the candidate file to `s3://<bucket>/artifacts/batch/production/`. Outreach keeps the incumbent file. On 9,999 customers my rate was 0.706, so I rolled this one back.

## 4. Monitoring window

In production I would sit on the candidate for 48 hours after both jobs are `Completed`. I would watch the disagreement rate, both means, both 95th percentiles, and the row count against the feature group. Clean means the rate is 0.10 or lower, both jobs finished, and the counts match.

The lab compresses that to 60 minutes. One pass misses the next weekly score, a late feature file, and a rate that is bad one week and fine the next. A higher mean also changes who lands in the top 10 percent.

I did not register auto-scaling. One `ml.m5.large`, and billing stops at `Completed`. On an endpoint I would track `SageMakerVariantInvocationsPerInstance` at 1000, scale out 60 seconds, scale in 600 seconds. Those files are not in the repo.

## 5. Stakeholder notifications

I notify roles, not named people.

- Data Engineer, at the start: feature prefix and Glue run id. On a rollback: whether the feature row count matched the score files.
- ML Engineer, at the start: both job names and the manifest URI. On a promote: the production prefix. On a rollback: leave the candidate output where it is.
- Model Approver, at the start: package version and the metrics in section 2. At the decision: the rate, the 0.10 threshold, and PROMOTE or ROLLBACK.
- Retention Operations, at the start: scoring has started and this week's file is unchanged. On a promote: the production prefix and the score date. On a rollback: stay on the incumbent, and do not build offers from the candidate file.

## 6. Post-deployment review

Next business day, inside the 48-hour window when we actually wait that long. The Model Approver runs it. ML Engineer and Data Engineer attend. Retention Operations comes on a rollback, or if the top 10 percent changed size. We write down the job names, the rate, the threshold, the decision, and the row-count check. This lab's note is `docs/lab5-batch-comparison.md`.

## 7. Resource cleanup

Finished jobs are not billing. I ran `bash scripts/teardown-lab5.sh` from the repo root. It deletes scaling policies and targets, alarms starting with `northstar-churn-rollback`, endpoints, endpoint configs, and models, and it stops jobs still `InProgress`. `docs/lab5-teardown-output.txt` needs six `OK` lines for those checks. I keep the model registry. The NAT gateway stays until `scripts/teardown-lab2.sh`, and only with the current Lab 2 kit.
