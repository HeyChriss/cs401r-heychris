# Lab 6 runbook

## Drift detection plan

### Which drift I expect to see

Data drift is the first thing I expect NorthStar to see. The churn model uses customers’ purchase history to make predictions, and that history changes when people shop differently. Three store rules can cause those changes.

**Holiday promotions.** Purchases made from November 1 through December 24 can be returned through January 31, no matter the customer’s loyalty tier (`return-policy.md`). This affects when people shop and how much they spend. In December, `days_since_last_purchase` gets smaller. Then in January, it gets bigger when customers take a break from shopping. `purchase_frequency_30d` and `avg_order_value` can change too. Free-shipping thresholds ($99, $75, $50, or any amount, depending on tier) and point multipliers (1.25× through 2×) can affect how many orders people place and how much they spend.

A customer who is quiet in January is not necessarily a new kind of customer. Their feature values may just look different from the April 2025–June 2026 training window.

**Catalog changes.** Transactions fall into eight categories: Apparel, Beauty, Electronics, Footwear, Grocery, Home, Outdoor, or Toys. If the store adds, removes, or promotes a category, `category_diversity_score` can change even if the customer’s chance of churning has not. Since the score is one of the model’s inputs, that counts as data drift.

**Economic shifts.** The training contract puts `avg_order_value` between $15 and $620. If people change how much they are willing or able to spend, `avg_order_value` and `total_spend_90d` will probably change before we have the 90-day churn label.

Concept drift can happen too, but it takes longer to confirm. The model predicts whether someone will churn within 90 days, and we use its scores to choose the top 10 percent of customers to contact. The same `days_since_last_purchase` might mean something different the week after Christmas than it does in July. A change to the loyalty terms could also change what “spent a lot” means. For example, returns might reduce a customer’s recent spending and cause them to drop a tier. That would mean the connection between the features and churn has changed. We can’t confirm it until the holdout label is available.

The result we ultimately care about is model degradation. The approved model shipped with an AUC of 0.7854 and top-10-percent recall of 0.3258, above the promotion gate of 0.25. If recall drops once the labels are ready, that is degradation. I’ll check for data drift every time the model scores customers, then check for degradation after the 90-day labels arrive.

### Tests, baseline, and thresholds

The monitor checks five features. The other six stay in the feature row, but they are not part of this check. In Lab 3, `days_since_last_purchase` had the highest gain (66.6), followed by the longer purchase-frequency window. That longer window can take a whole season to show a change, so I’m monitoring the 30-day frequency instead. It can change during one promotion. The table below is the `DRIFT_PLAN` in `monitoring/evidently_drift.py`.

The baseline is the training population: 9,999 customers and the 11 endpoint features, saved in `monitoring/baseline/baseline.csv`. I’ll keep it fixed until the next Approved model package is trained on a new feature snapshot.

The comparison is the champion capture, with one CSV row per request and at least 500 different payloads. Canary is not the comparison because its capture is just the same smoke-test row repeated.

PSI and JSD measure how different two groups of data are. For those tests, we call drift when the value is above the threshold. KS returns a p-value, so we call drift when the value is below the threshold.

| Feature | Test | Threshold | Drift when | Why I chose this test |
|---|---|---|---|---|
| `days_since_last_purchase` | PSI | 0.2 | PSI > 0.2 | This feature had the highest gain. The holidays make it smaller, then January makes it larger. PSI checks whether the overall pattern has changed. |
| `purchase_frequency_30d` | PSI | 0.2 | PSI > 0.2 | This can change during one promotion. The 180-day count is better for splitting the data, but slower to alert because it may not move until the season is over. |
| `avg_order_value` | PSI | 0.2 | PSI > 0.2 | Free-shipping thresholds and changes in how much people spend can both affect order size. PSI above 0.2 is the line we’re using for a meaningful shift. |
| `category_diversity_score` | KS | 0.05 | p < 0.05 | A catalog refresh can change the overall pattern of this score, not just its average. KS checks the full pattern. |
| `total_spend_90d` | KS | 0.05 | p < 0.05 | A sitewide sale can make a small number of customers spend much more than usual. A check of the average might miss that, while KS looks at the whole distribution. |

