# Wire the four modules together. Names are built from var.project and
# var.environment inside each module — nothing here hardcodes them either.

module "vpc" {
  source              = "../../modules/vpc"
  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
}

module "storage" {
  source      = "../../modules/storage"
  project     = var.project
  environment = var.environment
}

module "iam" {
  source      = "../../modules/iam"
  project     = var.project
  environment = var.environment
}

module "feature_store" {
  source                 = "../../modules/feature_store"
  project                = var.project
  environment            = var.environment
  data_engineer_role_arn = module.iam.data_engineer_role_arn
  bucket_name            = module.storage.bucket_name
}

module "glue" {
  source                 = "../../modules/glue"
  project                = var.project
  environment            = var.environment
  data_engineer_role_arn = module.iam.data_engineer_role_arn
  bucket_name            = module.storage.bucket_name
  vpc_id                 = module.vpc.vpc_id
  private_subnet_id      = module.vpc.private_subnet_id
  availability_zone      = var.availability_zone
  transform_script_path  = "${path.module}/../../../glue-scripts/transform.py"
  feature_script_path    = "${path.module}/../../../glue-scripts/feature_engineer.py"
  feature_group_name     = module.feature_store.feature_group_name
  aws_region             = var.aws_region
}

module "sagemaker" {
  source             = "../../modules/sagemaker"
  project            = var.project
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = [module.vpc.private_subnet_id]
  security_group_ids = [module.vpc.security_group_id]
  execution_role_arn = module.iam.ml_engineer_role_arn
  instance_type      = var.sagemaker_instance_type
}
