# Recreates the A4 Domain and MLEngineer user profile.
# retention_policy Delete is required so terraform destroy can remove the
# hidden Studio EFS volume; Retain leaves it behind and destroy hangs.

resource "aws_sagemaker_domain" "this" {
  domain_name = "${var.project}-${var.environment}-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  # VpcOnly sends Studio egress through the NAT gateway, not the internet gateway.
  app_network_access_type = "VpcOnly"

  default_user_settings {
    execution_role  = var.execution_role_arn
    security_groups = var.security_group_ids

    sharing_settings {
      notebook_output_option = "Disabled"
    }

    jupyter_lab_app_settings {
      default_resource_spec {
        instance_type = var.instance_type
      }
    }
  }

  retention_policy {
    home_efs_file_system = "Delete"
  }

  tags = {
    Name = "${var.project}-${var.environment}-domain"
  }
}

resource "aws_sagemaker_user_profile" "ml_engineer" {
  domain_id         = aws_sagemaker_domain.this.id
  user_profile_name = "MLEngineer"

  user_settings {
    execution_role = var.execution_role_arn
  }
}