The first live comparison does not show that the catalog changed. The 500 champion rows came from the beginning of the same feature file used for the baseline. PSI stayed below 0.2 (0.157, 0.081, and 0.165), but both KS p-values fell below 0.05 (about 2.2e-6 and 5.6e-15). That gives us a `violation_count` of 2 and `DriftDetected` of 1.

This shows that the test reacts when the comparison window is not a good sample. For the next run, the 500 rows should come from the current scoring week instead of the beginning of the training file.

### Checking for concept drift before the label exists

We won’t know the true outcome for a score made today for 90 days. Until then, I’ll use the 30-day return rate as an early signal and compare it across score groups.

At each scoring run, I’ll keep track of which customers are in the top 10 percent of churn scores and which customers are outside that group. For purchases they make during the following week, I’ll measure what share gets returned within the return window. Then I’ll compare those rates with the same groups from the training period.

If the gap between the groups gets wider or reverses while all five PSI and KS checks are still within their thresholds, that could be an early sign of concept drift. If the features have already changed, the return gap might just be data drift showing up in customer behavior, so I wouldn’t treat it as the same signal.

The return-rate check takes time because customers have time to return their purchases. Standard members have 30 calendar days (`return-policy.md`), and Platinum members have 60 days. Holiday purchases made from November 1 through December 24 stay open through January 31, so the return data for that period may not settle until January 31. Even with that delay, it is available before the 90-day churn label.

The score cutoff is available as soon as the model runs, so that is the first thing I’d check. Promotions can move the cutoff by changing the model’s inputs. The return-rate gap gives us another way to check whether the ranking still means something when the inputs have not changed.

## SLOs

These are the four promises I’m setting for the churn model. An alert is when I notify someone. The SLO is the monthly target, and the deployment freeze is when I stop shipping another version because too much of the monthly allowance has already been used.

I’m using a 30-day month with 43,200 minutes and a weekly score for all 9,999 customers.

| SLO | Target | SLI (good / total) | Error budget | Deployment freeze trigger |
|---|---|---|---|---|
| Availability | 99.5% | Successful predictions / total requests | 216 minutes/month | Do not deploy once unsuccessful minutes this month reach 108. |
| Latency (p95) | < 20 ms (`ModelLatency` ≤ 20000) | Requests completing in < 20 ms / total requests | 2,000 requests/month | Do not deploy once requests over 20000 µs this month reach 1,000. |
| Prediction quality | Recall@10% ≥ 0.25 on the weekly sample | Weekly samples at or above 0.25 / weekly samples | 1 failed sample/month | Do not approve a package or deploy once a second weekly sample this month is under 0.25. |
| Fairness | Recall gap across loyalty tiers ≤ 10pp | Weeks within the 10pp gap / weeks | 1 failing week/month | Do not approve a package or deploy once a second week this month has a tier more than 10 percentage points below that week’s overall recall@10. |

**Availability.** A 99.5% target allows half a percent of the month to have problems. Half a percent of 43,200 minutes is 216 minutes. I count a minute as unsuccessful when predictions fail during that minute. The freeze starts at 108 minutes, which is half the budget. I want to keep the other half available in case there is a real outage. If a deployment never reaches `InService`, it could use up the rest of that allowance, so I stop the next deployment at that point.

**Latency.** The alert document says to page when latency reaches 200 ms, which is a `ModelLatency` threshold of 200000. This SLO uses 20 ms, or 20000. On this deployment, champion p95 was about 5,297 µs, so a normal week is comfortably under 20 ms. The first call after a deployment is about 24,000 µs, which is over the SLO target. It is still below the 200 ms alert threshold, so it uses some of the budget without paging anyone.

Four weekly scores of 9,999 customers equal 39,996 requests. Five percent of that is about 2,000 requests that could take longer than 20000 µs. I freeze the next deployment at 1,000, when half of that allowance is already gone.

**Prediction quality.** I kept the target at 0.25 because that is the Lab 4 promotion gate. Lab 3 validation recall at the top 10 percent was 0.3212, and the approved model shipped at 0.3258. The positive rate is about 22%. Since we only contact the top 10 percent, recall probably cannot get much above 0.45, even with a very good ranking.

