terraform {
  required_version = ">= 0.13.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.63"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      App = "deploy-airflow-on-ecs-fargate"
    }
  }
}

variable "metadata_db" {
  type = object({
    db_name  = string
    username = string
    password = string
    port     = string
  })
  sensitive = true
}

variable "fernet_key" {
  type      = string
  sensitive = true
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "force_new_ecs_service_deployment" {
  type    = bool
  default = true
}

locals {
  fluentbit_image = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
}
