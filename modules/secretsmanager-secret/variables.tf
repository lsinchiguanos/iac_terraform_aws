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

variable "kms_key_arn" {
  type = string
}

variable "recovery_window_in_days" {
  type = number

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "recovery_window_in_days must be between 7 and 30."
  }
}

variable "secret_attributes" {
  type = map(string)
}

variable "secret_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "secret_value_version" {
  type = number
}

variable "administrator_arns" {
  type = list(string)

  validation {
    condition     = length(var.administrator_arns) > 0
    error_message = "At least one administrator is required to manage the secret."
  }
}

variable "reader_arns" {
  type = list(string)
}

variable "rotation_lambda_arn" {
  type = string
}

variable "rotation_schedule_expression" {
  type = string
}

variable "rotation_window_duration" {
  type = string
}

variable "tags" {
  type = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "Project", "Owner", "Version"] : contains(keys(var.tags), k)])
    error_message = "tags must include Environment, Project, Owner and Version."
  }
}
