variable "cluster_identifier" {
  type = string
}

variable "function" {
  type = string
}

variable "data_classification" {
  type    = string
  default = "Restricted"

  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
    error_message = "data_classification must be one of Public, Internal, Confidential, Restricted."
  }
}

variable "engine_version" {
  type = string
}

variable "parameter_group_family" {
  type = string
}

variable "database_name" {
  type = string
}

variable "master_username" {
  type = string
}

variable "master_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "master_password_version" {
  type = number
}

variable "port" {
  type    = number
  default = 5432
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Aurora requires subnets in at least two Availability Zones."
  }
}

variable "allowed_security_group_ids" {
  type = map(string)
}

variable "kms_key_arn" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "instance_count" {
  type = number

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15
    error_message = "instance_count must be between 1 and 15."
  }
}

variable "serverless_v2_scaling" {
  type = object({
    min_capacity             = number
    max_capacity             = number
    seconds_until_auto_pause = optional(number)
  })
  default = null
}

variable "storage_type" {
  type    = string
  default = null

  validation {
    condition     = var.storage_type == null || var.storage_type == "aurora-iopt1"
    error_message = "storage_type must be null (Aurora Standard) or aurora-iopt1."
  }
}

variable "backup_retention_period" {
  type = number

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35."
  }
}

variable "preferred_backup_window" {
  type = string
}

variable "preferred_maintenance_window" {
  type = string
}

variable "deletion_protection" {
  type = bool
}

variable "monitoring_interval" {
  type = number

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 1, 5, 10, 15, 30, 60."
  }
}

variable "performance_insights_retention_period" {
  type    = number
  default = 7
}

variable "log_retention_in_days" {
  type = number
}

variable "cluster_parameters" {
  type = map(object({
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = {}
}

variable "tags" {
  type = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "Project", "Owner", "Version"] : contains(keys(var.tags), k)])
    error_message = "tags must include Environment, Project, Owner and Version."
  }
}
