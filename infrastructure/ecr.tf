resource "aws_ecr_repository" "airflow" {
  name = "deploy-airflow-on-ecs-fargate-airflow"
  image_scanning_configuration {
    scan_on_push = true
  }
}
