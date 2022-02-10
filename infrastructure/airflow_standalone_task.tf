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
  name_prefix       = "/deploy-airflow-on-ecs-fargate/airflow-standalone-task-fluentbit/"
  retention_in_days = 1
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
      environment = local.airflow_task_common_environment
      user        = "50000:0"
      # Example forwarding logs to a sidecar fluent-bit log router
      # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/firelens-example-taskdefs.html#firelens-example-firehose
      logConfiguration = {
        # The awsfirelens log driver is syntactic sugar for the Task Definition.
        # It allows you to specify Fluentd or Fluent Bit output plugin configuration.
        # https://aws.amazon.com/blogs/containers/under-the-hood-firelens-for-amazon-ecs-tasks/
        logDriver = "awsfirelens"
        # The Name field defines the plugin. Options are firehose or kinesis_firehose.
        # firehose is written in golang, while kinesis_firehost in C; but only the golang version
        # has support for millisecond time_key_format.
        #  Error: unable to apply log options of container metrics to fireLens config: missing output key Name which is required
        # Amazon Kinesis Data Firehose output plugin configuration parameters
        # https://docs.fluentbit.io/manual/pipeline/outputs/firehose#configuration-parameters
        options = {
          Name            = "firehose"
          region          = var.aws_region
          delivery_stream = aws_kinesis_firehose_delivery_stream.airflow_standalone_task_stream.name
          # Gotcha: You need to set the time_key property to add the timestamp to the log record.
          # By default the timestamp from Fluent Bit will not be added to records sent to Kinesis.
          time_key = "timestamp"
          # Add millisecond precision to timestamp (default is second precision)
          time_key_format = "%Y-%m-%dT%H:%M:%S.%L"
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
