# A registry to push our container images to
resource "aws_ecr_repository" "airflow" {
  name = "airflow"
  image_scanning_configuration {
    scan_on_push = true
  }
}
