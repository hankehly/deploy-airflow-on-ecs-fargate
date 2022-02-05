# A security group to attach to our webserver ALB to allow all incoming HTTP requests
resource "aws_security_group" "airflow_webserver_alb" {
  name_prefix = "airflow-webserver-alb-"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The ALB for our webserver service
resource "aws_lb" "airflow_webserver" {
  name               = "airflow-webserver"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.airflow_webserver_alb.id]
  # Skip for demo
  # access_logs { }
  subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  ip_address_type = "ipv4"
}

# Webserver service target group to route traffic from ALB listener to ECS service
# Flow: Internet -> ALB -> Listener -> Target Group -> ECS Service
# Note: ECS registers targets automatically, so we do not need to define them.
resource "aws_lb_target_group" "airflow_webserver" {
  name        = "airflow-webserver"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
  health_check {
    enabled = true
    path    = "/health"
    # Gotcha: interval must be greater than timeout
    interval            = 30
    timeout             = 10
    unhealthy_threshold = 5
  }
}

# Listener to forward traffic from ALB to webserver service target group
# Flow: Internet -> ALB -> Listener -> Target Group -> ECS Service
resource "aws_lb_listener" "airflow_webserver" {
  load_balancer_arn = aws_lb.airflow_webserver.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.airflow_webserver.arn
  }
}

# Firehose delivery stream for webserver logs
resource "aws_kinesis_firehose_delivery_stream" "airflow_webserver_stream" {
  name        = "deploy-airflow-on-ecs-fargate-airflow-webserver-stream"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn            = aws_iam_role.airflow_firehose.arn
    bucket_arn          = aws_s3_bucket.airflow.arn
    prefix              = "kinesis-firehose/airflow-webserver/"
    error_output_prefix = "kinesis-firehose/airflow-webserver-error-output/"
  }
}

# Send fluentbit logs to Cloud Watch
resource "aws_cloudwatch_log_group" "airflow_webserver_fluentbit" {
  name_prefix       = "deploy-airflow-on-ecs-fargate/airflow-webserver-fluentbit/"
  retention_in_days = 3
}

# Webserver task definition
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
resource "aws_ecs_task_definition" "airflow_webserver" {
  family             = "airflow-webserver"
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
      name   = "webserver"
      image  = join(":", [aws_ecr_repository.airflow.repository_url, "latest"])
      cpu    = 1024
      memory = 2048
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
      healthcheck = {
        command = [
          "CMD",
          "curl",
          "--fail",
          "http://localhost:8080/health"
        ]
        interval = 35
        timeout  = 30
        retries  = 5
      }
      # Start the init process inside the container to remove any zombie SSM agent child processes found
      # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html#ecs-exec-task-definition
      linuxParameters = {
        initProcessEnabled = true
      }
      essential   = true
      command     = ["webserver"]
      environment = local.airflow_task_common_env
      user        = "50000:0"
      # Example forwarding logs to an Kinesis Data Firehose delivery stream
      # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/firelens-example-taskdefs.html#firelens-example-firehose
      logConfiguration = {
        # The awsfirelens log driver is syntactic sugar for the Task Definition.
        # It allows you to specify Fluentd or Fluent Bit output plugin configuration.
        # https://aws.amazon.com/blogs/containers/under-the-hood-firelens-for-amazon-ecs-tasks/
        logDriver = "awsfirelens"
        options = {
          # Error: unable to apply log options of container metrics to fireLens config: missing output key Name which is r
          # Amazon Kinesis Data Firehose output plugin configuration parameters
          # https://docs.fluentbit.io/manual/pipeline/outputs/firehose#configuration-parameters
          Name            = "kinesis_firehose"
          region          = var.aws_region
          delivery_stream = aws_kinesis_firehose_delivery_stream.airflow_webserver_stream.name
          # Gotcha: You need to set the time_key property to add the timestamp to the log record.
          # By default the timestamp from Fluent Bit will not be added to records sent to Kinesis.
          time_key = "timestamp"
          # Add millisecond precision to timestamp
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
          awslogs-group         = aws_cloudwatch_log_group.airflow_webserver_fluentbit.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "airflow-webserver-fluentbit"
        }
      },
      memoryReservation = 50
    }
  ])
}

# Webserver service security group to allow access from load balancer
resource "aws_security_group" "airflow_webserver_service" {
  name_prefix = "airflow-webserver-service-"
  description = "Allow HTTP inbound traffic from load balancer"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "HTTP from load balancer"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.airflow_webserver_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Airflow webserver service
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
resource "aws_ecs_service" "airflow_webserver" {
  name = "airflow-webserver"
  # If a revision is not specified, the latest ACTIVE revision is used.
  task_definition = aws_ecs_task_definition.airflow_webserver.family
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
    security_groups  = [aws_security_group.airflow_webserver_service.id]
  }
  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  load_balancer {
    target_group_arn = aws_lb_target_group.airflow_webserver.arn
    container_name   = "webserver"
    container_port   = 8080
  }
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
resource "aws_appautoscaling_target" "airflow_webserver" {
  max_capacity       = 1
  min_capacity       = 0
  resource_id        = "service/${aws_ecs_cluster.airflow.name}/${aws_ecs_service.airflow_webserver.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale to zero at night (21:00 Japan Standard Time)
resource "aws_appautoscaling_scheduled_action" "airflow_webserver_scheduled_scale_in" {
  name               = "ecs"
  service_namespace  = aws_appautoscaling_target.airflow_webserver.service_namespace
  resource_id        = aws_appautoscaling_target.airflow_webserver.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_webserver.scalable_dimension
  # Gotcha: Cron expressions have SIX required fields
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions
  schedule = "cron(0 12 * * ? *)"
  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}

# Scale to one during the day (10:00 Japan Standard Time)
resource "aws_appautoscaling_scheduled_action" "airflow_webserver_scheduled_scale_out" {
  name               = "ecs"
  service_namespace  = aws_appautoscaling_target.airflow_webserver.service_namespace
  resource_id        = aws_appautoscaling_target.airflow_webserver.resource_id
  scalable_dimension = aws_appautoscaling_target.airflow_webserver.scalable_dimension
  # Gotcha: Cron expressions have SIX required fields
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions
  schedule = "cron(0 3 * * ? *)"
  scalable_target_action {
    min_capacity = 1
    max_capacity = 1
  }
  depends_on = [
    # Prevent a `ConcurrentUpdateException` by forcing sequential changes to autoscaling policies
    aws_appautoscaling_scheduled_action.airflow_webserver_scheduled_scale_in
  ]
}
