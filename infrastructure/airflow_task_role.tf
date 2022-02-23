# A role to control permissions of airflow service containers.
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_role_arn
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
resource "aws_iam_role" "airflow_task" {
  name_prefix = "airflow-task-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

# Containers need this policy for usage with the CloudWatch agent.
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy_servicelens_CloudWatch_agent_deploy_ECS.html
data "aws_iam_policy" "cloud_watch_agent_server_policy" {
  name = "CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cloud_watch_agent_server_policy" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = data.aws_iam_policy.cloud_watch_agent_server_policy.arn
}

# Grant airflow tasks permissions required to read/write messages from the celery broker.
resource "aws_iam_policy" "airflow_sqs_read_write" {
  name_prefix = "airflow-sqs-read-write-"
  path        = "/"
  description = "Grants read/write permissions on all SQS queues"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
        ]
        Resource = aws_sqs_queue.celery_broker.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_sqs_read_write" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_sqs_read_write.arn
}

# The ECS Exec feature requires a task IAM role to grant containers the permissions
# needed for communication between the managed SSM agent (execute-command agent) and the SSM service.
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html#ecs-exec-enabling-and-using
resource "aws_iam_policy" "ecs_task_ecs_exec" {
  name_prefix = "ecs-task-ecs-exec-"
  path        = "/"
  description = "Grant containers the permissions needed for communication between the managed SSM agent (execute-command agent) and the SSM service."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_ecs_exec" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.ecs_task_ecs_exec.arn
}

resource "aws_iam_policy" "airflow_firehose_put_record_batch" {
  name_prefix = "airflow-firehose-put-record-batch-"
  path        = "/"
  description = "Grant containers the permissions required for routing logs to Kinesis Data Firehose."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "firehose:PutRecordBatch"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_firehose_put_record_batch" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_firehose_put_record_batch.arn
}

# Allow ECS services to read secrets from AWS Secret Manager.
resource "aws_iam_policy" "secret_manager_read_secret" {
  name        = "secretManagerReadSecret"
  description = "Grants read, list and describe permissions on SecretManager secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Effect = "Allow"
        Resource = [
          aws_secretsmanager_secret.fernet_key.arn,
          aws_secretsmanager_secret.sql_alchemy_conn.arn,
          aws_secretsmanager_secret.celery_result_backend.arn
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_read_secret" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.secret_manager_read_secret.arn
}

# Allow airflow services to access S3
# In a proction environment, one may want to limit access to a specific key.
resource "aws_iam_policy" "airflow_task_storage" {
  name_prefix = "airflow-task-storage-"
  path        = "/"
  description = ""
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        Resource = [
          aws_s3_bucket.airflow.arn,
          "${aws_s3_bucket.airflow.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_task_storage" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_task_storage.arn
}

# Allow the airflow metrics service to fetch ECS service information and send metrics
# to CloudWatch. These permissions are only required by the metrics service; but to
# simplify the configuration for demonstration purposes, all airflow services get
# the same permissions.
resource "aws_iam_policy" "airflow_metrics" {
  name_prefix = "airflow-metrics-"
  path        = "/"
  description = "Grant permissions needed for metrics service to get service information from ECS and send metric data to cloudwatch."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_metrics" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_metrics.arn
}
