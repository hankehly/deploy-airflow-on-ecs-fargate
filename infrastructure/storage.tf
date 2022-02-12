resource "aws_s3_bucket" "airflow" {
  bucket_prefix = "deploy-airflow-on-ecs-fargate-"
}

resource "aws_s3_bucket_acl" "airflow" {
  bucket = aws_s3_bucket.airflow.id
  acl    = "private"
}
