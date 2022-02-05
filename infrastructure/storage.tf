resource "aws_s3_bucket" "airflow" {
  bucket_prefix = "deploy-airflow-on-ecs-fargate-"
  acl           = "private"
}
