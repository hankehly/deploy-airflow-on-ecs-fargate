# Firehose delivery stream for standalone task logs
resource "aws_kinesis_firehose_delivery_stream" "airflow_standalone_task_stream" {
  name        = "deploy-airflow-on-ecs-fargate-airflow-standalone-task-stream"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn            = aws_iam_role.airflow_firehose.arn
    bucket_arn          = aws_s3_bucket.airflow.arn
    prefix              = "kinesis-firehose/airflow-standalone-task/"
    error_output_prefix = "kinesis-firehose/airflow-standalone-task-error-output/"
  }
}

# Send fluentbit logs to Cloud Watch
resource "aws_cloudwatch_log_group" "airflow_standalone_task_fluentbit" {
  name_prefix       = "deploy-airflow-on-ecs-fargate/airflow-standalone-task-fluentbit/"
  retention_in_days = 3
}

# A security group for our standalone tasks
# We specify this not in our task definition, but when making calls to the "run-task" API
resource "aws_security_group" "airflow_standalone_task" {
  name        = "airflow-standalone-task"
  description = "Deny all incoming traffic"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
      name        = "airflow"
      image       = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu         = 256
      memory      = 512
      essential   = true
      command     = ["version"]
      environment = local.airflow_task_common_env
      user        = "50000:0"
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          region          = var.aws_region
          delivery_stream = aws_kinesis_firehose_delivery_stream.airflow_standalone_task_stream.name
        }
      }
    },
    {
      name      = "fluentbit"
      essential = true
      image     = local.fluentbit_image,
      firelensConfiguration = {
        type = "fluentbit"
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow_standalone_task_fluentbit.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-standalone-task-fluentbit"
        }
      },
      memoryReservation = 50
    }
  ])
}
