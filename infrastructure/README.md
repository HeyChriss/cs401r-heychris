# infrastructure/

Terraform for the NorthStar platform. Lab 1 modules are the VPC, bucket,
MLEngineer role, and SageMaker domain. Lab 2 extends those modules and adds
`modules/glue/` and `modules/feature_store/`. The root README has the
end-to-end pipeline.

`terraform fmt` and `terraform validate` must pass on submit:

```bash
cd environments/dev
terraform init
terraform fmt -check -recursive ../..   # no output = pass
terraform validate                      # exits 0
```

## Layout

```
modules/vpc/            public subnet, private subnet, NAT gateway, routes, SageMaker security group
modules/storage/        data bucket, encryption, versioning, five lifecycle rules
modules/iam/            MLEngineer, DataEngineer, ModelMonitor
modules/sagemaker/      domain in the private subnet, MLEngineer user profile
modules/glue/           catalog, raw crawler, network connection, transform job, feature job
modules/feature_store/  customer feature group, online store and offline store
```

Each module contains **only** its designated resources — that is graded.

## The rule that catches people

**No hardcoded names.** The rubric runs:

```bash
grep -rn '"northstar-dev"' infrastructure/modules/
```

and expects nothing. Build names from `var.project` and `var.environment`
(`"${var.project}-${var.environment}-data"`), and give every variable a
`description` — that is also graded.