If I set the SLO at the model’s launch score, a normal week below that number could look like a broken promise. I’d rather set a target we can use consistently. I’m assuming there are four weekly samples in a month. One might miss 0.25. If a second sample in the same month misses it, I stop approvals and deployments until the next month.

**Fairness.** A week passes when every loyalty tier’s recall@10 is within 10 percentage points of that week’s overall recall. This is the same flag used in Lab 3. No tier triggered it on the validation split. Silver had the lowest result, about 7 points below the overall 0.3212. Platinum’s recall looked high, but it was based on only 21 churners. That means one unusual week for that group is within the allowance and does not automatically freeze deployments.

If a second week in the same month flags any tier, I stop approvals and deployments for the rest of the month.

## Runbook: Data drift on `days_since_last_purchase`

This runbook is for when `days_since_last_purchase` has changed. Its PSI was 0.157 in the first live run, below the 0.2 threshold, so this runbook did not apply to that run. The KS alerts on the other two features are a different issue, and I would not follow these steps for them.

### Detection

- The alert is `northstar-drift-detected` in `NorthStar/ChurnModel`. It is in ALARM when `DriftDetected` is 1. I only start this runbook when `drift_violations.json` shows `days_since_last_purchase` with method `psi` and a value above 0.2.
- I check the other PSI results in the same file, the number of champion rows captured, and whether `northstar-glue-job-failure` also fired for `northstar-dev-feature-engineer`. If there are fewer than 500 rows, or the feature job is in FAILED, ERROR, or TIMEOUT, the comparison may be bad rather than showing a real shift. If the churn training pipeline is still within its 2-hour suppression window, I do not start this runbook.

### Triage (< 5 minutes)

- **Step 1:** Open `monitoring/reports/drift_violations.json` for the job that just finished. Check the `days_since_last_purchase` row for the PSI value, `captured_records`, and `underpowered_window`. If the method is `ks`, or the feature is not `days_since_last_purchase`, I stop because this runbook does not apply.
- **Step 2:** Check the date and the feature job. A value above 0.2 in January, after purchases made from November 1 through December 24, fits the holiday gap I expect. A value above 0.2 during a random week, or a feature job that did not finish as SUCCEEDED, could mean the file is wrong. I also check `purchase_frequency_30d` and `avg_order_value` in the same report. If they changed too, the week may have really been different. If only recency changed, I look for an incorrect `purchase_date` in the latest `processed/customers/` write.

### Containment options

- **Option A:** Hold today’s offer send and rerun the drift job with a clean champion window of at least 500 different rows from the current scoring week. I use this if `captured_records` is under 500, the rows came from the beginning of the training file, or the feature job failed and a rerun can replace the file. Offers go out only after the new report shows PSI for `days_since_last_purchase` at or below 0.2.
- **Option B:** If I can’t get a clean window today, the offer job uses the last file in `s3://northstar-dev-data-998631802064/artifacts/batch/production/` instead of making offers from today’s scores. This is the same rule I used when the candidate batch disagreed with the incumbent: outreach uses the last file that was allowed to go out. I use this option if the week’s capture is real, PSI is still above 0.2, and there is no corrected feature file yet. Retention still contacts the previous top 10 percent. The new scores are not used until a later run is at or below 0.2, or an Approved retrain replaces `baseline.csv`.

### Escalation

- **When to escalate:** PSI for `days_since_last_purchase` is still above 0.2 after the clean rerun, and the production file being used as a fallback is more than 14 days old. A failed feature job during the same period is also a reason to escalate. Otherwise, customers could be contacted from an outdated list, or not contacted at all.
- **Who is paged:** the retention operations manager. The on-call person is the ML engineer, and this alert is a P3, so the manager is the next escalation.
- **Response time:** the on-call ML engineer responds within 30 minutes of the ALARM on a scoring day. The retention operations manager responds within 60 minutes of the escalation.

### Resolution verification

- I consider the issue resolved when a new drift job, using at least 500 different champion rows from the scoring week, reports `days_since_last_purchase` PSI at or below 0.2 and publishes `DriftDetected` as 0.
- `northstar-drift-detected` also needs to return to OK. If offers went out using the production fallback, Retention Operations needs to know which date that file is from. No offer file should be built from the drifted scores.

