## Pipeline Stage Mapping

For this lab, I used AWS CodePipeline to run the project’s build and model workflow. The pipeline is set up in pipeline.yaml, and buildspec.yml defines the steps that run during the build. I chose CodePipeline because the training job, model registry, approval process, and build alerts were already set up in AWS. Using GitHub Actions would have meant running those steps from outside the AWS account.

The pipeline has three stages: Source, Build, and Manual Approval. The Build stage handles several phases in one place, which lets the tests, training job, and evaluation share the same files.
Source is CodePipeline gets the project code from GitHub.
Test is the build runs the data and feature tests. If they fail, the build stops before training or registering a model.
Build and train is when the pipeline sets up and runs the churn model training job. I used managed spot training because the account did not have an on-demand training quota.
Register part after training, the model is added to the model registry and waits for approval.
Evaluate: the build checks the model’s performance and fairness metrics. The fairness check reports a concern, but it does not fail the build. If a separate build check fails, the package is marked as rejected.

I also tested what happens when the tests fail. In that run, the pipeline stopped during the test phase, before training began, and no new model package was registered.

The successful run completed all build phases and passed the tests. The new model package is waiting for manual approval, while the previous approved model remains the current champion.

## Champion-Challenger
I compare each new model, or challenger, with the current champion. The challenger can move forward if its AUC is no more than 0.02 below the champion’s. In the final successful build, both models had an AUC of 0.7854, so the challenger passed that check.

The model also needs to meet the other promotion requirements for precision, recall, and confidence in its lift results. Passing the checks does not automatically replace the champion: a person still needs to approve the model. Until then, version 4 remains the approved champion.
## Retraining Triggers
I designed two ways to start the pipeline again. They both use the same process to test, train, evaluate, and register a model. These triggers are planned but have not been deployed.

- Weekly schedule: Amazon EventBridge Scheduler, `cron(0 13 ? * SUN *)`, starts `northstar-pipeline` every Sunday at 13:00 UTC.
- Performance drop: SageMaker Model Monitor scores production traffic daily and publishes `NorthStar/Production` `auc_roc`. A CloudWatch alarm starts the pipeline if that AUC stays below 0.70 for a full day. The champion’s AUC is 0.7854, so 0.70 is a real drop.

## DataOps Maturity

Current level: 2

I have automated parts of the data preparation process. Code transforms the raw customer data into processed data and features, and I have tests that check the data. In the successful build, all 28 data tests passed. I also tested a failure case: when a test failed, the pipeline stopped before training a model.

## MLOps Maturity

My top priority: Set up an automatic workflow that runs the data transformation and feature engineering jobs when new customer data arrives, then checks the results with the tests I already have.
MLOps Maturity
Current level: 2

I have a pipeline that trains and evaluates new models, tracks experiment results, and registers models for review. The latest candidate matched the champion’s AUC, though the evaluation also flagged a fairness gap between customer groups. That warning did not stop the build. A person must approve a model before it can become the champion.

To reach Level 3, I need to deploy an approved model to a live endpoint. The deployment step is not in place yet, so there is no production endpoint reporting performance. That also means the planned performance monitoring and automatic retraining trigger cannot run yet.

My top priority: Add the deployment step for approved models, then monitor the live model’s performance so the pipeline can respond if it drops.