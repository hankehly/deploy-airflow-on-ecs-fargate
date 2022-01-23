resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/21"
  tags = {
    Name = "deploy-airflow-on-ecs-fargate"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "deploy-airflow-on-ecs-fargate"
  }
}

# AWS automatically creates the default route table for us.
# We just want to specify our internet gateway.
# The 'local' route is added automatically for us.
resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "deploy-airflow-on-ecs-fargate"
  }
}

# A few public subnets to host our Internet facing services
resource "aws_subnet" "public_a" {
  availability_zone       = "${var.aws_region}a"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
  tags = {
    Name = "deploy-airflow-on-ecs-fargate-public-a"
  }
}
resource "aws_subnet" "public_b" {
  availability_zone       = "${var.aws_region}b"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
  tags = {
    Name = "deploy-airflow-on-ecs-fargate-public-b"
  }
}

# A few private subnets to host private services like the metadata db and cache
resource "aws_subnet" "private_a" {
  availability_zone       = "${var.aws_region}a"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.main.id
  tags = {
    Name = "deploy-airflow-on-ecs-fargate-private-a"
  }
}
resource "aws_subnet" "private_b" {
  availability_zone       = "${var.aws_region}b"
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.main.id
  tags = {
    Name = "deploy-airflow-on-ecs-fargate-private-b"
  }
}
