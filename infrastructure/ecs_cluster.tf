# The ECS cluster that hosts our airflow services
resource "aws_ecs_cluster" "airflow" {
  name = "airflow"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "airflow" {
  cluster_name       = aws_ecs_cluster.airflow.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  # Place all tasks in fargate by default
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# A role to control Amazon ECS container agent permissions (may already exist)
# This role is for ECS's container agent, not our containerized applications
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html#create-task-execution-role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
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

# A reference to the AWS managed "task execution role policy"
data "aws_iam_policy" "amazon_ecs_task_execution_role_policy" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

# The link between our task role and the above policy
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.amazon_ecs_task_execution_role_policy.arn
}

# The task execution role also requires read access to SSM to fetch the Cloud Watch
# agent configuration
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy_servicelens_CloudWatch_agent_deploy_ECS.html
data "aws_iam_policy" "amazon_ssm_read_only_access" {
  name = "AmazonSSMReadOnlyAccess"
}
resource "aws_iam_role_policy_attachment" "amazon_ssm_read_only_access_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.amazon_ssm_read_only_access.arn
}


# A role to control API permissions on our airflow service tasks
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

# Containers need this policy for usage with Cloud Watch agent
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy_servicelens_CloudWatch_agent_deploy_ECS.html
data "aws_iam_policy" "cloud_watch_agent_server_policy" {
  name = "CloudWatchAgentServerPolicy"
}
resource "aws_iam_role_policy_attachment" "cloud_watch_agent_server_policy" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = data.aws_iam_policy.cloud_watch_agent_server_policy.arn
}

# Allow airflow tasks to perform operations on SQS queues.
# The permissions granted here may be more than necessary.
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
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ListQueues",
          "sqs:ChangeMessageVisibility",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:ListQueueTags",
          "sqs:ListDeadLetterSourceQueues",
          "sqs:PurgeQueue",
          "sqs:DeleteQueue",
          "sqs:CreateQueue",
          "sqs:SetQueueAttributes"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_sqs_read_write" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_sqs_read_write.arn
}

# The ECS Exec feature requires a task IAM role to grant containers the permissions
# needed for communication between the managed SSM agent (execute-command agent) and
# the SSM service.
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

# Enable ECS Exec on our airflow tasks
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

# A policy to allow ECS services to read secrets from AWS Secret Manager
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
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# Allow airflow task containers to read SecretManager secrets
resource "aws_iam_role_policy_attachment" "airflow_read_secret" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.secret_manager_read_secret.arn
}

# Permissions for airflow services to access S3
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

# A policy to allow the metrics service to get/send metrics to CloudWatch. These
# permissions only required by the metrics service; but to simplify the config for
# demonstration purposes, we grant airflow services the same permissions.
resource "aws_iam_policy" "airflow_cloudwatch_put_metric_data" {
  name_prefix = "airflow-cloudwatch-put-metric-data-"
  path        = "/"
  description = "Grant permissions needed to send metric data to cloudwatch."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_cloudwatch_put_metric_data" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_cloudwatch_put_metric_data.arn
}

locals {
  airflow_task_common_environment = [
    {
      name  = "AIRFLOW__WEBSERVER__INSTANCE_NAME"
      value = "deploy-airflow-on-ecs-fargate"
    },
    {
      name  = "AIRFLOW__LOGGING__LOGGING_LEVEL"
      value = "DEBUG"
    },
    {
      name  = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER"
      value = "s3://${aws_s3_bucket.airflow.bucket}/remote_base_log_folder/"
    },
    {
      name  = "X_AIRFLOW_SQS_CELERY_BROKER_PREDEFINED_QUEUE_URL"
      value = aws_sqs_queue.airflow_worker_broker.url
    },
    # Here we take advantage of Amazon's SecretsManagerBackend to retrieve secret values
    # at runtime from Secret Manager. We only need to store the *name* of the secret,
    # so an environment variable is acceptable.
    # Another option would be to specify the secret values directly as environment
    # variables using the Task Definition "secrets" attribute.
    # In that case, you would switch "value" to "valueFrom" and set the value to the
    # secret ARN: eg. aws_secretsmanager_secret.sql_alchemy_conn.arn
    {
      name = "AIRFLOW__CORE__SQL_ALCHEMY_CONN_SECRET"

      # Use substr to remove the "config_prefix" string from the secret names
      value = substr(aws_secretsmanager_secret.sql_alchemy_conn.name, 45, -1)
    },
    {
      name  = "AIRFLOW__CORE__FERNET_KEY_SECRET"
      value = substr(aws_secretsmanager_secret.fernet_key.name, 45, -1)
    },
    {
      name  = "AIRFLOW__CELERY__RESULT_BACKEND_SECRET"
      value = substr(aws_secretsmanager_secret.celery_result_backend.name, 45, -1)
    },
    {
      # Gotcha: Even if you set this to "True" in airflow.cfg
      # an environment variable overrides it to False
      name  = "AIRFLOW__CORE__LOAD_EXAMPLES"
      value = "True"
    }
  ]

  airflow_cloud_watch_metrics_namespace = "DeployAirflowOnECSFargate"
}
