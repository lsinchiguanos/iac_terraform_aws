account_id  = "730335476193"
region      = "us-east-1"
environment = "dev"
project     = "deuna-transactional-platform"
owner       = "cloud-infrastructure"

vpc_name         = "deuna-dev-vpc"
data_subnet_tier = "private-data"

terraform_deployer_role_name   = "deuna-dev-github-terraform-deployer"
security_break_glass_role_name = "deuna-security-break-glass"
dba_role_names                 = ["deuna-dev-dba-operator"]

transaction_records_writer_role_names = [
  "deuna-dev-ecs-payments-processor-task",
  "deuna-dev-ecs-transaction-ledger-task",
]

db_client_security_group_names = [
  "deuna-dev-ecs-payments-processor-sg",
  "deuna-dev-ecs-transaction-ledger-sg",
  "deuna-dev-ecs-onboarding-sg",
]

kms = {
  rotation_period_in_days = 365
  deletion_window_in_days = 7
}

transaction_records_bucket = {
  current_version_transitions = [
    { days = 30, storage_class = "STANDARD_IA" },
  ]
  current_version_expiration_days    = 90
  noncurrent_version_expiration_days = 7
  newer_noncurrent_versions          = 1
}

aurora = {
  engine_version         = "16.6"
  parameter_group_family = "aurora-postgresql16"
  instance_class         = "db.serverless"
  instance_count         = 1
  serverless_v2_scaling = {
    min_capacity             = 0
    max_capacity             = 4
    seconds_until_auto_pause = 3600
  }
  backup_retention_period               = 7
  preferred_backup_window               = "06:00-07:00"
  preferred_maintenance_window          = "sun:07:30-sun:08:30"
  deletion_protection                   = false
  monitoring_interval                   = 60
  performance_insights_retention_period = 7
  log_retention_in_days                 = 30
}

pgadmin_password_version = 1

pgadmin_secret = {
  recovery_window_in_days      = 7
  rotation_schedule_expression = "cron(0 9 ? * MON *)"
  rotation_window_duration     = "2h"
}

rotation_lambda = {
  create_secretsmanager_vpc_endpoint = true
  log_retention_in_days              = 14
}
