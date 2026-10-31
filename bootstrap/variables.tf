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

variable "terraform_deployer_role_name" {
  type = string
}

variable "security_break_glass_role_name" {
  type = string
}

variable "state_noncurrent_version_expiration_days" {
  type = number
}
