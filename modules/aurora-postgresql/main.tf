data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  default_cluster_parameters = {
    "rds.force_ssl"                       = { value = "1", apply_method = "immediate" }
    "ssl_min_protocol_version"            = { value = "TLSv1.2", apply_method = "immediate" }
    "shared_preload_libraries"            = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "pgaudit.log"                         = { value = "ddl,role", apply_method = "immediate" }
    "log_min_duration_statement"          = { value = "1000", apply_method = "immediate" }
    "log_connections"                     = { value = "1", apply_method = "immediate" }
    "log_disconnections"                  = { value = "1", apply_method = "immediate" }
    "log_lock_waits"                      = { value = "1", apply_method = "immediate" }
    "idle_in_transaction_session_timeout" = { value = "300000", apply_method = "immediate" }
  }

  cluster_parameters = merge(local.default_cluster_parameters, var.cluster_parameters)
}

resource "aws_db_subnet_group" "this" {
  name        = var.cluster_identifier
  description = "Private data-tier subnets for ${var.cluster_identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name       = var.cluster_identifier
    Function   = "database-subnet-placement"
    IsMonetary = "False"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.cluster_identifier}-sg"
  description = "PostgreSQL ingress to ${var.cluster_identifier} from authorized workloads only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name       = "${var.cluster_identifier}-sg"
    Function   = "database-network-access"
    IsMonetary = "False"
  })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = var.allowed_security_group_ids

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "PostgreSQL from ${each.key}"

  tags = merge(var.tags, {
    Name       = "${var.cluster_identifier}-from-${each.key}"
    Function   = "database-network-access"
    IsMonetary = "False"
  })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${var.cluster_identifier}-"
  family      = var.parameter_group_family
  description = "Hardened ${var.parameter_group_family} parameters for ${var.cluster_identifier}"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, {
    Name       = "${var.cluster_identifier}-${var.parameter_group_family}"
    Function   = "database-engine-configuration"
    IsMonetary = "False"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/cluster/${var.cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name       = "${var.cluster_identifier}-postgresql-logs"
    Function   = "database-log-retention"
    IsMonetary = "True"
  })
}

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  name               = "${var.cluster_identifier}-enhanced-monitoring"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume.json

  tags = merge(var.tags, {
    Name       = "${var.cluster_identifier}-enhanced-monitoring"
    Function   = "database-os-metrics-publisher"
    IsMonetary = "False"
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = var.cluster_identifier
  engine                              = "aurora-postgresql"
  engine_mode                         = "provisioned"
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  master_password_wo                  = var.master_password
  master_password_wo_version          = var.master_password_version
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.this.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  delete_automated_backups            = false
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.cluster_identifier}-final"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  allow_major_version_upgrade         = false
  apply_immediately                   = false

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless_v2_scaling != null ? [var.serverless_v2_scaling] : []

    content {
      min_capacity             = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity             = serverlessv2_scaling_configuration.value.max_capacity
      seconds_until_auto_pause = serverlessv2_scaling_configuration.value.seconds_until_auto_pause
    }
  }

  tags = merge(var.tags, {
    Name               = var.cluster_identifier
    Function           = var.function
    IsMonetary         = "True"
    DataClassification = var.data_classification
  })

  depends_on = [aws_cloudwatch_log_group.postgresql]
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier                            = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.this.id
  engine                                = aws_rds_cluster.this.engine
  engine_version                        = aws_rds_cluster.this.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.this.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  promotion_tier                        = count.index
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period
  copy_tags_to_snapshot                 = true
  apply_immediately                     = false

  tags = merge(var.tags, {
    Name               = "${var.cluster_identifier}-${count.index + 1}"
    Function           = "${var.function}-instance"
    IsMonetary         = "True"
    DataClassification = var.data_classification
  })

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}
