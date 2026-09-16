## ADR-001: NorthStar Platform Foundation

### Status
Accepted

### Context
I am laying the foundation for NorthStar's shared AI platform. The company needs three systems on one stack: a churn model, an LLM that writes personalized retention offers, and a customer-service agent. They all read the same customer and order data, including PII, so this is something shared that I need to work on. The storage has to be the same too. I cannot have different storages because then we are not going to be able to modify it from different storages, so is necessary to share the storage so everything is consistent regardless of the model.

### Decision
I created VPC `northstar-dev-vpc` (`10.0.0.0/16`) with one public subnet in `us-east-1a` (`10.0.100.0/24`), an Internet Gateway, a `0.0.0.0/0` route to that, and security group. Studio sits in that subnet in Lab 1 so that I can pull ECR images and reach S3 without a Gateway. The SG exists because a the churn probabilities must not be reachable from the public internet.

Storage is one versioned and public-access-blocked bucket with `raw/` which is all the data, `processed/` has all of the cleaned data, `features/` contain the features for the models, and `artifacts/` contains the models and the evaluations. Scoring and offer generation both read `features/`, and the agent will read `processed/` order status.

Identity is SageMaker-trusted role `northstar-dev-MLEngineer`. It may run training, endpoints, and Studio apps, pull ECR, write logs, and read/write only `artifacts/` and `features/`. Writes to `raw/` and `processed/` are denied. The IDE is SageMaker Studio Domain `northstar-dev-domain`, IAM auth, profile `MLEngineer`, kernel `ml.t3.medium`.

### Consequences
#### What this makes easy
We can have weekly jobs and provide this to the RAG model we will create. Also having everything shared makes everything consisten and IAM makes everything secure so that roles and permissions are only provided for certain people.

#### What this makes harder
Lab 1 Studio has a public IP, which will fail a production privacy review for GDPR/CCPA scoring until Lab 2’s private subnet exists at least for now.  MLEngineer cannot repair a corrupt `raw/` object until DataEngineer exists. As of right now, everything that we havent done in roles, is not completed so there are a lot of gaps to fix. 

#### What would cause you to revisit this decision
Changing roles or sharing new things will make me revisit this decision.

### Alternative Considered
I first consider to have each s3 bucket for each project, but looking at the dependecies of those I was able to see that we might need to have a shared s3 so that everything is consistent. I rejected that because of inconsistency and dependency of the models' storage.

### AWS Service Selection
- **Networking isolation model:** A custom VPC (`10.0.0.0/16`) rather than the default VPC, so the SageMaker security group admits only what is necessary and does not have a public gateway. This is good for privacy and legal reasons. 
- **Storage design:** One S3 bucket with `raw/`, `processed/`, `features/`, and `artifacts/` so all models have one resource and consistency.
- **Identity model:** A SageMaker-trusted `MLEngineer` role that can write `features/` and `artifacts/` but not `raw/`, so a notebook cannot destroy original data.
- **ML development environment:** SageMaker Studio (IAM Domain, `ml.t3.medium`) rather than laptop notebooks or Notebook Instances, so churn, LLM/RAG offers, and the service agent share one VPC, one role, and one IDE.
