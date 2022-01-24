# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group
resource "aws_elasticache_subnet_group" "airflow" {
  name       = "airflow"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# Redis security group that allows incoming connections from airflow services
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "airflow_worker_broker" {
  name_prefix = "airflow-worker-broker"
  description = "Allow ingress to the cache"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    security_groups = [
      aws_security_group.airflow_webserver_service.id,
      aws_security_group.airflow_scheduler_service.id,
      aws_security_group.airflow_worker_service.id
    ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our redis instance to servce as the airflow celery broker
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_cluster
resource "aws_elasticache_cluster" "airflow" {
  cluster_id = "airflow-worker-broker"
  engine     = "redis"
  node_type  = "cache.t4g.micro"
  # The initial number of cache nodes that the cache cluster will have.
  # For Redis, this value must be 1.
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  # Gotcha: When engine is redis and the version is 6 or higher
  # only the major version can be set, e.g., 6.x
  engine_version     = "6.x"
  port               = 6379
  security_group_ids = [aws_security_group.airflow_worker_broker.id]
  subnet_group_name  = aws_elasticache_subnet_group.airflow.name
}
