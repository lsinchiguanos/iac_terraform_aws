variable "bucket_name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 lowercase characters, digits or hyphens."
  }
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

variable "kms_alias_arn" {
  type = string
}

variable "privileged_principal_arns" {
  type = list(string)

  validation {
    condition     = length(var.privileged_principal_arns) > 0
    error_message = "At least one privileged principal is required to manage the bucket."
  }
}

variable "current_version_transitions" {
  type = list(object({
    days          = number
    storage_class = string
  }))
  default = []

  validation {
    condition     = alltrue([for t in var.current_version_transitions : contains(["STANDARD_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class)])
    error_message = "storage_class must be STANDARD_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER or DEEP_ARCHIVE."
  }
}

variable "current_version_expiration_days" {
  type    = number
  default = null
}

variable "noncurrent_version_transition" {
  type = object({
    days          = number
    storage_class = string
  })
  default = null
}

variable "noncurrent_version_expiration_days" {
  type = number
}

variable "newer_noncurrent_versions" {
  type    = number
  default = 3
}

variable "abort_incomplete_multipart_upload_days" {
  type    = number
  default = 7
}

variable "object_lock" {
  type = object({
    mode = string
    days = number
  })
  default = null

  validation {
    condition     = var.object_lock == null || contains(["GOVERNANCE", "COMPLIANCE"], try(var.object_lock.mode, ""))
    error_message = "object_lock.mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "tags" {
  type = map(string)

  validation {
    condition     = alltrue([for k in ["Environment", "Project", "Owner", "Version"] : contains(keys(var.tags), k)])
    error_message = "tags must include Environment, Project, Owner and Version."
  }
}
