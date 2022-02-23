resource "aws_secretsmanager_secret" "fernet_key" {
  name_prefix = "deploy-airflow-on-ecs-fargate/airflow/config/fernet_key/"
}

resource "aws_secretsmanager_secret_version" "fernet_key" {
  secret_id     = aws_secretsmanager_secret.fernet_key.id
  secret_string = var.fernet_key
}

# Store core.sql_alchemy_conn setting for consumption by airflow SecretsManagerBackend.
# The config options must follow the config prefix naming convention defined within the secrets backend.
# This means that sql_alchemy_conn is not defined with a connection prefix, but with "config" prefix.
# https://airflow.apache.org/docs/apache-airflow/stable/howto/set-config.html
resource "aws_secretsmanager_secret" "sql_alchemy_conn" {
  name_prefix = "deploy-airflow-on-ecs-fargate/airflow/config/sql_alchemy_conn/"
}

resource "aws_secretsmanager_secret_version" "sql_alchemy_conn" {
  secret_id     = aws_secretsmanager_secret.sql_alchemy_conn.id
  secret_string = "postgresql+psycopg2://${aws_db_instance.airflow_metadata_db.username}:${aws_db_instance.airflow_metadata_db.password}@${aws_db_instance.airflow_metadata_db.address}:${aws_db_instance.airflow_metadata_db.port}/${aws_db_instance.airflow_metadata_db.name}"
}

resource "aws_secretsmanager_secret" "celery_result_backend" {
  name_prefix = "deploy-airflow-on-ecs-fargate/airflow/config/celery_result_backend/"
}

resource "aws_secretsmanager_secret_version" "celery_result_backend" {
  secret_id     = aws_secretsmanager_secret.celery_result_backend.id
  secret_string = "db+postgresql://${aws_db_instance.airflow_metadata_db.username}:${aws_db_instance.airflow_metadata_db.password}@${aws_db_instance.airflow_metadata_db.address}:${aws_db_instance.airflow_metadata_db.port}/${aws_db_instance.airflow_metadata_db.name}"
}
