# Firehose delivery stream for metrics logs
resource "aws_kinesis_firehose_delivery_stream" "airflow_metrics_stream" {
  name        = "deploy-airflow-on-ecs-fargate-airflow-metrics-stream"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn            = aws_iam_role.airflow_firehose.arn
    bucket_arn          = aws_s3_bucket.airflow.arn
    prefix              = "kinesis-firehose/airflow-metrics/"
    error_output_prefix = "kinesis-firehose/airflow-metrics-error-output/"
  }
}

# Send fluentbit logs to Cloud Watch
resource "aws_cloudwatch_log_group" "airflow_metrics_fluentbit" {
  name_prefix       = "deploy-airflow-on-ecs-fargate/airflow-metrics-fluentbit/"
  retention_in_days = 3
}

# Metrics service security group (no incoming connections)
resource "aws_security_group" "airflow_metrics_service" {
  name_prefix = "airflow-metrics-"
  description = "Deny all incoming traffic"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  number_of_active_running_dags_metric = {
    namespace   = "DeployAirflowOnECSFargate"
    metric_name = "NumberOfActiveRunningDags"
  }
}

# Metrics service task definition
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
resource "aws_ecs_task_definition" "airflow_metrics" {
  family             = "airflow-metrics"
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
      name      = "metrics"
      image     = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu       = 256
      memory    = 512
      essential = true
      command = [
        "python",
        "scripts/put_number_of_active_running_dags_metric.py",
        "--namespace",
        local.number_of_active_running_dags_metric.namespace,
        "--cluster-name",
        aws_ecs_cluster.airflow.name,
        "--metric-name",
        local.number_of_active_running_dags_metric.metric_name,
        "--region-name",
        var.aws_region
      ]
      environment = local.airflow_task_common_env
      user        = "50000:0"
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          region          = var.aws_region
          delivery_stream = aws_kinesis_firehose_delivery_stream.airflow_metrics_stream.name
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
          awslogs-group         = aws_cloudwatch_log_group.airflow_metrics_fluentbit.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-metrics-fluentbit"
        }
      },
      memoryReservation = 50
    }
  ])
}

# Airflow ECS metrics service
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
resource "aws_ecs_service" "airflow_metrics" {
  name = "airflow-metrics"
  # If a revision is not specified, the latest ACTIVE revision is used.
  task_definition = aws_ecs_task_definition.airflow_metrics.family
  cluster         = aws_ecs_cluster.airflow.arn
  # If using awsvpc network mode, do not specify this role.
  # iam_role =
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  launch_type                        = "FARGATE"
  network_configuration {
    subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    # For tasks on Fargate, in order for the task to pull the container image it must either
    # 1. use a public subnet and be assigned a public IP address
    # 2. use a private subnet that has a route to the internet or a NAT gateway
    assign_public_ip = true
    security_groups  = [aws_security_group.airflow_metrics_service.id]
  }
  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  # This can be used to update tasks to use a newer container image with same
  # image/tag combination (e.g., myimage:latest)
  force_new_deployment = true
}

# resource "aws_cloudwatch_metric_alarm" "airflow_zero_active_running_dags" {
#   alarm_name        = "AirflowZeroActiveRunningDags"
#   alarm_description = "Alarm raised when the number of active running dags is zero for 15 consecutive minutes"
#   namespace         = local.number_of_active_running_dags_metric.namespace
#   metric_name       = local.number_of_active_running_dags_metric.metric_name
#   dimensions = {
#     ClusterName = aws_ecs_cluster.airflow.name
#   }
#   # Evaluate the alarm every 300 seconds
#   period = 300
#   # Every {period} seconds, we want to compute the sum of the data points within the
#   # past {period} seconds.
#   statistic = "Sum"
#   # When deciding whether or not to enter alarm state, consider this many periods in the past.
#   evaluation_periods = 3
#   # If this many points out of the past {evaluation_periods} points meet the alarm state
#   # condition, enter alarm state. Otherwise, enter OK state.
#   # In this demonstration, I want to check for 15 consecutive minutes of inactivity, so
#   # only enter alarm state if 3 out of the past 3 periods (each 5 minutes in length)
#   # reached the alarm state condition.
#   datapoints_to_alarm = 3
#   # Every {period} seconds, we ask the following:
#   #  "Is the metric value for the past {period} seconds less than {threshold}?"
#   comparison_operator = "LessThanThreshold"
#   threshold           = 1
#   alarm_actions = [
#     # Trigger airflow workers to "scale in"
#     aws_appautoscaling_policy.airflow_worker_scale_in.arn
#   ]
# }
