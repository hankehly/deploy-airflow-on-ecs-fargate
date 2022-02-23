# Send worker logs to this Cloud Watch log group
resource "aws_cloudwatch_log_group" "airflow_worker" {
  name_prefix       = "/deploy-airflow-on-ecs-fargate/airflow-worker/"
  retention_in_days = 1
}

resource "aws_ecs_task_definition" "airflow_worker" {
  family             = "airflow-worker"
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
      name      = "worker"
      image     = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu       = 1024
      memory    = 2048
      essential = true
      command   = ["celery", "worker"]
      linuxParameters = {
        initProcessEnabled = true
      }
      environment = concat(
        local.airflow_task_common_environment,
        # Note: DUMB_INIT_SETSID required to handle warm shutdown of the celery workers properly
        #  https://airflow.apache.org/docs/docker-stack/entrypoint.html#signal-propagation
        [
          {
            name  = "DUMB_INIT_SETSID"
            value = "0"
          }
        ]
      )
      user = "50000:0"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow_worker.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-worker"
        }
      }
    }
  ])
}

resource "aws_security_group" "airflow_worker_service" {
  name_prefix = "airflow-worker-"
  description = "Deny all incoming traffic"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "airflow_worker" {
  name            = "airflow-worker"
  task_definition = aws_ecs_task_definition.airflow_worker.family
  cluster         = aws_ecs_cluster.airflow.arn
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  # Workers are autoscaled depending on the active, unpaused task count, so there is no
  # need to specify a desired_count here (the default is 0)
  desired_count = 0
  lifecycle {
    ignore_changes = [desired_count]
  }
  enable_execute_command = true
  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.airflow_worker_service.id]
  }
  platform_version     = "1.4.0"
  scheduling_strategy  = "REPLICA"
  force_new_deployment = var.force_new_ecs_service_deployment
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

resource "aws_appautoscaling_target" "airflow_worker" {
  max_capacity       = 5
  min_capacity       = 0
  resource_id        = "service/${aws_ecs_cluster.airflow.name}/${aws_ecs_service.airflow_worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# A target tracking scaling policy to scale the worker service.
# With target tracking scaling policies, one selects a scaling metric and sets a target
# value. Amazon Auto Scaling creates and manages the CloudWatch alarms that trigger the
# scaling policy and calculates the scaling adjustment based on the metric and the target value.
# https://docs.aws.amazon.com/autoscaling/application/userguide/application-auto-scaling-target-tracking.html
resource "aws_appautoscaling_policy" "airflow_worker" {
  name               = "airflow-worker"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.airflow_worker.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.airflow_worker.service_namespace
  target_tracking_scaling_policy_configuration {
    target_value = local.airflow_worker_autoscaling_metric.target_tracking_target_value
    customized_metric_specification {
      namespace   = local.airflow_worker_autoscaling_metric.namespace
      metric_name = local.airflow_worker_autoscaling_metric.metric_name
      statistic   = "Average"
      dimensions {
        name  = "ClusterName"
        value = aws_ecs_cluster.airflow.name
      }
    }
  }
}
