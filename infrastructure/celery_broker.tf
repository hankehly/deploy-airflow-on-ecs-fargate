# An SQS queue to act as our celery broker
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
resource "aws_sqs_queue" "airflow_worker_broker" {
  name_prefix = "airflow-worker-broker-"
}

# Raise an alarm when there are messages in the queue waiting to be received.
# If there are more than 0, the current number of workers is insufficient.
resource "aws_cloudwatch_metric_alarm" "airflow_worker_broker_messages_visible" {
  alarm_name  = "AirflowWorkerBrokerMessagesVisible"
  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  statistic   = "Sum"
  dimensions = {
    QueueName = aws_sqs_queue.airflow_worker_broker.name
  }
  # We would like to "scale out" more quickly than "scale in", so check the alarm
  # condition every minute
  period = 60
  # Are there any (more than zero) messages visible (ie waiting to be received)
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  # We want this alarm to trigger immediately so that we can start processing work as
  # soon as possible, so let's specify that only 1 datapoint needs to cross the
  # threshold in order to enter alarm state.
  datapoints_to_alarm = 1
  evaluation_periods  = 1
  alarm_actions = [
    # Trigger airflow workers to "scale out"
    aws_appautoscaling_policy.airflow_worker_scale_out.arn
  ]
}
