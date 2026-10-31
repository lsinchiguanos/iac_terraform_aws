data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "this" {
  name        = "${var.function_name}-sg"
  description = "Egress from ${var.function_name} to Aurora PostgreSQL and the Secrets Manager endpoint"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name       = "${var.function_name}-sg"
    Function   = "secret-rotation-network-access"
    IsMonetary = "False"
  })
}

resource "aws_vpc_security_group_egress_rule" "postgresql" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.db_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  description                  = "PostgreSQL to Aurora for ALTER USER during rotation"

  tags = merge(var.tags, {
    Name       = "${var.function_name}-to-aurora"
    Function   = "secret-rotation-network-access"
    IsMonetary = "False"
  })
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to the Secrets Manager interface endpoint inside the VPC"

  tags = merge(var.tags, {
    Name       = "${var.function_name}-to-secretsmanager"
    Function   = "secret-rotation-network-access"
    IsMonetary = "False"
  })
}

resource "aws_vpc_security_group_ingress_rule" "db_from_rotation" {
  security_group_id            = var.db_security_group_id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  description                  = "PostgreSQL from ${var.function_name}"

  tags = merge(var.tags, {
    Name       = "aurora-from-${var.function_name}"
    Function   = "secret-rotation-network-access"
    IsMonetary = "False"
  })
}

resource "aws_security_group" "secretsmanager_endpoint" {
  count = var.create_secretsmanager_vpc_endpoint ? 1 : 0

  name        = "${var.function_name}-secretsmanager-vpce-sg"
  description = "HTTPS ingress to the Secrets Manager interface endpoint from ${var.function_name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name       = "${var.function_name}-secretsmanager-vpce-sg"
    Function   = "private-aws-api-access"
    IsMonetary = "False"
  })
}

resource "aws_vpc_security_group_ingress_rule" "secretsmanager_endpoint" {
  count = var.create_secretsmanager_vpc_endpoint ? 1 : 0

  security_group_id            = aws_security_group.secretsmanager_endpoint[0].id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from ${var.function_name}"

  tags = merge(var.tags, {
    Name       = "secretsmanager-vpce-from-${var.function_name}"
    Function   = "private-aws-api-access"
    IsMonetary = "False"
  })
}

data "aws_iam_policy_document" "secretsmanager_endpoint" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.create_secretsmanager_vpc_endpoint ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.secretsmanager_endpoint[0].id]
  policy              = data.aws_iam_policy_document.secretsmanager_endpoint.json

  tags = merge(var.tags, {
    Name       = "${var.function_name}-secretsmanager-vpce"
    Function   = "private-aws-api-access"
    IsMonetary = "True"
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name       = "${var.function_name}-logs"
    Function   = "secret-rotation-log-retention"
    IsMonetary = "True"
  })
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "this" {
  name             = var.function_name
  application_id   = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser"
  semantic_version = var.application_version
  capabilities     = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY"]

  parameters = {
    endpoint            = "https://secretsmanager.${data.aws_region.current.region}.amazonaws.com"
    functionName        = var.function_name
    vpcSubnetIds        = join(",", var.subnet_ids)
    vpcSecurityGroupIds = aws_security_group.this.id
  }

  tags = merge(var.tags, {
    Name       = var.function_name
    Function   = "database-credential-rotation"
    IsMonetary = "True"
  })
}

data "aws_lambda_function" "this" {
  function_name = aws_serverlessapplicationrepository_cloudformation_stack.this.outputs["RotationLambdaARN"]
}
