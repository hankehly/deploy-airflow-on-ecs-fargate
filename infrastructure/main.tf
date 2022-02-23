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

  airflow_task_common_environment = [
    {
      name  = "AIRFLOW__WEBSERVER__INSTANCE_NAME"
      value = "deploy-airflow-on-ecs-fargate"
    },
    {
      name  = "AIRFLOW__LOGGING__LOGGING_LEVEL"
      value = "DEBUG"
    },
    {
      name  = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER"
      value = "s3://${aws_s3_bucket.airflow.bucket}/remote_base_log_folder/"
    },
    {
      name  = "X_AIRFLOW_SQS_CELERY_BROKER_PREDEFINED_QUEUE_URL"
      value = aws_sqs_queue.celery_broker.url
    },
    # Use the Amazon SecretsManagerBackend to retrieve secret configuration values at
    # runtime from Secret Manager. Only the *name* of the secret is needed here, so an
    # environment variable is acceptable.
    # Another option would be to specify the secret values directly as environment
    # variables using the Task Definition "secrets" attribute. In that case, one would
    # instead set "valueFrom" to the secret ARN (eg. aws_secretsmanager_secret.sql_alchemy_conn.arn)
    {
      name = "AIRFLOW__CORE__SQL_ALCHEMY_CONN_SECRET"
      # Remove the "config_prefix" using `substr`
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
      # Note: Even if one sets this to "True" in airflow.cfg a hidden environment
      # variable overrides it to False
      name  = "AIRFLOW__CORE__LOAD_EXAMPLES"
      value = "True"
    }
  ]

  airflow_cloud_watch_metrics_namespace = "DeployAirflowOnECSFargate"
}
