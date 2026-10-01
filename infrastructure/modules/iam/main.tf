# MLEngineer (Lab 1), plus DataEngineer and ModelMonitor (Lab 2).
# Object writes for MLEngineer stay on artifacts/ and features/, never raw/.

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ml_engineer" {
  name               = "${var.project}-${var.environment}-MLEngineer"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  description        = "SageMaker execution role for Studio and training"

  tags = {
    Name = "${var.project}-${var.environment}-MLEngineer"
  }
}

data "aws_iam_policy_document" "ml_engineer" {
  statement {
    sid = "SageMakerCore"
    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:CreateEndpoint",
      "sagemaker:DescribeEndpoint",
      "sagemaker:DeleteEndpoint",
      "sagemaker:CreateEndpointConfig",
      "sagemaker:DeleteEndpointConfig",
      "sagemaker:CreateMlflowApp",
      "sagemaker:DescribeMlflowApp",
      "sagemaker:ListMlflowApps",
      "sagemaker:CreatePresignedMlflowAppUrl",
      "sagemaker:RegisterModel",
      "sagemaker:DescribeModelPackage",
      "sagemaker:ListModelPackages",
    ]
    resources = ["*"]
  }

  statement {
    sid = "StudioSelfService"
    actions = [
      "sagemaker:DescribeDomain",
      "sagemaker:ListDomains",
      "sagemaker:DescribeUserProfile",
      "sagemaker:ListUserProfiles",
      "sagemaker:DescribeSpace",
      "sagemaker:ListSpaces",
      "sagemaker:CreateSpace",
      "sagemaker:UpdateSpace",
      "sagemaker:DeleteSpace",
      "sagemaker:DescribeApp",
      "sagemaker:ListApps",
      "sagemaker:CreateApp",
      "sagemaker:DeleteApp",
      "sagemaker:CreatePresignedDomainUrl",
      # Studio tags every space/app it creates. The lab JSON omitted this;
      # without it, CreateSpace fails with AccessDenied on sagemaker:AddTags.
      "sagemaker:AddTags",
    ]
    resources = [
      "arn:aws:sagemaker:*:*:domain/*",
      "arn:aws:sagemaker:*:*:user-profile/*",
      "arn:aws:sagemaker:*:*:space/*",
      "arn:aws:sagemaker:*:*:app/*",
    ]
  }

  statement {
    sid = "S3ArtifactsAndFeatures"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-${var.environment}-data-*/artifacts/*",
      "arn:aws:s3:::${var.project}-${var.environment}-data-*/features/*",
    ]
  }

  statement {
    sid = "S3BucketList"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = ["arn:aws:s3:::${var.project}-${var.environment}-data-*"]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/sagemaker/*"]
  }

  statement {
    sid = "ECRRead"
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ml_engineer" {
  name        = "${var.project}-${var.environment}-MLEngineer-policy"
  description = "Least-privilege policy for the MLEngineer SageMaker role"
  policy      = data.aws_iam_policy_document.ml_engineer.json
}

resource "aws_iam_role_policy_attachment" "ml_engineer" {
  role       = aws_iam_role.ml_engineer.name
  policy_arn = aws_iam_policy.ml_engineer.arn
}

# DataEngineer writes the data prefixes and Feature Store records.
# It can read job scripts under artifacts/glue/ and cannot write artifacts/.
# sagemaker.amazonaws.com is on the trust policy because CreateFeatureGroup
# rejects an execution role that does not trust SageMaker.

data "aws_iam_policy_document" "data_engineer_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "glue.amazonaws.com",
        "lambda.amazonaws.com",
        "sagemaker.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "data_engineer" {
  name               = "${var.project}-${var.environment}-DataEngineer"
  assume_role_policy = data.aws_iam_policy_document.data_engineer_assume.json
  description        = "Data-plane role for Glue jobs and Feature Store writes"

  tags = {
    Name = "${var.project}-${var.environment}-DataEngineer"
  }
}

data "aws_iam_policy_document" "data_engineer" {
  statement {
    sid = "GlueDataPlane"
    actions = [
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:BatchStopJobRun",
      "glue:CreateCrawler",
      "glue:CreateDatabase",
      "glue:CreateJob",
      "glue:CreatePartition",
      "glue:CreateTable",
      "glue:DeleteCrawler",
      "glue:DeleteDatabase",
      "glue:DeleteJob",
      "glue:DeletePartition",
      "glue:DeleteTable",
      "glue:GetConnection",
      "glue:GetConnections",
      "glue:GetCrawler",
      "glue:GetCrawlers",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetJob",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:GetJobs",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
      "glue:StartCrawler",
      "glue:StartJobRun",
      "glue:StopCrawler",
      "glue:UpdateCrawler",
      "glue:UpdateDatabase",
      "glue:UpdateJob",
      "glue:UpdatePartition",
      "glue:UpdateTable",
    ]
    resources = ["*"]
  }

  statement {
    sid = "GlueNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid = "GlueEniTags"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
  }

  statement {
    sid = "S3DataPrefixes"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-${var.environment}-data-*/raw/*",
      "arn:aws:s3:::${var.project}-${var.environment}-data-*/processed/*",
      "arn:aws:s3:::${var.project}-${var.environment}-data-*/features/*",
    ]
  }

  # Feature Store writes offline-store objects with an ACL, and it checks the
  # bucket ACL before accepting the offline store URI.
  statement {
    sid       = "S3FeatureStoreAcl"
    actions   = ["s3:PutObjectAcl"]
    resources = ["arn:aws:s3:::${var.project}-${var.environment}-data-*/features/*"]
  }

  statement {
    sid     = "S3GlueScripts"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.project}-${var.environment}-data-*/artifacts/glue/*",
    ]
  }

  statement {
    sid = "S3ListData"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketAcl",
    ]
    resources = ["arn:aws:s3:::${var.project}-${var.environment}-data-*"]
  }

  statement {
    sid = "FeatureStoreWrite"
    actions = [
      "sagemaker:PutRecord",
      "sagemaker:CreateFeatureGroup",
      "sagemaker:DescribeFeatureGroup",
    ]
    resources = ["arn:aws:sagemaker:*:*:feature-group/*"]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws-glue/*",
      "arn:aws:logs:*:*:log-group:/aws-glue/*:log-stream:*",
      "arn:aws:logs:*:*:log-group:/aws/sagemaker/*",
      "arn:aws:logs:*:*:log-group:/aws/sagemaker/*:log-stream:*",
    ]
  }
}

resource "aws_iam_policy" "data_engineer" {
  name        = "${var.project}-${var.environment}-DataEngineer-policy"
  description = "Glue, data-prefix S3, and Feature Store write access"
  policy      = data.aws_iam_policy_document.data_engineer.json
}

resource "aws_iam_role_policy_attachment" "data_engineer" {
  role       = aws_iam_role.data_engineer.name
  policy_arn = aws_iam_policy.data_engineer.arn
}

# ModelMonitor observes. It cannot write S3, invoke endpoints, or start jobs.

data "aws_iam_policy_document" "model_monitor_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "model_monitor" {
  name               = "${var.project}-${var.environment}-ModelMonitor"
  assume_role_policy = data.aws_iam_policy_document.model_monitor_assume.json
  description        = "Read-only observer for drift metrics"

  tags = {
    Name = "${var.project}-${var.environment}-ModelMonitor"
  }
}

data "aws_iam_policy_document" "model_monitor" {
  statement {
    sid = "CloudWatchMetrics"
    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DescribeAlarms",
    ]
    resources = ["*"]
  }

  statement {
    sid = "SageMakerReadDriftRuns"
    actions = [
      "sagemaker:ListProcessingJobs",
      "sagemaker:DescribeProcessingJob",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "S3ArtifactsRead"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.project}-${var.environment}-data-*/artifacts/*"]
  }

  statement {
    sid       = "S3ListArtifacts"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.project}-${var.environment}-data-*"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "artifacts/*",
        "artifacts/",
      ]
    }
  }

  statement {
    sid       = "S3BucketLocation"
    actions   = ["s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.project}-${var.environment}-data-*"]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/sagemaker/*",
      "arn:aws:logs:*:*:log-group:/aws/sagemaker/*:log-stream:*",
    ]
  }
}

resource "aws_iam_policy" "model_monitor" {
  name        = "${var.project}-${var.environment}-ModelMonitor-policy"
  description = "CloudWatch metrics and read-only access to artifacts"
  policy      = data.aws_iam_policy_document.model_monitor.json
}

resource "aws_iam_role_policy_attachment" "model_monitor" {
  role       = aws_iam_role.model_monitor.name
  policy_arn = aws_iam_policy.model_monitor.arn
}
