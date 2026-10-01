# Catalog, raw crawler, and the transform job.
# Names come from var.project and var.environment.
# Glue workers run in the private subnet, so the job needs a NETWORK
# connection whose security group allows all traffic from itself.

locals {
  database_name = replace("${var.project}_${var.environment}", "-", "_")
  name_prefix   = "${var.project}-${var.environment}"
}

resource "aws_glue_catalog_database" "this" {
  name        = local.database_name
  description = "Catalog tables for raw and processed customer data"
}

resource "aws_security_group" "glue" {
  name        = "${local.name_prefix}-glue-sg"
  description = "Glue workers - all ingress from this security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "All ports from this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Outbound to S3, Glue, and CloudWatch through the NAT gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-glue-sg"
  }
}

resource "aws_glue_connection" "network" {
  name            = "${local.name_prefix}-network"
  description     = "Places Glue workers in the private subnet"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = var.availability_zone
    security_group_id_list = [aws_security_group.glue.id]
    subnet_id              = var.private_subnet_id
  }
}

resource "aws_glue_crawler" "raw" {
  name          = "${local.name_prefix}-raw-crawler"
  description   = "Discovers the schema of raw customer CSV files"
  role          = var.data_engineer_role_arn
  database_name = aws_glue_catalog_database.this.name

  s3_target {
    path = "s3://${var.bucket_name}/${var.raw_customers_prefix}/"
  }

  tags = {
    Name = "${local.name_prefix}-raw-crawler"
  }
}

resource "aws_s3_object" "transform_script" {
  bucket = var.bucket_name
  key    = var.script_key
  source = var.transform_script_path
  etag   = filemd5(var.transform_script_path)
}

resource "aws_glue_job" "transform" {
  name         = "${local.name_prefix}-transform"
  description  = "Cast, impute, and deduplicate raw customer transactions to Parquet"
  role_arn     = var.data_engineer_role_arn
  glue_version = "4.0"

  # glueetl is the Spark runtime. Glue 4.0 runs Python 3 there.
  # python_version belongs to Python shell jobs, which cannot import pyspark.
  command {
    name            = "glueetl"
    script_location = "s3://${var.bucket_name}/${var.script_key}"
  }

  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 20
  max_retries       = 0
  execution_class   = "STANDARD"

  connections = [aws_glue_connection.network.name]

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-continuous-cloudwatch-log" = "true"
    "--database_name"                    = aws_glue_catalog_database.this.name
    "--table_name"                       = var.catalog_table_name
    "--output_path"                      = "s3://${var.bucket_name}/${var.processed_customers_prefix}/"
    "--TempDir"                          = "s3://${var.bucket_name}/processed/glue-tmp/"
  }

  depends_on = [aws_s3_object.transform_script]

  tags = {
    Name = "${local.name_prefix}-transform"
  }
}

resource "aws_s3_object" "feature_script" {
  bucket = var.bucket_name
  key    = var.feature_script_key
  source = var.feature_script_path
  etag   = filemd5(var.feature_script_path)
}

resource "aws_glue_job" "feature_engineer" {
  name         = "${local.name_prefix}-feature-engineer"
  description  = "Aggregate observation-window features and label them from the outcome window"
  role_arn     = var.data_engineer_role_arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${var.bucket_name}/${var.feature_script_key}"
  }

  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 40
  max_retries       = 0
  execution_class   = "STANDARD"

  connections = [aws_glue_connection.network.name]

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-continuous-cloudwatch-log" = "true"
    "--input_path"                       = "s3://${var.bucket_name}/${var.processed_customers_prefix}/"
    "--output_path"                      = "s3://${var.bucket_name}/${var.features_customers_prefix}/"
    "--feature_group_name"               = var.feature_group_name
    "--region"                           = var.aws_region
    "--TempDir"                          = "s3://${var.bucket_name}/features/glue-tmp/"
  }

  depends_on = [aws_s3_object.feature_script]

  tags = {
    Name = "${local.name_prefix}-feature-engineer"
  }
}
