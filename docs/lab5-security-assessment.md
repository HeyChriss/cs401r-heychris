# Lab 5 security assessment

The churn system is the weekly batch score. Three IAM roles bound it. `northstar-dev-MLEngineer` trains and serves, and it can read and write `artifacts/` and `features/`. It has no Glue and no Athena. `northstar-dev-DataEngineer` runs Glue and writes `raw/`, `processed/`, and `features/`. `northstar-dev-ModelMonitor` can write CloudWatch metrics and can only read `artifacts/`. The data bucket `northstar-dev-data-998631802064` is versioned and encrypted with SSE-S3 (`AES256`). That default matters in the classification table: a principal who can `s3:GetObject` receives plaintext, because there is no KMS key in the path.

## 3a. STRIDE threat model

| Threat | STRIDE Category | Likelihood | Impact | Mitigation | AWS Control |
|---|---|---|---|---|---|
| A substituted `model.tar.gz` is registered and scored as if it were the approved churn model. | Spoofing | M | H | The training pipeline registers the package as `PendingManualApproval`. Only an explicit `UpdateModelPackage` sets `Approved`. The job runs as `northstar-dev-MLEngineer`, and that role's trust policy allows `sagemaker.amazonaws.com` only. | SageMaker Model Registry approval status. IAM trust policy on `northstar-dev-MLEngineer`. |
| A compromised data pipeline rewrites `features/customers/` before the weekly score, so both models score poisoned rows. | Tampering | M | H | The blast radius is `northstar-dev-DataEngineer`. That role can write `raw/`, `processed/`, and `features/`, and it cannot write `artifacts/`. `northstar-dev-MLEngineer` cannot write `raw/`. Versioning keeps the previous feature objects. | IAM statement `S3DataPrefixes` on `northstar-dev-DataEngineer`. S3 bucket versioning on `northstar-dev-data-998631802064`. |
| Nobody can show who approved version 1, or who later read the score file. | Repudiation | M | M | Management calls such as `UpdateModelPackage` and `CreateTransformJob` are recorded. Object reads are not, unless data events are enabled. None of the three roles turns data events on. That is a gap those roles do not close. | AWS CloudTrail management events. CloudTrail S3 data events on `s3:GetObject` for the data bucket. |
| The batch score file, which holds `customer_id`, the feature row, and the probability, is readable by the observer role. The weights in the same prefix support membership inference. | Information Disclosure | M | H | `northstar-dev-ModelMonitor` is the blast radius: `S3ArtifactsRead` is `s3:GetObject` on `artifacts/*`, and the shadow scores were written to `artifacts/batch/`. Move customer-level scores to a prefix that statement does not cover. SSE-S3 does not add a second check. | IAM statement `S3ArtifactsRead` on `northstar-dev-ModelMonitor`. An AWS KMS key policy that does not grant that role `kms:Decrypt`. |
| Repeated transform jobs hold the eight `ml.m5.large` transform slots, so the weekly score cannot start. | Denial of Service | L | M | The account quota stops an unbounded fleet. A finished job releases the instance. Teardown stops anything still `InProgress`. | Service Quotas quota `L-236AE59F`. SageMaker `StopTransformJob` for jobs still running. |
| A principal that can pass `northstar-dev-MLEngineer` into SageMaker gains training, registration, and writes to `features/` and `artifacts/`. | Elevation of Privilege | L | H | `iam:PassRole` is allowed only for that role ARN, and only when `iam:PassedToService` is `sagemaker.amazonaws.com`. The role has no Glue, no Athena, and no `s3:GetObject` on `raw/*`. The gap: IAM user `cs401r-lab` sits outside all three roles and can approve a package and read every prefix directly. | IAM `PassRole` condition on `northstar-dev-MLEngineer`. The missing `raw/*` resource on statement `S3ArtifactsAndFeatures`. |

## 3b. Data classification

The tier is the sensitivity of the asset. The encryption column is the standard that asset should use. SSE-S3 is S3-managed AES-256. SSE-KMS is a customer managed key, so `kms:Decrypt` is a second decision and key use is in CloudTrail. CSE would keep plaintext out of Glue and the XGBoost container, which have to read the objects, so it is not the choice for any asset below.

