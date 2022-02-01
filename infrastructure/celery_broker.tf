# An SQS queue to act as our celery broker
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
resource "aws_sqs_queue" "airflow_worker_broker" {
  name_prefix = "airflow-worker-broker-"
}

# Raise an alarm when our queue has been empty for 15 consecutive minutes.
# We can use this to 'scale in' the worker service.
# https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
resource "aws_cloudwatch_metric_alarm" "airflow_worker_broker_queue_empty" {
  alarm_name        = "AirflowWorkerBrokerQueueEmpty"
  alarm_description = "Alarm raised when the queue has been empty for 15 consecutive minutes"
  namespace         = "AWS/SQS"
  metric_name       = "NumberOfEmptyReceives"
  dimensions = {
    QueueName = aws_sqs_queue.airflow_worker_broker.name
  }
  statistic = "Sum"
  # Evaluate the alarm every 300 seconds
  period = 300
  # When deciding whether or not to enter alarm state, don't just consider the most recent
  # event. Consider this many periods in the past as well.
  evaluation_periods = 3
  # If this many points out of the past {evaluation_periods} points meet the alarm state
  # condition, enter alarm state. Otherwise, enter OK state.
  # In this demonstration, I want to check for 15 consecutive minutes of inactivity, so
  # only enter alarm state if 3 out of the past 3 periods (each 5 minutes in length)
  # reached the alarm state condition.
  datapoints_to_alarm = 3
  # For each period, we ask the following:
  #   "Is the total number of empty receives for the past 300 seconds above zero?"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  alarm_actions = [
    # Trigger airflow workers to "scale in"
    aws_appautoscaling_policy.airflow_worker_scale_in.arn
  ]
}

# Raise an alarm when there are messages in the queue waiting to be received.
# If there are more than 0, this means the current number of workers is insufficient.
resource "aws_cloudwatch_metric_alarm" "airflow_worker_broker_messages_waiting" {
  alarm_name  = "AirflowWorkerBrokerMessagesWaiting"
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
