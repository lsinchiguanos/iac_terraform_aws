variable "name" {
  type = string
}

variable "description" {
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

variable "administrator_arns" {
  type = list(string)

  validation {
    condition     = length(var.administrator_arns) > 0
    error_message = "At least one key administrator is required to avoid locking the key."
  }
}

variable "service_user_arns" {
  type = list(string)
}

variable "via_services" {
  type = list(string)

  validation {
    condition     = alltrue([for s in var.via_services : contains(["s3", "rds", "secretsmanager", "sqs", "lambda", "ec2"], s)])
    error_message = "via_services only accepts s3, rds, secretsmanager, sqs, lambda or ec2."
  }
}

variable "cloudwatch_logs_log_group_arns" {
  type    = list(string)
  default = []
}

variable "rotation_period_in_days" {
  type    = number
  default = 365

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "rotation_period_in_days must be between 90 and 2560."
  }
}

variable "deletion_window_in_days" {
  type    = number
  default = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  type = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "Project", "Owner", "Version"] : contains(keys(var.tags), k)])
    error_message = "tags must include Environment, Project, Owner and Version."
  }
}
