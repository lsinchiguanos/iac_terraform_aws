output "kms_key_arn" {
  value = module.data_at_rest_key.key_arn
}

output "kms_alias_name" {
  value = module.data_at_rest_key.alias_name
}

output "transaction_records_bucket" {
  value = module.transaction_records_bucket.bucket_id
}

output "aurora_writer_endpoint" {
  value = module.aurora_transactions.writer_endpoint
}

output "aurora_reader_endpoint" {
  value = module.aurora_transactions.reader_endpoint
}

output "aurora_security_group_id" {
  value = module.aurora_transactions.security_group_id
}

output "pgadmin_secret_arn" {
  value = module.pgadmin_secret.secret_arn
}

output "pgadmin_rotation_function_arn" {
  value = module.pgadmin_rotation_lambda.function_arn
}
