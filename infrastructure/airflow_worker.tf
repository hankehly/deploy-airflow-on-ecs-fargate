# Worker service security group (no incoming connections)
resource "aws_security_group" "airflow_worker_service" {
  name_prefix = "airflow-worker"
  description = "Deny all incoming traffic"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Direct worker logs to this Cloud Watch log group
resource "aws_cloudwatch_log_group" "airflow_worker" {
  name_prefix       = "deploy-airflow-on-ecs-fargate/airflow-worker/"
  retention_in_days = 3
}

# Worker service task definition
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
resource "aws_ecs_task_definition" "airflow_worker" {
  family             = "airflow-worker"
  cpu                = 1024
  memory             = 2048
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.airflow_task.arn
  network_mode       = "awsvpc"
  runtime_platform {
    operating_system_family = "LINUX"
    # ARM64 currently does not work because of upstream dependencies
    # https://github.com/apache/airflow/issues/15635
    cpu_architecture = "X86_64"
  }
  requires_compatibilities = ["FARGATE"]
  # Note: DUMB_INIT_SETSID required to handle warm shutdown of the celery workers properly
  #  (See https://airflow.apache.org/docs/docker-stack/entrypoint.html#signal-propagation)
  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu       = 1024
      memory    = 2048
      essential = true
      command   = ["celery", "worker"]
      environment = [
        {
          name  = "AIRFLOW__WEBSERVER__INSTANCE_NAME"
          value = "deploy-airflow-on-ecs-fargate"
        },
        # Use substr to remove the "config_prefix" string from the secret names
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
        },
        {
          name  = "DUMB_INIT_SETSID"
          value = "0"
        }
      ]
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

# Airflow ECS worker service
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
resource "aws_ecs_service" "airflow_worker" {
  name = "airflow-worker"
  # If a revision is not specified, the latest ACTIVE revision is used.
  task_definition = aws_ecs_task_definition.airflow_worker.family
  cluster         = aws_ecs_cluster.airflow.arn
  # If using awsvpc network mode, do not specify this role.
  # iam_role =
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # Workers are autoscaled depending on the state of the broker queue, so there is no
  # need to specify a desired_count here (the default is 0)
  desired_count = 0
  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    # For tasks on Fargate, in order for the task to pull the container image it must either
    # 1. use a public subnet and be assigned a public IP address
    # 2. use a private subnet that has a route to the internet or a NAT gateway
    assign_public_ip = true
    security_groups  = [aws_security_group.airflow_worker_service.id]
  }
  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  # This can be used to update tasks to use a newer container image with same
  # image/tag combination (e.g., myimage:latest)
  force_new_deployment = true
  # If a capacityProviderStrategy is specified, the launchType parameter must be omitted.
  # launch_type = "FARGATE"
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    # 100% of tasks should use fargate spot
    weight = 1
  }
}

# For this example, we want to save money by scaling to zero at night when we don't need to access the service.
# Target registration:
#  https://docs.aws.amazon.com/autoscaling/application/userguide/services-that-can-integrate-ecs.html#integrate-register-ecs
# Example scaling configurations:
#  https://docs.aws.amazon.com/autoscaling/application/userguide/examples-scheduled-actions.html
resource "aws_appautoscaling_target" "airflow_worker" {
  max_capacity       = 5
  min_capacity       = 0
  resource_id        = "service/${aws_ecs_cluster.airflow.name}/${aws_ecs_service.airflow_worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale in the workers
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy
resource "aws_appautoscaling_policy" "airflow_worker_scale_in" {
  name               = "airflow-worker-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.airflow_worker.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.airflow_worker.service_namespace
  # More information on policy configuration can be found here:
  # # https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-simple-step.html#as-scaling-steps
  step_scaling_policy_configuration {
    adjustment_type = "ChangeInCapacity"
    # Scale in as most once every 5 minutes
    cooldown = 300
    # When looking at the cloud watch alarm metric points that triggered the scaling,
    # what do we want to base the step adjustment on? The minimum, maximum or average
    # value? Because we only have 1 step, the value of this parameter does not really matter
    metric_aggregation_type = "Maximum"
    # Property descriptions can be found here:
    # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-autoscaling-scalingpolicy-stepadjustments.html
    # Here is a nice video describing step adjustments:
    # https://www.youtube.com/watch?v=Arv6NGQJJJQ
    step_adjustment {
      scaling_adjustment = -1
      # Setting the lower bound to zero indicates we want to act immediately on alarm threshold breach
      metric_interval_lower_bound = 0
      # Setting the upper bound to null(=inf) indicates that we do want our scaling
      # behavior to stop at a certain "cap"; rather we want it to continue as long as we
      # are in alarm state. If we wanted to scale-in in bigger adjustments, we could set
      # the upper bound to a number, then add another step adjustment with the lower bound
      # set to the other step adjustment's upper bound. This demo just shows a simple
      # configuration.
      metric_interval_upper_bound = null
    }
  }
}

# Scale out workers
resource "aws_appautoscaling_policy" "airflow_worker_scale_out" {
  name               = "airflow-worker-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.airflow_worker.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.airflow_worker.service_namespace
  step_scaling_policy_configuration {
    adjustment_type = "ChangeInCapacity"
    # Scale out at most once every 60 seconds
    cooldown = 60
    # When looking at the cloud watch alarm metric points that triggered the scaling,
    # what do we want to base the step adjustment on? The minimum, maximum or average
    # value? Because we only have 1 step, the value of this parameter does not really matter
    metric_aggregation_type = "Maximum"
    step_adjustment {
      scaling_adjustment = 1
      # Start scaling immediately on alarm threshold breach
      metric_interval_lower_bound = 0
      # Never stop or change scaling behavior, no matter how high the threshold breach goes
      metric_interval_upper_bound = null
    }
  }
  depends_on = [
    # Attempt to prevent the `ConcurrentUpdateException` by specifying dependency on the
    # other scaling policy
    aws_appautoscaling_policy.airflow_worker_scale_in
  ]
}
