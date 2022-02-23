# A subnet group for our RDS instance.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
resource "aws_db_subnet_group" "airflow_metadata_db" {
  name_prefix = "airflow-metadata-db-"
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# A security group to attach to our RDS instance.
# It should allow incoming access on var.metadata_db.port from our airflow services.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "airflow_metadata_db" {
  name_prefix = "airflow-metadata-db-"
  description = "Allow inbound traffic to RDS from ECS"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port = var.metadata_db.port
    to_port   = var.metadata_db.port
    protocol  = "tcp"
    security_groups = [
      aws_security_group.airflow_webserver_service.id,
      aws_security_group.airflow_scheduler_service.id,
      aws_security_group.airflow_worker_service.id,
      aws_security_group.airflow_standalone_task.id,
      aws_security_group.airflow_metrics_service.id
    ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# A postgres RDS instance for airflow metadata.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
resource "aws_db_instance" "airflow_metadata_db" {
  identifier_prefix      = "airflow-metadata-db-"
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_subnet_group_name   = aws_db_subnet_group.airflow_metadata_db.name
  engine                 = "postgres"
  engine_version         = "13.4"
  instance_class         = "db.t4g.micro"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.airflow_metadata_db.id]
  apply_immediately      = true
  skip_final_snapshot    = true
  db_name                = var.metadata_db.db_name
  username               = var.metadata_db.username
  password               = var.metadata_db.password
  port                   = var.metadata_db.port
}
