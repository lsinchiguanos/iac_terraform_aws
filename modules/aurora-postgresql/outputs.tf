output "cluster_identifier" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  value = aws_rds_cluster.this.cluster_resource_id
}

output "writer_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "database_name" {
  value = aws_rds_cluster.this.database_name
}

output "master_username" {
  value = aws_rds_cluster.this.master_username
}

output "security_group_id" {
  value = aws_security_group.this.id
}
