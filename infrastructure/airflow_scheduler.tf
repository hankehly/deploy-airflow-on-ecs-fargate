# Firehose delivery stream for scheduler logs
resource "aws_kinesis_firehose_delivery_stream" "airflow_scheduler_stream" {
  name        = "deploy-airflow-on-ecs-fargate-airflow-scheduler-stream"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn            = aws_iam_role.airflow_firehose.arn
    bucket_arn          = aws_s3_bucket.airflow.arn
    prefix              = "kinesis-firehose/airflow-scheduler/"
    error_output_prefix = "kinesis-firehose/airflow-scheduler-error-output/"
  }
}

# Send fluentbit logs to Cloud Watch
resource "aws_cloudwatch_log_group" "airflow_scheduler_fluentbit" {
  name_prefix       = "deploy-airflow-on-ecs-fargate/airflow-scheduler-fluentbit/"
  retention_in_days = 3
}

# Scheduler service task definition
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
resource "aws_ecs_task_definition" "airflow_scheduler" {
  family             = "airflow-scheduler"
  cpu                = 1024
  memory             = 2048
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
      name   = "scheduler"
      image  = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu    = 1024
      memory = 2048
      healthcheck = {
        command = [
          "CMD-SHELL",
          "airflow jobs check --job-type SchedulerJob --hostname \"$${HOSTNAME}\""
        ]
        interval = 35
        timeout  = 30
        retries  = 5
      }
      essential = true
      command   = ["scheduler"]
      # Start the init process inside the container to remove any zombie SSM agent child processes found
      # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html#ecs-exec-task-definition
      linuxParameters = {
        initProcessEnabled = true
      }
      environment = local.airflow_task_common_env
      user        = "50000:0"
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name            = "kinesis_firehose"
          region          = var.aws_region
          delivery_stream = aws_kinesis_firehose_delivery_stream.airflow_scheduler_stream.name
          time_key        = "timestamp"
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
          awslogs-group         = aws_cloudwatch_log_group.airflow_scheduler_fluentbit.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-scheduler-fluentbit"
        }
      },
      memoryReservation = 50
    }
  ])
}

# Scheduler service security group (no incoming connections)
resource "aws_security_group" "airflow_scheduler_service" {
  name_prefix = "airflow-scheduler-"
  description = "Deny all incoming traffic"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Airflow ECS scheduler service
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
resource "aws_ecs_service" "airflow_scheduler" {
  name = "airflow-scheduler"
  # If a revision is not specified, the latest ACTIVE revision is used.
  task_definition = aws_ecs_task_definition.airflow_scheduler.family
  cluster         = aws_ecs_cluster.airflow.arn
  # If using awsvpc network mode, do not specify this role.
  # iam_role =
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  lifecycle {
    ignore_changes = [desired_count]
  }
  enable_execute_command = true
  launch_type            = "FARGATE"
  network_configuration {
    subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    # For tasks on Fargate, in order for the task to pull the container image it must either
    # 1. use a public subnet and be assigned a public IP address
    # 2. use a private subnet that has a route to the internet or a NAT gateway
    assign_public_ip = true
    security_groups  = [aws_security_group.airflow_scheduler_service.id]
  }
  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  # This can be used to update tasks to use a newer container image with same
  # image/tag combination (e.g., myimage:latest)
  force_new_deployment = true
}

# For this example, we want to save money by scaling to zero at night when we don't need to access the service.
# Target registration:
#  https://docs.aws.amazon.com/autoscaling/application/userguide/services-that-can-integrate-ecs.html#integrate-register-ecs
# Example scaling configurations:
#  https://docs.aws.amazon.com/autoscaling/application/userguide/examples-scheduled-actions.html
# ECS scheduled scaling example:
#  https://aws.amazon.com/blogs/containers/optimizing-amazon-elastic-container-service-for-cost-using-scheduled-scaling/
resource "aws_appautoscaling_target" "airflow_scheduler" {
  max_capacity       = 1
  min_capacity       = 0
  resource_id        = "service/${aws_ecs_cluster.airflow.name}/${aws_ecs_service.airflow_scheduler.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale to zero at night (21:00 Japan Standard Time)
resource "aws_appautoscaling_scheduled_action" "airflow_scheduler_scheduled_scale_in" {
  name               = "ecs"
  service_namespace  = aws_appautoscaling_target.airflow_scheduler.service_namespace
  resource_id        = aws_appautoscaling_target.airflow_scheduler.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_scheduler.scalable_dimension
  # Gotcha: Cron expressions have SIX required fields
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions
  schedule = "cron(0 12 * * ? *)"
  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}

# Scale to one during the day (10:00 Japan Standard Time)
resource "aws_appautoscaling_scheduled_action" "airflow_scheduler_scheduled_scale_out" {
  name               = "ecs"
  service_namespace  = aws_appautoscaling_target.airflow_scheduler.service_namespace
  resource_id        = aws_appautoscaling_target.airflow_scheduler.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_scheduler.scalable_dimension
  # Gotcha: Cron expressions have SIX required fields
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions
  schedule = "cron(0 3 * * ? *)"
  scalable_target_action {
    min_capacity = 1
    max_capacity = 1
  }
  depends_on = [
    # Prevent a `ConcurrentUpdateException` by forcing sequential changes to autoscaling policies
    aws_appautoscaling_scheduled_action.airflow_scheduler_scheduled_scale_in
  ]
}
