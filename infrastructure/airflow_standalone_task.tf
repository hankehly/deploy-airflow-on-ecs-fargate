# A security group for our standalone tasks
# We specify this not in our task definition, but when making calls to the "run-task" API
resource "aws_security_group" "airflow_standalone_task" {
  name_prefix = "airflow-standalone-task-"
  description = "Deny all incoming traffic"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Send logs from standalone tasks to this log group
resource "aws_cloudwatch_log_group" "airflow_standalone_task" {
  name_prefix       = "deploy-airflow-on-ecs-fargate/airflow-standalone-task/"
  retention_in_days = 3
}

# Standalone task template. Override container definition parameters like "command"
# when making calls to run-task API.
resource "aws_ecs_task_definition" "airflow_standalone_task" {
  family             = "airflow-standalone-task"
  cpu                = 256
  memory             = 512
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.airflow_task.arn
  network_mode       = "awsvpc"
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  requires_compatibilities = ["FARGATE"]
  container_definitions = jsonencode([
    {
      name      = "airflow"
      image     = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu       = 256
      memory    = 512
      essential = true
      command   = ["version"]
      environment = [
        {
          name  = "AIRFLOW__WEBSERVER__INSTANCE_NAME"
          value = "deploy-airflow-on-ecs-fargate"
        },
        {
          name  = "AIRFLOW__CORE__SQL_ALCHEMY_CONN_SECRET"
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
          name  = "X_AIRFLOW_SQS_CELERY_BROKER_PREDEFINED_QUEUE_URL"
          value = aws_sqs_queue.airflow_worker_broker.url
        }
      ]
      user = "50000:0"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow_standalone_task.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-standalone-task"
        }
      }
    }
  ])
}
