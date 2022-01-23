# The ECS cluster that hosts our airflow services
resource "aws_ecs_cluster" "airflow" {
  name               = "airflow"
  capacity_providers = ["FARGATE"]
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# A role to control Amazon ECS container agent permissions (may already exist)
# This role is for ECS's container agent, not our containerized applications
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html#create-task-execution-role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

# A reference to the AWS managed "task execution role policy"
data "aws_iam_policy" "amazon_ecs_task_execution_role_policy" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

# The link between our task role and the above policy
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = data.aws_iam_policy.amazon_ecs_task_execution_role_policy.arn
}
