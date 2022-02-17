locals {
  airflow_worker_autoscaling_metric = {
    namespace                    = "DeployAirflowOnECSFargate"
    metric_name                  = "CapacityProviderReservation"
    metric_unit                  = "Percent"
    target_tracking_target_value = 100
  }
}

resource "aws_cloudwatch_log_group" "airflow_metrics" {
  name_prefix       = "/deploy-airflow-on-ecs-fargate/airflow-metrics/"
  retention_in_days = 1
}

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
      entryPoint = [
        "python"
      ]
      command = [
        "scripts/put_airflow_worker_autoscaling_metric_data.py",
        "--namespace",
        local.airflow_worker_autoscaling_metric.namespace,
        "--cluster-name",
        aws_ecs_cluster.airflow.name,
        "--metric-name",
        local.airflow_worker_autoscaling_metric.metric_name,
        "--metric-unit",
        local.airflow_worker_autoscaling_metric.metric_unit,
        "--worker-service-name",
        aws_ecs_service.airflow_worker.name,
        "--region-name",
        var.aws_region,
        "--period",
        "10"
      ]
      environment = local.airflow_task_common_environment
      user        = "50000:0"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.airflow_metrics.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-metrics"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "airflow_metrics" {
  name            = "airflow-metrics"
  task_definition = aws_ecs_task_definition.airflow_metrics.family
  cluster         = aws_ecs_cluster.airflow.arn
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  launch_type                        = "FARGATE"
  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.airflow_metrics_service.id]
  }
  platform_version     = "1.4.0"
  scheduling_strategy  = "REPLICA"
  force_new_deployment = var.force_new_ecs_service_deployment
}
