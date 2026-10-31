account_id  = "891377129462"
region      = "us-east-1"
environment = "prod"
project     = "deuna-transactional-platform"
owner       = "cloud-infrastructure"

vpc_name         = "deuna-prod-vpc"
data_subnet_tier = "private-data"

terraform_deployer_role_name   = "deuna-prod-github-terraform-deployer"
security_break_glass_role_name = "deuna-security-break-glass"
dba_role_names                 = ["deuna-prod-dba-operator"]

transaction_records_writer_role_names = [
  "deuna-prod-ecs-payments-processor-task",
  "deuna-prod-ecs-transaction-ledger-task",
]

db_client_security_group_names = [
  "deuna-prod-ecs-payments-processor-sg",
  "deuna-prod-ecs-transaction-ledger-sg",
  "deuna-prod-ecs-onboarding-sg",
]

kms = {
  rotation_period_in_days = 365
  deletion_window_in_days = 30
}

transaction_records_bucket = {
  current_version_transitions = [
    { days = 30, storage_class = "STANDARD_IA" },
    { days = 180, storage_class = "GLACIER_IR" },
    { days = 730, storage_class = "DEEP_ARCHIVE" },
  ]
  current_version_expiration_days    = 3650
  noncurrent_version_transition      = { days = 30, storage_class = "GLACIER_IR" }
  noncurrent_version_expiration_days = 365
  newer_noncurrent_versions          = 5
  object_lock                        = { mode = "GOVERNANCE", days = 365 }
}

aurora = {
  engine_version                        = "16.6"
  parameter_group_family                = "aurora-postgresql16"
  instance_class                        = "db.r7g.large"
  instance_count                        = 2
  backup_retention_period               = 35
  preferred_backup_window               = "06:00-07:00"
  preferred_maintenance_window          = "sun:07:30-sun:08:30"
  deletion_protection                   = true
  monitoring_interval                   = 30
  performance_insights_retention_period = 7
  log_retention_in_days                 = 365
}

pgadmin_password_version = 1

pgadmin_secret = {
  recovery_window_in_days      = 30
  rotation_schedule_expression = "cron(0 9 ? * SUN#1 *)"
  rotation_window_duration     = "2h"
}

rotation_lambda = {
  create_secretsmanager_vpc_endpoint = true
  log_retention_in_days              = 90
}
