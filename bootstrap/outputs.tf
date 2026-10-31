output "state_bucket" {
  value = module.terraform_state_bucket.bucket_id
}

output "state_kms_key_arn" {
  value = module.terraform_state_key.key_arn
}

output "state_kms_alias_arn" {
  value = module.terraform_state_key.alias_arn
}
