variable "function_name" {
  type = string

  validation {
    condition     = length(var.function_name) <= 40
    error_message = "function_name must be at most 40 characters to keep the generated CloudFormation names within IAM limits."
  }
}

variable "application_version" {
  type    = string
  default = null
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "db_security_group_id" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "create_secretsmanager_vpc_endpoint" {
  type = bool
}

variable "kms_key_arn" {
  type = string
}

variable "log_retention_in_days" {
  type = number
}

variable "tags" {
  type = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "Project", "Owner", "Version"] : contains(keys(var.tags), k)])
    error_message = "tags must include Environment, Project, Owner and Version."
  }
}
