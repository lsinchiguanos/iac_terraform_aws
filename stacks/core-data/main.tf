ephemeral "random_password" "pgadmin" {
  length           = 32
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
  min_special      = 4
  override_special = "!#%^*()-_=+[]{}:?"
}

module "pgadmin_rotation_lambda" {
  source = "../../modules/rds-postgresql-rotation-lambda"

  function_name                      = local.rotation_function_name
  application_version                = var.rotation_lambda.application_version
  vpc_id                             = data.aws_vpc.this.id
  subnet_ids                         = data.aws_subnets.data.ids
  db_security_group_id               = module.aurora_transactions.security_group_id
  db_port                            = module.aurora_transactions.port
  create_secretsmanager_vpc_endpoint = var.rotation_lambda.create_secretsmanager_vpc_endpoint
  kms_key_arn                        = module.data_at_rest_key.key_arn
  log_retention_in_days              = var.rotation_lambda.log_retention_in_days
  tags                               = local.common_tags
}

module "data_at_rest_key" {
  source = "../../modules/kms-key"

  name                    = "${local.name_prefix}-data-at-rest"
  description             = "Encrypts transaction records in S3, the Aurora transactions cluster and its pgadmin secret in ${var.environment}"
  function                = "data-at-rest-encryption"
  rotation_period_in_days = var.kms.rotation_period_in_days
  deletion_window_in_days = var.kms.deletion_window_in_days
  administrator_arns      = local.platform_administrator_arns

  service_user_arns = distinct(concat(
    [local.deployer_role_arn, module.pgadmin_rotation_lambda.role_arn],
    local.dba_role_arns,
    local.transaction_writer_role_arns,
  ))

  via_services = ["s3", "rds", "secretsmanager"]

  cloudwatch_logs_log_group_arns = [
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/rds/cluster/${local.aurora_cluster_identifier}/*",
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.rotation_function_name}",
  ]

  tags = local.common_tags
}

module "transaction_records_bucket" {
  source = "../../modules/s3-bucket"

  bucket_name                        = "${local.name_prefix}-transaction-records-${local.account_id}"
  function                           = "transaction-records-storage"
  kms_key_arn                        = module.data_at_rest_key.key_arn
  kms_alias_arn                      = module.data_at_rest_key.alias_arn
  privileged_principal_arns          = local.platform_administrator_arns
  current_version_transitions        = var.transaction_records_bucket.current_version_transitions
  current_version_expiration_days    = var.transaction_records_bucket.current_version_expiration_days
  noncurrent_version_transition      = var.transaction_records_bucket.noncurrent_version_transition
  noncurrent_version_expiration_days = var.transaction_records_bucket.noncurrent_version_expiration_days
  newer_noncurrent_versions          = var.transaction_records_bucket.newer_noncurrent_versions
  object_lock                        = var.transaction_records_bucket.object_lock
  tags                               = local.common_tags
}

module "aurora_transactions" {
  source = "../../modules/aurora-postgresql"

  cluster_identifier                    = local.aurora_cluster_identifier
  function                              = "transactional-database"
  engine_version                        = var.aurora.engine_version
  parameter_group_family                = var.aurora.parameter_group_family
  database_name                         = "transactions"
  master_username                       = "pgadmin"
  master_password                       = ephemeral.random_password.pgadmin.result
  master_password_version               = var.pgadmin_password_version
  vpc_id                                = data.aws_vpc.this.id
  subnet_ids                            = data.aws_subnets.data.ids
  allowed_security_group_ids            = local.db_client_security_group_ids
  kms_key_arn                           = module.data_at_rest_key.key_arn
  instance_class                        = var.aurora.instance_class
  instance_count                        = var.aurora.instance_count
  serverless_v2_scaling                 = var.aurora.serverless_v2_scaling
  storage_type                          = var.aurora.storage_type
  backup_retention_period               = var.aurora.backup_retention_period
  preferred_backup_window               = var.aurora.preferred_backup_window
  preferred_maintenance_window          = var.aurora.preferred_maintenance_window
  deletion_protection                   = var.aurora.deletion_protection
  monitoring_interval                   = var.aurora.monitoring_interval
  performance_insights_retention_period = var.aurora.performance_insights_retention_period
  log_retention_in_days                 = var.aurora.log_retention_in_days
  tags                                  = local.common_tags
}

module "pgadmin_secret" {
  source = "../../modules/secretsmanager-secret"

  name                    = "deuna/${var.environment}/aurora-transactions/pgadmin"
  description             = "Master credentials of user pgadmin for ${local.aurora_cluster_identifier}"
  function                = "database-master-credentials"
  kms_key_arn             = module.data_at_rest_key.key_arn
  recovery_window_in_days = var.pgadmin_secret.recovery_window_in_days

  secret_attributes = {
    engine              = "postgres"
    host                = module.aurora_transactions.writer_endpoint
    port                = tostring(module.aurora_transactions.port)
    dbname              = module.aurora_transactions.database_name
    username            = module.aurora_transactions.master_username
    dbClusterIdentifier = module.aurora_transactions.cluster_identifier
  }

  secret_password      = ephemeral.random_password.pgadmin.result
  secret_value_version = var.pgadmin_password_version

  administrator_arns = local.platform_administrator_arns
  reader_arns        = concat([module.pgadmin_rotation_lambda.role_arn], local.dba_role_arns)

  rotation_lambda_arn          = module.pgadmin_rotation_lambda.function_arn
  rotation_schedule_expression = var.pgadmin_secret.rotation_schedule_expression
  rotation_window_duration     = var.pgadmin_secret.rotation_window_duration

  tags = local.common_tags
}
