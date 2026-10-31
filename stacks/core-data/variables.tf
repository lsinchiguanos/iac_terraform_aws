variable "account_id" {
  type = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "project" {
  type = string
}

variable "owner" {
  type = string
}

variable "release_version" {
  type = string

  validation {
    condition     = can(regex("^[0-9]+[.][0-9]+[.][0-9]+(-[0-9A-Za-z.]+)?$", var.release_version))
    error_message = "release_version must be the Git release tag in SemVer format, e.g. 1.1.0 or 1.2.0-rc.1."
  }
}

variable "vpc_name" {
  type = string
}

variable "data_subnet_tier" {
  type = string
}

variable "terraform_deployer_role_name" {
  type = string
}

variable "security_break_glass_role_name" {
  type = string
}

variable "dba_role_names" {
  type = list(string)
}

variable "transaction_records_writer_role_names" {
  type = list(string)
}

variable "db_client_security_group_names" {
  type = list(string)
}

variable "kms" {
  type = object({
    rotation_period_in_days = number
    deletion_window_in_days = number
  })
}

variable "transaction_records_bucket" {
  type = object({
    current_version_transitions = list(object({
      days          = number
      storage_class = string
    }))
    current_version_expiration_days = optional(number)
    noncurrent_version_transition = optional(object({
      days          = number
      storage_class = string
    }))
    noncurrent_version_expiration_days = number
    newer_noncurrent_versions          = number
    object_lock = optional(object({
      mode = string
      days = number
    }))
  })
}

variable "aurora" {
  type = object({
    engine_version         = string
    parameter_group_family = string
    instance_class         = string
    instance_count         = number
    serverless_v2_scaling = optional(object({
      min_capacity             = number
      max_capacity             = number
      seconds_until_auto_pause = optional(number)
    }))
    storage_type                          = optional(string)
    backup_retention_period               = number
    preferred_backup_window               = string
    preferred_maintenance_window          = string
    deletion_protection                   = bool
    monitoring_interval                   = number
    performance_insights_retention_period = number
    log_retention_in_days                 = number
  })
}

variable "pgadmin_password_version" {
  type = number
}

variable "pgadmin_secret" {
  type = object({
    recovery_window_in_days      = number
    rotation_schedule_expression = string
    rotation_window_duration     = string
  })
}

variable "rotation_lambda" {
  type = object({
    application_version                = optional(string)
    create_secretsmanager_vpc_endpoint = bool
    log_retention_in_days              = number
  })
}
