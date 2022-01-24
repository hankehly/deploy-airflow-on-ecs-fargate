# A role to control API permissions on our flower tasks.
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_role_arn
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
resource "aws_iam_role" "flower_task" {
  name_prefix = "flowerTask"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Allow flower to read SecretManager secrets
resource "aws_iam_role_policy_attachment" "flower_read_secret" {
  role       = aws_iam_role.flower_task.name
  policy_arn = aws_iam_policy.secret_manager_read_secret.arn
}

# A security group to attach to our flower ALB to allow all incoming HTTP requests
resource "aws_security_group" "flower_alb" {
  name_prefix = "flower-alb"
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

# The ALB for our flower service
resource "aws_lb" "flower" {
  name_prefix        = "flower"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.flower_alb.id]
  # Skip for demo
  # access_logs { }
  subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  ip_address_type = "ipv4"
}

# Flower service target group to route traffic from ALB listener to ECS service
# Flow: Internet -> ALB -> Listener -> Target Group -> ECS Service
# Note: ECS registers targets automatically, so we do not need to define them.
resource "aws_lb_target_group" "flower" {
  # Gotcha: "name_prefix" cannot be longer than 6 characters
  name_prefix = "flower"
  port        = 5555
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
  health_check {
    enabled             = true
    path                = "/"
    interval            = 10
    timeout             = 10
    unhealthy_threshold = 5
  }
}

# Listener to forward traffic from ALB to flower service target group
# Flow: Internet -> ALB -> Listener -> Target Group -> ECS Service
resource "aws_lb_listener" "flower" {
  load_balancer_arn = aws_lb.flower.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flower.arn
  }
}

# Direct flower logs to this Cloud Watch log group
resource "aws_cloudwatch_log_group" "flower" {
  name_prefix = "flower"
}

# Flower task definition
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
resource "aws_ecs_task_definition" "flower" {
  family             = "flower"
  cpu                = 1024
  memory             = 2048
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.airflow_webserver_task.arn
  network_mode       = "awsvpc"
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  requires_compatibilities = ["FARGATE"]
  container_definitions = jsonencode([
    {
      name   = "flower"
      image  = aws_ecr_repository.airflow.repository_url
      cpu    = 1024
      memory = 2048
      portMappings = [
        {
          containerPort = 5555
          hostPort      = 5555
        }
      ]
      healthcheck = {
        command = [
          "CMD",
          "curl",
          "--fail",
          "http://localhost:5555/"
        ]
        interval = 10
        timeout  = 10
        retries  = 5
      }
      essential = true
      command   = ["celery", "flower"]
      environment = [
        {
          name  = "AIRFLOW__WEBSERVER__INSTANCE_NAME"
          value = "deploy-airflow-on-ecs-fargate"
        }
      ]
      user = "50000:0"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.flower.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "flower"
        }
      }
    }
  ])
}

# Flower service security group to allow access from load balancer
resource "aws_security_group" "flower_service" {
  name_prefix = "flower-service"
  description = "Allow HTTP inbound traffic from load balancer"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "HTTP from load balancer"
    from_port       = 5555
    to_port         = 5555
    protocol        = "tcp"
    security_groups = [aws_security_group.flower_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Flower service
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
resource "aws_ecs_service" "flower" {
  name = "flower"
  # If a revision is not specified, the latest ACTIVE revision is used.
  task_definition = aws_ecs_task_definition.flower.family
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
  launch_type = "FARGATE"
  network_configuration {
    subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    # For tasks on Fargate, in order for the task to pull the container image it must either
    # 1. use a public subnet and be assigned a public IP address
    # 2. use a private subnet that has a route to the internet or a NAT gateway
    assign_public_ip = true
    security_groups  = [aws_security_group.flower_service.id]
  }
  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  load_balancer {
    target_group_arn = aws_lb_target_group.flower.arn
    container_name   = "flower"
    container_port   = 5555
  }
  # This can be used to update tasks to use a newer container image with same
  # image/tag combination (e.g., myimage:latest)
  # force_new_deployment = true
}
