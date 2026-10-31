locals {
  name_prefix = "deuna-${var.environment}"

  common_tags = {
    Environment = var.environment
    Project     = var.project
    Owner       = var.owner
    Version     = var.release_version
  }

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  aurora_cluster_identifier = "${local.name_prefix}-aurora-transactions"
  rotation_function_name    = "${local.name_prefix}-pgadmin-rotation"

  deployer_role_arn            = data.aws_iam_role.terraform_deployer.arn
  break_glass_role_arn         = data.aws_iam_role.security_break_glass.arn
  dba_role_arns                = [for r in data.aws_iam_role.dba : r.arn]
  transaction_writer_role_arns = [for r in data.aws_iam_role.transaction_records_writers : r.arn]

  platform_administrator_arns = [local.deployer_role_arn, local.break_glass_role_arn]

  db_client_security_group_ids = {
    for name, sg in data.aws_security_group.db_clients : name => sg.id
  }
}
