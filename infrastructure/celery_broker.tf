# Using Amazon SQS as celery broker
# https://docs.celeryproject.org/en/stable/getting-started/backends-and-brokers/sqs.html
resource "aws_sqs_queue" "celery_broker" {
  name_prefix = "airflow-celery-broker-"
}
