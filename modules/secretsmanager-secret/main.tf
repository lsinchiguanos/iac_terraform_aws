resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name               = var.name
    Function           = var.function
    IsMonetary         = "True"
    DataClassification = var.data_classification
  })
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id                = aws_secretsmanager_secret.this.id
  secret_string_wo         = jsonencode(merge(var.secret_attributes, { password = var.secret_password }))
  secret_string_wo_version = var.secret_value_version
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "DenySecretValueAccessOutsideAllowedPrincipals"
    effect = "Deny"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]

    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = distinct(concat(var.administrator_arns, var.reader_arns))
    }
  }

  statement {
    sid    = "DenySecretManagementOutsideAdministrators"
    effect = "Deny"

    actions = [
      "secretsmanager:CancelRotateSecret",
      "secretsmanager:DeleteResourcePolicy",
      "secretsmanager:DeleteSecret",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:RemoveRegionsFromReplication",
      "secretsmanager:ReplicateSecretToRegions",
      "secretsmanager:RestoreSecret",
      "secretsmanager:RotateSecret",
      "secretsmanager:StopReplicationToReplica",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:UpdateSecret",
    ]

    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = var.administrator_arns
    }
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  secret_arn          = aws_secretsmanager_secret.this.arn
  policy              = data.aws_iam_policy_document.this.json
  block_public_policy = true
}

resource "aws_secretsmanager_secret_rotation" "this" {
  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_lambda_arn
  rotate_immediately  = true

  rotation_rules {
    schedule_expression = var.rotation_schedule_expression
    duration            = var.rotation_window_duration
  }

  depends_on = [
    aws_secretsmanager_secret_version.this,
    aws_secretsmanager_secret_policy.this,
  ]
}
