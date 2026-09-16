# Recreates the A3 MLEngineer role. Same trust and least-privilege actions as
# the console policy. Object writes are only artifacts/ and features/, never raw/.

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
