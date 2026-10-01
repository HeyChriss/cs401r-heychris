variable "project" {
  description = "Project name, used as the first element of every resource name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "data_engineer_role_arn" {
  description = "Execution role that writes Feature Store records and the offline store"
  type        = string
}

variable "bucket_name" {
  description = "Data bucket that backs the offline store"
  type        = string
}

variable "offline_store_prefix" {
  description = "S3 prefix for the Feature Store offline store. Kept separate from the feature-engineering job output."
  type        = string
  default     = "features/offline-store"
}
