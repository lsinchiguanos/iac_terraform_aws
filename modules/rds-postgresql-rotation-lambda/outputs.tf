output "function_arn" {
  value = data.aws_lambda_function.this.arn

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_vpc_endpoint.secretsmanager,
    aws_vpc_security_group_egress_rule.postgresql,
    aws_vpc_security_group_egress_rule.https,
    aws_vpc_security_group_ingress_rule.db_from_rotation,
  ]
}

output "role_arn" {
  value = data.aws_lambda_function.this.role
}

output "security_group_id" {
  value = aws_security_group.this.id
}
