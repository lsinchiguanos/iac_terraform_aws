data "aws_iam_role" "terraform_deployer" {
  name = var.terraform_deployer_role_name
}

data "aws_iam_role" "security_break_glass" {
  name = var.security_break_glass_role_name
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    Owner       = var.owner
    Version     = var.release_version
  }

  administrator_arns = [
    data.aws_iam_role.terraform_deployer.arn,
    data.aws_iam_role.security_break_glass.arn,
  ]
}

module "terraform_state_key" {
  source = "../modules/kms-key"

  name                    = "deuna-${var.environment}-terraform-state"
  description             = "Encrypts Terraform state objects for the deuna ${var.environment} account"
  function                = "terraform-state-encryption"
  data_classification     = "Confidential"
  administrator_arns      = local.administrator_arns
  service_user_arns       = local.administrator_arns
  via_services            = ["s3"]
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

module "terraform_state_bucket" {
  source = "../modules/s3-bucket"

  bucket_name                            = "deuna-${var.environment}-terraform-state-${var.account_id}"
  function                               = "terraform-state-storage"
  data_classification                    = "Confidential"
  kms_key_arn                            = module.terraform_state_key.key_arn
  kms_alias_arn                          = module.terraform_state_key.alias_arn
  privileged_principal_arns              = local.administrator_arns
  noncurrent_version_expiration_days     = var.state_noncurrent_version_expiration_days
  newer_noncurrent_versions              = 20
  abort_incomplete_multipart_upload_days = 1
  tags                                   = local.common_tags
}
