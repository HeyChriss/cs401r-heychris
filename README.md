# NorthStar platform

CS 401R repository for the NorthStar ML platform. Lab 1 built the VPC, data bucket, MLEngineer role, and SageMaker domain. Lab 2 puts SageMaker in a private subnet, adds the data and monitoring roles, and runs the path from raw transactions to Feature Store.

Resource names are built from `project` and `environment`. Nothing under `infrastructure/modules/` hardcodes `northstar-dev`.

## Modules

| Module | What it owns |
|---|---|
| `modules/vpc` | VPC, public subnet, private subnet `10.0.1.0/24`, internet gateway, NAT gateway, route tables, SageMaker security group. `enable_nat_gateway` is false in the local environment. |
| `modules/storage` | Versioned, encrypted data bucket and the five lifecycle rules. `enable_lifecycle_rules` is false in the local environment. |
| `modules/iam` | `MLEngineer`, `DataEngineer`, and `ModelMonitor`. DataEngineer writes `raw/`, `processed/`, and `features/` and can only read `artifacts/glue/`. ModelMonitor reads `artifacts/` and writes CloudWatch metrics. |
| `modules/sagemaker` | Studio domain in the private subnet with `app_network_access_type = VpcOnly`, and the MLEngineer user profile. |
| `modules/glue` | Catalog database, raw crawler, network connection, transform job, and feature-engineering job. Scripts are uploaded to `artifacts/glue/` on apply. |
| `modules/feature_store` | Feature group `customer-features`: 16 features, online store on, offline store at `features/offline-store/`. |

## Apply

```bash
cd infrastructure/environments/dev
terraform init
terraform apply
```

LocalStack checks the VPC, bucket, and the three IAM roles, and it confirms no NAT gateway was created locally. SageMaker and Glue are not part of that check.

```bash
make local-validate LOCAL_OUT=docs/lab2-localstack-output.txt
```

## Data pipeline

Run these after `terraform apply`, from the repo root. The account id comes from STS, and the bucket name is `northstar-dev-data-<account-id>`.

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="northstar-dev-data-${ACCOUNT}"

aws s3 cp northstar-raw-sample.csv "s3://${BUCKET}/raw/customers/northstar-raw-sample.csv"

aws glue start-crawler --name northstar-dev-raw-crawler
aws glue get-crawler --name northstar-dev-raw-crawler --query 'Crawler.State'

aws glue start-job-run --job-name northstar-dev-transform
aws glue start-job-run --job-name northstar-dev-feature-engineer
```

Wait until each crawler state returns to `READY` and each job run is `SUCCEEDED` before starting the next step. The crawler registers `northstar_dev.customers`. The transform job writes Parquet to `processed/customers/`, one row per transaction. The feature job writes one labeled row per customer to `features/customers/` and calls Feature Store `PutRecord` on `northstar-dev-customer-features`.

`bash scripts/verify-lab2.sh` checks the same assertions the rubric uses.

## Teardown

The NAT gateway bills about $0.045 per hour until it is deleted. `terraform destroy` alone leaves Glue network interfaces, the Studio EFS volume, and other resources behind.

```bash
bash scripts/teardown-lab2.sh
```

The script writes `docs/lab2-destroy-output.txt` and checks that no billable platform resources remain. The Terraform state bucket is kept.
