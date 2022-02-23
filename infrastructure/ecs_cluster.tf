resource "aws_ecs_cluster" "airflow" {
  name = "airflow"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Allow services in our cluster to use fargate or fargate_spot.
# Place all tasks in fargate by default.
resource "aws_ecs_cluster_capacity_providers" "airflow" {
  cluster_name       = aws_ecs_cluster.airflow.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    weight            = 100
    capacity_provider = "FARGATE"
  }
}