| Asset | Tier | Encryption | Why this standard | IAM access | Share with a vendor |
|---|---|---|---|---|---|
| Customer PII | Restricted | SSE-KMS | Names, contact, and the customer master identify a person. SSE-S3, which the bucket uses today, returns plaintext to any `s3:GetObject`. A CMK denies decrypt without a key grant. CSE would stop the Glue crawler from reading the raw CSV. | `northstar-dev-DataEngineer` on `raw/`. `northstar-dev-MLEngineer` has no `raw/*`. | No |
| Transaction history | Confidential | SSE-KMS | Amounts, dates, and `customer_id` are personal when joined, and they are not contact details, so the tier stays below Restricted. SSE-S3 would make the DataEngineer object grant the only gate. | `northstar-dev-DataEngineer` on `raw/` and `processed/`. | No |
| Behavioral clickstream | Confidential | SSE-KMS | Device, session, and click events are quasi-identifiers at high volume. A CMK lets a stream consumer be granted decrypt without opening the customer master. SSE-S3 cannot make that split. | Not granted on the three roles today. A stream prefix should be `northstar-dev-DataEngineer` only. | No |
| Product catalog | Internal | SSE-S3 | Descriptions and list prices are business data, not personal data. S3-managed AES-256 is enough. A CMK on the whole catalog adds key cost and no privacy boundary. Inventory counts stay in this tier and off the public site feed. | Not required by the ML roles. A commerce role can read the catalog prefix. | Yes, for published descriptions and list prices only |
| Model weights | Confidential | SSE-KMS | The tarball can be used for membership inference against the training set. SSE-S3 means `S3ArtifactsRead` is enough to download it. A CMK can omit `northstar-dev-ModelMonitor` from `kms:Decrypt`. CSE would break the XGBoost container, which loads `xgboost-model` itself. | `northstar-dev-MLEngineer` reads and writes `artifacts/`. `northstar-dev-ModelMonitor` reads `artifacts/`. `northstar-dev-DataEngineer` can read only `artifacts/glue/`. | No |
| Inference logs | Restricted | SSE-KMS | The batch score file and any later `datacapture/` objects hold `customer_id`, the feature vector, and the probability. That recreates a personal scoring record. The 7-day expiration and the 1-day noncurrent delete limit how long it lives. They do not change who can read it. SSE-S3 is the wrong standard while those objects sit in this bucket. | `northstar-dev-MLEngineer` writes `datacapture/*` and `artifacts/batch/`. `northstar-dev-ModelMonitor` can read `artifacts/batch/` today and should not. | No |
| Feature Store records | Confidential | SSE-KMS | The offline store under `features/` includes the label and the same features as the score file. The online store is SageMaker feature group `northstar-dev-customer-features`. A CMK on the offline prefix forces training reads through `kms:Decrypt`. SSE-S3 leaves `features/*` `GetObject` as the only control. | `northstar-dev-DataEngineer` writes `features/` and calls `PutRecord`. `northstar-dev-MLEngineer` reads `features/`. `northstar-dev-ModelMonitor` has no `features/` access. | No |

## 4. Privacy impact assessment

### Personal data inventory

The weekly churn job processes personal data because every row is tied to a `customer_id`. The fields actually present at each stage:

| Stage | Where it lives | Personal data |
|---|---|---|
| Ingest | `s3://northstar-dev-data-998631802064/raw/customers/` | `customer_id` on each transaction. The full customer master also carries hashed email, `age_band`, `state`, and `zip_code`. |
| Transform | `processed/customers/` | One row per transaction: `customer_id`, amounts, dates, store, channel, payment method. |
| Features | `features/customers/` and feature group `northstar-dev-customer-features` | `customer_id`, the 11 aggregates, `loyalty_tier`, `churn_label`, `event_time`. |
| Training | `artifacts/training/.../model.tar.gz` | No `customer_id` column. The booster is fit on those customers' feature rows and the label. |
| Scoring | `artifacts/batch/*/customers.csv.out` | `customer_id`, the 11 features, and the churn probability. |

Clickstream is not in this pipeline. `search_query` in that source can contain an email address, which is why it stays out.

### Lawful basis

