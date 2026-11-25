"""Publish Lab 6 model and business metrics from a finished drift run.

Run this on your laptop after monitoring/run_evidently_job.py completes.
The processing container must not call PutMetricData: installing Evidently
upgrades urllib3 past the botocore pin in the sklearn image.

    python monitoring/publish_metrics.py \
        --summary monitoring/reports/drift_violations.json

DriftDetected is 1 when drift_direction() flagged any feature, else 0.
ChurnAlertVolume is the captured-record count in that summary. It is the
proxy for daily churn-alert volume: one distinct scored customer per record.
The Task 1 alarm treats a drop of more than 30 percent from this window
(500 -> below 350) as the breach until a 7-day average exists.
"""

import argparse
import json

import boto3

NAMESPACE = "NorthStar/ChurnModel"
ENDPOINT = "northstar-churn-prod"


def put_metrics(summary: dict, region: str) -> None:
    drift = 1.0 if summary["drift_detected"] else 0.0
    volume = float(summary["captured_records"])
    cloudwatch = boto3.client("cloudwatch", region_name=region)
    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {
                "MetricName": "DriftDetected",
                "Dimensions": [{"Name": "EndpointName", "Value": ENDPOINT}],
                "Value": drift,
                "Unit": "Count",
            },
            {
                "MetricName": "ChurnAlertVolume",
                "Dimensions": [{"Name": "EndpointName", "Value": ENDPOINT}],
                "Value": volume,
                "Unit": "Count",
            },
        ],
    )
    print(f"published DriftDetected={drift:g} ChurnAlertVolume={volume:g} "
          f"namespace={NAMESPACE} endpoint={ENDPOINT}")


def log_mlflow(summary: dict, app_arn: str, job_name: str) -> None:
    """Log the drift run to the serverless MLflow app. Not a tracking server."""
    import mlflow

    mlflow.set_tracking_uri(app_arn)
    mlflow.set_experiment("northstar-drift")
    with mlflow.start_run(run_name=f"drift-{job_name}"):
        mlflow.log_params({
            "baseline_records": summary["baseline_records"],
            "captured_records": summary["captured_records"],
            "variant": "champion",
        })
        for feature, detail in summary["per_feature"].items():
            mlflow.log_metric(f"{detail['method']}_{feature}", detail["value"])
        mlflow.log_metric("violation_count", summary["violation_count"])
        mlflow.log_artifact("monitoring/reports/drift_report.html")
    print(f"logged drift-{job_name} to northstar-drift")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", default="monitoring/reports/drift_violations.json")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--mlflow-arn", default=None,
                        help="Serverless SageMaker MLflow app ARN")
    parser.add_argument("--job-name", default="nsc-evidently-1795632223")
    parser.add_argument("--skip-cloudwatch", action="store_true")
    args = parser.parse_args()
    with open(args.summary, encoding="utf-8") as handle:
        summary = json.load(handle)
    if not args.skip_cloudwatch:
        put_metrics(summary, args.region)
    if args.mlflow_arn:
        log_mlflow(summary, args.mlflow_arn, args.job_name)


if __name__ == "__main__":
    main()
