# Alert architecture

This is who gets told when the churn model or the offer generator misbehaves. The endpoint is `northstar-churn-prod`. Champion carries weight 9, so I put the CPU and latency alarms on champion. Canary only has the repeated smoke-test row.

While the endpoint was up I created the metric alarms with the actions turned off, so this account never paged anyone. The thresholds below are the ones those alarms used, and the tiers are what I would attach now that the design is written down. The endpoint is already deleted, and I left it deleted.

`ModelLatency` comes back in microseconds. When I say 200 ms I mean a threshold of 200000, and when I say 500 ms I mean 500000. On this deploy, champion p95 was about 5,297. If I had typed 200, the alarm would have been in ALARM the whole time the endpoint was healthy.

## Who gets told

| Tier | What I do |
|---|---|
| P1 | Wake the on-call ML engineer and page the retention operations manager. |
| P2 | Page the on-call ML engineer. |
| P3 | Post in #northstar-ml and open a ticket on the NorthStar ML queue. |
| P4 | Open a ticket on the NorthStar ML queue. Nobody is paged. |

P1 is an outage: no scores, so no top 10 percent and no offers. P2 is the scoring path being wrong or slow enough that today's offers should not go out. P3 is something an engineer should look at the same day, while the store is still taking orders. P4 is a bad offer sentence. It can wait for a person at a desk.

## The alerts

| Alert | Tier | What trips it |
|---|---|---|
| `northstar-endpoint-not-inservice` | P1 | `EndpointUp` < 1 |
| `northstar-model-latency-p95` | P2 | Champion `ModelLatency` p95 > 200000 |
| `northstar-churn-alert-volume` | P2 | `ChurnAlertVolume` more than 30% under the 7-day average |
| `northstar-glue-job-failure` | P3 | Transform or feature job enters FAILED, ERROR, or TIMEOUT |
| `northstar-drift-detected` | P3 | `DriftDetected` >= 1 |
| `northstar-endpoint-cpu-champion` | P3 | Champion CPU average > 80 for three 5-minute periods |
| `northstar-offer-faithfulness` | P4 | Weekly mean `OfferFaithfulness` < 0.50 |

**`northstar-endpoint-not-inservice` (P1).** Once an hour I check `EndpointStatus` for `northstar-churn-prod`. If it is not `InService`, I publish `EndpointUp` = 0 to `NorthStar/ChurnModel`, dimension `EndpointName`. The alarm is average below 1 over one hour. An idle endpoint that is still `InService` does not page. I only had traffic while I was sending the 500 requests, and a "no invocations" alarm would have been in ALARM all night. No endpoint means the top 10 percent does not get scored and the offer job has nothing to send. That is the manager page.

**`northstar-model-latency-p95` (P2).** Namespace `AWS/SageMaker`, metric `ModelLatency`, variant `champion`, extended statistic p95, greater than 200000, period 60 seconds, 2 periods out of 2. That is 200 ms. The first call after a deploy is about 24,000 µs on the reference run, which is 24 ms, so this line does not trip on a cold start. I still want two minutes of it, not one sample. The 20 ms SLO is a monthly budget. It is a different number, and it is not this page.

The deploy script also created `northstar-churn-rollback-latency` at that same 200000 line. Its job is to move traffic off canary. The P2 alarm is the one that pages. If both fire, on-call should get one page.

**`northstar-churn-alert-volume` (P2).** Namespace `NorthStar/ChurnModel`, metric `ChurnAlertVolume`, dimension `EndpointName` = `northstar-churn-prod`, maximum, period 1 hour, less than the threshold. The metric is the count of distinct captured scores. The rule is a drop of more than 30 percent against the 7-day average. I have one window, 500, so the threshold is 350 until seven days exist. Under that, the top 10 percent list is short and the offers will go to the wrong people or to nobody. The store is still up, so this is on-call and not the manager.

**`northstar-glue-job-failure` (P3).** This is the EventBridge rule `northstar-glue-job-failure`, not a CloudWatch threshold. Source `aws.glue`, detail type Glue Job State Change, state FAILED, ERROR, or TIMEOUT, job name `northstar-dev-transform` or `northstar-dev-feature-engineer`. I am not alarming on `glue.driver.aggregate.numFailedTasks`. A transform that died on AccessDenied reported 0 failed tasks. The dashboard can keep graphing that series. The page is the state change. The lab calls a Glue failure P3. I agree. Today's scores do not get built, and the store is not down, so Slack and a ticket are enough.

**`northstar-drift-detected` (P3).** Namespace `NorthStar/ChurnModel`, metric `DriftDetected`, maximum >= 1, period 5 minutes. I publish 1 when any feature in the plan drifts, and 0 when none do. PSI drifts when the value is over 0.2. KS drifts when the p-value is under 0.05. My first publish was 1, and the alarm went to ALARM. The 500 rows were the head of the training file. PSI on the three features stayed under 0.2 (0.157, 0.081, and 0.165), and the two KS p-values fell under 0.05. I would keep the alarm for a normal scoring week. A drift hit is a same-day look, not a reason to wake the manager.

**`northstar-endpoint-cpu-champion` (P3).** Namespace `/aws/sagemaker/Endpoints`, metric `CPUUtilization`, variant `champion`, average over period 300 seconds, 3 periods out of 3, greater than 80. I chose 80 and not 160. SageMaker adds the cores together. This box is `ml.t2.medium`, 2 vCPU, so the metric runs from 0 to 200. A threshold of 80 is 40 percent of the machine. A threshold of 160 would be 80 percent of the whole machine. I took the lower one, on purpose. The first point after `InService` was 96.6 on champion, and the reference run saw 1,101, which a 2-vCPU box cannot actually be. Three 5-minute periods means that one point cannot trip it. After that point, champion sat around 0.06 to 0.32. Memory stays on the dashboard. It is not its own page. If CPU stays high long enough to matter, latency is the P2.

**`northstar-offer-faithfulness` (P4).** Once a week the RAG eval publishes `OfferFaithfulness` to `NorthStar/Offers`, the mean for that run. The alarm is average below 0.50. My two temperature-0 runs averaged 0.572. The Platinum offer that said points will not expire scored 0.429 both times, so 0.50 is under a normal week and over that failure. A wrong sentence is a policy bug. The loyalty terms say points expire 18 months after the last qualifying purchase, and the FAQ says a person cannot reinstate an expired offer. Nobody gets woken up for it. A ticket is how it gets fixed before the next send.

## Suppression

**Suppress `northstar-drift-detected` while the churn training pipeline is running.** The window starts when the pipeline execution starts and ends when that execution reaches a terminal state. If it is still running after 2 hours, the suppression ends anyway and the drift alert is allowed to fire.

That is the only alert this rule suppresses. It does not suppress the endpoint alarm, the latency alarm, the volume alarm, the Glue failure rule, the CPU alarm, or the offer ticket.

A retrain writes a new feature snapshot. Comparing a half-written snapshot to `baseline.csv` trips PSI and KS, and that is the job running, not a catalog change. A Glue failure in that same window still has to reach Slack. A failed feature job is the reason the snapshot is wrong.

I am not suppressing drift for November and December. The holiday return window, the free-shipping thresholds, and the point multipliers are supposed to move `days_since_last_purchase`, `purchase_frequency_30d`, and `avg_order_value`. Hiding those alarms for the season would hide the drift the plan is there to catch.