The basis is legitimate interests, GDPR Article 6(1)(f).

NorthStar already holds purchase history because the customer bought goods. The churn score uses that history to cut 12-month churn from 18 percent to 14 percent by offering retention to the top 10 percent, instead of a blanket 20 percent discount. That is the retailer's interest in keeping customers and in not giving away margin.

Contractual necessity does not fit. The sale is complete without a churn probability. The score is not required to deliver the goods or to run the loyalty account. Consent does not fit either. The job scores every active customer once a week. A consent gate would drop anyone who never opted in, and the top 10 percent would then describe the people who answered a form rather than the people about to leave.

The balancing test is why the interest is legitimate rather than merely convenient. The score uses purchase aggregates, not email, age band, zip code, or search text. A customer who objects is removed by the erasure steps below, and the score file is not a marketing list that gets sold. The data is not a special category.

### Data minimization

Training uses the 11 columns in `FEATURE_COLUMNS` in `models/churn/churn_model.py`: recency, tenure, purchase counts at 30, 90, and 180 days, order value, 90-day spend, lifetime value, basket size, category diversity, and the online-to-store ratio. The label is `churn_label`. `customer_id` is the join key and is removed with `$[1:]` before the model sees the row.

Considered and left out:

- Hashed email, `age_band`, `state`, and `zip_code`. They identify a person and do not measure whether the next 90 days will be silent.
- Clickstream, including `search_query`. Queries sometimes contain an email, and about 35 percent of events have no `customer_id`.
- Raw `payment_method`, `promotion_code`, `device_type`, and `store_id`. The useful part of those fields is already in the spend, basket, and channel aggregates.
- `loyalty_tier`. It is kept on the feature row for the fairness slice check. It is not a model input.

### Right to erasure

NorthStar receives a deletion request for `customer_id` `C00123456`. The bucket is versioned, so a delete that omits the version id only writes a marker. The old bytes stay until every version is deleted.

**(a) Raw S3.** `raw/customers/` and `processed/customers/` are shared files, not one key per customer. Rewrite each object without rows for `C00123456`. Then list versions and delete every version id:

```bash
aws s3api list-object-versions --bucket northstar-dev-data-998631802064 --prefix raw/customers/
aws s3api delete-object --bucket northstar-dev-data-998631802064 --key <key> --version-id <version-id>
```

Do the same for `processed/customers/`. Do not wait for a lifecycle rule.

**(b) Feature Store.** The online store and the offline store are different deletes. Online, remove the current record from `northstar-dev-customer-features`:

```bash
aws sagemaker-featurestore-runtime delete-record \
  --feature-group-name northstar-dev-customer-features \
  --record-identifier-value-as-string C00123456 \
  --event-time <utc-timestamp>
```

Offline, `DeleteRecord` does nothing to the parquet under `features/customers/` and `features/offline-store/`. That store is append-only. Rewrite the parts so no row has this `customer_id`, then delete every current and noncurrent version of the old parts. The `expire-feature-versions` rule waits 60 days. An erasure request does not.

**(c) Model training data.** Drop `C00123456` from the next training extract, run the pipeline again, and approve the new package only if it still meets the metrics bar. Delete every version of the old `model.tar.gz` under `artifacts/training/`. The customer is not a row in the booster. The weights are a fit over the training rows, so there is no key to delete inside `xgboost-model`.

**(d) Inference logs.** The score files at `artifacts/batch/incumbent-scores/` and `artifacts/batch/candidate-scores/` are one CSV for all 9,999 customers. Rewrite them without `C00123456` and delete every version of the old objects. Do the same for any object under `datacapture/`. The 7-day capture rule only expires a current object later, and the 1-day noncurrent rule only cleans versions after that. The request is due now.

The hardest step is (c), the trained model. Steps (a), (b) online, and (d) are rewrites or a `DeleteRecord`: the customer is still a row or a key. The booster is not. Removing one customer from it means training a new model without that row and discarding the old artifact. Until that new artifact is the one in the registry, the customer is still in the model. The offline feature store is the same kind of problem in a milder form, because its history is append-only and a delete there is a rewrite plus a version purge, not an in-place removal. The model is harder because even a perfect rewrite of the training files leaves the information in the weights.
