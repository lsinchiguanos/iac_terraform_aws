data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  via_services = [for s in var.via_services : "${s}.${data.aws_region.current.region}.amazonaws.com"]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.administrator_arns
    }

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListGrants",
      "kms:ListKeyPolicies",
      "kms:ListKeyRotations",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:RevokeGrant",
      "kms:RotateKeyOnDemand",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "CryptographicUseThroughAwsServices"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.service_user_arns
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = local.via_services
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "GrantsForAwsResources"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.service_user_arns
    }

    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]

    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = local.via_services
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudwatch_logs_log_group_arns) > 0 ? [1] : []

    content {
      sid    = "CloudWatchLogsEncryption"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
      }

      actions = [
        "kms:Decrypt*",
        "kms:Describe*",
        "kms:Encrypt*",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]

      resources = ["*"]

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = var.cloudwatch_logs_log_group_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description                        = var.description
  key_usage                          = "ENCRYPT_DECRYPT"
  customer_master_key_spec           = "SYMMETRIC_DEFAULT"
  multi_region                       = false
  enable_key_rotation                = true
  rotation_period_in_days            = var.rotation_period_in_days
  deletion_window_in_days            = var.deletion_window_in_days
  bypass_policy_lockout_safety_check = false
  policy                             = data.aws_iam_policy_document.this.json

  tags = merge(var.tags, {
    Name               = var.name
    Function           = var.function
    IsMonetary         = "True"
    DataClassification = var.data_classification
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
