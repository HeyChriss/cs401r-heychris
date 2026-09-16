# Monthly Cost Estimate

This is after Free Tier, so it is what I would pay if I kept the same habits all month. The SageMaker Domain, VPC, and IAM role do not have an hourly charge; the bill is the kernel, storage, and a little data transfer.


| Component             | Monthly Estimate | Assumptions?                                                                                                                     | One Optimization                                                                                                                          |
| --------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| SageMaker Studio      | $2.00            | `ml.t3.medium` at **$0.05/hour**. I assume **2 hours/day** on **20 lab days** (40 hours).                                        | Shut the kernel down after every session instead of leaving it up 24/7. 730 hours × $0.05 = **$36.50**. Shutdown saves **~$34.50/month**. |
| S3 storage            | $0.46            | Data bucket `northstar-dev-data-*`. I assume **20 GB** of prefixes and lab files at **$0.023/GB-month**.                         | Lifecycle rule: move objects older than 30 days to S3 Standard-IA (~$0.0125/GB). On 20 GB that is about **$0.21/month** saved.            |
| Internet Gateway      | $0.15            | The IGW has no hourly fee. I assume **15 GB** of Studio UI plus image pulls at the lab rate of **$0.01/GB**.                     | Work in LocalStack (`make local-validate`) for Terraform checks so I do not pull SageMaker images from ECR every debug cycle.             |
| DynamoDB (state lock) | $0.01            | Table `northstar-tfstate-lock`, on-demand. A lock is a couple of reads/writes per `plan`/`apply`. Near zero; I round to a penny. | Keep on-demand. Provisioned capacity would cost more at this volume.                                                                      |
| S3 state bucket       | $0.02            | Bucket `northstar-tfstate-*`. State file is small. I assume **1 GB** (with versions) at **$0.023/GB**.                           | Do not store AMIs or datasets in the state bucket. State only.                                                                            |
| **Total**             | **$2.64**        |                                                                                                                                  | Biggest lever: Studio shutdown (**~$34.50**).                                                                                             |




## How I got the numbers ( just for interpretability) 

- **Studio:** AWS lists `ml.t3.medium` at $0.05/hour in `us-east-1`. 2 × 20 × 0.05 = $2.00. The first 250 hours across two months are free on the SageMaker Free Tier; I left that out so the table is steady-state, not the first-month discount.
- **S3 data:** $0.023/GB is the Calculator Standard storage rate the lab quotes. 20 GB is a guess...
- **IGW:** Calculator treats the gateway as $0. I used $0.01/GB as the assignment table says. Real public IPv4 data-out in `us-east-1` is closer to $0.09/GB; if I used that, 15 GB would be $1.35 and the total would be about **$3.84**.

