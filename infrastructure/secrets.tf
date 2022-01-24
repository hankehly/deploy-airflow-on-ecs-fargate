# A secret to hold our core.fernet_key setting for consumption by airflow SecretsManagerBackend
resource "aws_secretsmanager_secret" "fernet_key" {
  name_prefix = "airflow/config/fernet_key"
}
resource "aws_secretsmanager_secret_version" "fernet_key" {
  secret_id     = aws_secretsmanager_secret.fernet_key.id
  secret_string = var.fernet_key
}

# A secret to hold our celery.broker_url setting for consumption by airflow SecretsManagerBackend
# eg. redis://:@redis:6379/0
resource "aws_secretsmanager_secret" "broker_url" {
  name_prefix = "airflow/config/broker_url"
}
resource "aws_secretsmanager_secret_version" "broker_url" {
  secret_id = aws_secretsmanager_secret.broker_url.id
  secret_string = jsonencode([
    { "conn_type" : "redis" },
    { "host" : aws_elasticache_cluster.airflow.cache_nodes[0].address },
    { "port" : aws_elasticache_cluster.airflow.cache_nodes[0].port },
    { "schema" : "0" }
  ])
}

# A secret to hold our core.sql_alchemy_conn setting for consumption by airflow SecretsManagerBackend
# eg. postgresql+psycopg2://airflow:airflow@airflow-db/airflow
# Gotcha: The config options must follow the config prefix naming convention defined within the secrets backend.
#  This means that sql_alchemy_conn is not defined with a connection prefix, but with config prefix.
#  For example it should be named as airflow/config/sql_alchemy_conn
#  https://airflow.apache.org/docs/apache-airflow/stable/howto/set-config.html
resource "aws_secretsmanager_secret" "sql_alchemy_conn" {
  name_prefix = "airflow/config/sql_alchemy_conn"
}
resource "aws_secretsmanager_secret_version" "sql_alchemy_conn" {
  secret_id = aws_secretsmanager_secret.sql_alchemy_conn.id
  secret_string = jsonencode([
    { "conn_type" : "postgresql+psycopg2" },
    { "login" : aws_db_instance.airflow_metadata_db.username },
    { "password" : aws_db_instance.airflow_metadata_db.password },
    { "host" : aws_db_instance.airflow_metadata_db.address },
    { "port" : aws_db_instance.airflow_metadata_db.port },
    { "schema" : aws_db_instance.airflow_metadata_db.name }
  ])
}


# A secret to hold our celery.result_backend setting for consumption by airflow SecretsManagerBackend
# eg. db+postgresql://airflow:airflow@airflow-db/airflow
resource "aws_secretsmanager_secret" "result_backend" {
  name_prefix = "airflow/config/result_backend"
}
resource "aws_secretsmanager_secret_version" "result_backend" {
  secret_id = aws_secretsmanager_secret.result_backend.id
  secret_string = jsonencode([
    { "conn_type" : "db+postgresql" },
    { "login" : aws_db_instance.airflow_metadata_db.username },
    { "password" : aws_db_instance.airflow_metadata_db.password },
    { "host" : aws_db_instance.airflow_metadata_db.address },
    { "port" : aws_db_instance.airflow_metadata_db.port },
    { "schema" : aws_db_instance.airflow_metadata_db.name }
  ])
}

resource "aws_iam_policy" "secret_manager_read_secret" {
  name        = "secretManagerReadSecret"
  description = "Grants read, list and describe permissions on SecretManager secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
