# The ECS cluster that hosts our airflow services
resource "aws_ecs_cluster" "airflow" {
  name               = "airflow"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  setting {
    name  = "containerInsights"
    value = "enabled"
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

# A role to control API permissions on our airflow service tasks
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_role_arn
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
resource "aws_iam_role" "airflow_task" {
  name_prefix = "airflowTask-"
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

# Allow airflow tasks to read SecretManager secrets
resource "aws_iam_role_policy_attachment" "airflow_read_secret" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.secret_manager_read_secret.arn
}

resource "aws_iam_role_policy_attachment" "airflow_sqs_read_write" {
  role       = aws_iam_role.airflow_task.name
  policy_arn = aws_iam_policy.airflow_sqs_read_write.arn
}
