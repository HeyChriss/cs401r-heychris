variable "project" {
  description = "Project name, used as the first element of every resource name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "data_engineer_role_arn" {
  description = "IAM role the crawler and ETL jobs assume"
  type        = string
}

variable "bucket_name" {
  description = "Data bucket that holds raw, processed, features, and artifacts"
  type        = string
}

variable "vpc_id" {
  description = "VPC where Glue workers place their network interfaces"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet for Glue job workers"
  type        = string
}

variable "availability_zone" {
  description = "Availability Zone of the private subnet"
  type        = string
}

variable "transform_script_path" {
  description = "Local path to the transform script uploaded to artifacts/glue/"
  type        = string
}

variable "raw_customers_prefix" {
  description = "S3 prefix the raw crawler scans, without a leading slash"
  type        = string
  default     = "raw/customers"
}

variable "processed_customers_prefix" {
  description = "S3 prefix the transform job writes Parquet to, without a leading slash"
  type        = string
  default     = "processed/customers"
}

variable "catalog_table_name" {
  description = "Catalog table the crawler registers. With no table prefix this matches the last folder of the raw prefix."
  type        = string
  default     = "customers"
}

variable "script_key" {
  description = "S3 key where the transform script is uploaded"
  type        = string
  default     = "artifacts/glue/transform.py"
}

variable "feature_script_path" {
  description = "Local path to the feature engineering script uploaded to artifacts/glue/"
  type        = string
}

variable "feature_script_key" {
  description = "S3 key where the feature engineering script is uploaded"
  type        = string
  default     = "artifacts/glue/feature_engineer.py"
}

variable "feature_group_name" {
  description = "SageMaker Feature Group the feature engineering job writes to"
  type        = string
}

variable "aws_region" {
  description = "Region passed to the Feature Store runtime client"
  type        = string
}

variable "features_customers_prefix" {
  description = "S3 prefix the feature engineering job writes. Separate from the offline store prefix."
  type        = string
  default     = "features/customers"
}
