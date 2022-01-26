# An SQS queue to act as our celery broker
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
resource "aws_sqs_queue" "airflow_worker_broker" {
  name_prefix = "airflow-worker-broker-"
}