### Post-incident actions

- **Within 24 hours:** I write down the PSI value, `captured_records`, whether the feature job was SUCCEEDED, and whether the issue was the January gap or a bad file. If the baseline is no longer a good comparison, I note that. I do not replace `baseline.csv` until the next Approved package is trained on a new snapshot.
- **Postmortem:** required if offers were built from the drifted scores, or if PSI for `days_since_last_purchase` is still above 0.2 on the next weekly run. It is not required if the hold worked and the next run is back at or below 0.2.

## Runbook: Inference latency spike

Champion p95 was about 5,297 µs on this deployment. The first call after a deployment was about 24,000 µs. Neither one triggers this runbook. This runbook starts when p95 is above 500 ms (`ModelLatency` over 500000) for more than 5 minutes.

### Detection

- The early alert is `northstar-model-latency-p95`. It fires when champion p95 is above 200000 for 2 minutes. I start this runbook when p95 stays above 500000 for more than 5 minutes. The unit is microseconds: 500 ms is 500000, not 500.
- I check canary too, along with `northstar-endpoint-cpu-champion` and `EndpointStatus`. If canary is also above 500000, the instance or account may be the problem. If only champion is slow, the issue may be with that version. A slow first call after deployment does not qualify: 24,000 is below 500000 and does not last 5 minutes.

### Triage (< 5 minutes)

- **Step 1:** Check champion p95 for the last five one-minute periods. All five need to be above 500000 before I continue. If the endpoint status is anything other than `InService`, I use the endpoint-down page instead.
- **Step 2:** Check canary p95 for the same five minutes and the champion CPU average. This instance is `ml.t2.medium`. CPU is summed across 2 vCPUs, so the range is 0 to 200. The CPU alarm is an average above 80 for three 5-minute periods. If CPU is rising while p95 is above 500000, the instance may be the cause. If CPU is still around the healthy range I saw (0.06 to 0.32), I look for a stuck request instead of a busy processor.

### Containment options

- **Option A:** Move traffic to the version whose p95 is still below 200000. Champion usually has weight 9 and canary has weight 1. If champion is slow but canary is not, I move requests to canary. The rollback alarm `northstar-churn-rollback-latency` can already take traffic away from canary at 200000. This step goes the other direction, so I use it only when the two versions have different results. A weight of 0 stops requests from going to the slow version. It does not stop the hourly charge, so I still delete or fix that version after the offers are safe.
- **Option B:** If both versions stay above 500000, or I can’t move traffic, the offer job stops calling the endpoint and uses `s3://northstar-dev-data-998631802064/artifacts/batch/production/`. This has the last batch scores I allowed into production. The weekly top 10 percent can still get offers from that file without live requests to the model. I use this option if the endpoint cannot get back below 500000 during the scoring window.

### Escalation

- **When to escalate:** champion p95 is still above 500000 fifteen minutes after moving traffic, or both versions were above 500000 and the offer job had to use the batch file.
- **Who is paged:** the retention operations manager. The on-call ML engineer gets the P2 page from `northstar-model-latency-p95`.
- **Response time:** the on-call ML engineer responds within 15 minutes. The retention operations manager responds within 15 minutes of the escalation because the offer send is waiting on a file decision.

### Resolution verification

- I consider it resolved when champion p95 `ModelLatency` is below 200000 for five one-minute periods in a row and `northstar-model-latency-p95` is OK.
- If the send used the batch file, the offers for that week are complete once the offer job finishes using `artifacts/batch/production/` without calling `northstar-churn-prod`. That means the offers can still go out, but the endpoint is not fixed until its p95 is back below 200000.

### Post-incident actions

- **Within 24 hours:** I record the instance type, the five p95 values above 500000, the CPU averages for those same periods, and which containment option I used. If the `ml.t2.medium` ran out of CPU credits, I note that too so it can be considered before the next deployment.
- **Postmortem:** required if p95 stayed above 500000 for more than 15 minutes, or if that week’s offers were skipped because neither the endpoint nor the production batch file could be used. It is not required if moving traffic or using the batch file got the offers out and p95 was back below 200000 the same day.