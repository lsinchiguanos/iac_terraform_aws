data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "data" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "tag:Tier"
    values = [var.data_subnet_tier]
  }
}

data "aws_security_group" "db_clients" {
  for_each = toset(var.db_client_security_group_names)

  vpc_id = data.aws_vpc.this.id
  name   = each.value
}

data "aws_iam_role" "terraform_deployer" {
  name = var.terraform_deployer_role_name
}

data "aws_iam_role" "security_break_glass" {
  name = var.security_break_glass_role_name
}

data "aws_iam_role" "dba" {
  for_each = toset(var.dba_role_names)

  name = each.value
}

data "aws_iam_role" "transaction_records_writers" {
  for_each = toset(var.transaction_records_writer_role_names)

  name = each.value
}
