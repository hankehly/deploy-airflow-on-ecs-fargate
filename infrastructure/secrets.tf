# A secret to hold our core.fernet_key setting for consumption by airflow SecretsManagerBackend
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret
resource "aws_secretsmanager_secret" "fernet_key" {
  name_prefix = "deploy-airflow-on-ecs-fargate/airflow/config/fernet_key/"
}
resource "aws_secretsmanager_secret_version" "fernet_key" {
  secret_id     = aws_secretsmanager_secret.fernet_key.id
  secret_string = var.fernet_key
}

# A secret to hold our core.sql_alchemy_conn setting for consumption by airflow SecretsManagerBackend
# eg. postgresql+psycopg2://airflow:airflow@airflow-db/airflow
# Gotcha: The config options must follow the config prefix naming convention defined within the secrets backend.
#  This means that sql_alchemy_conn is not defined with a connection prefix, but with config prefix.
#  For example it should be named as deploy-airflow-on-ecs-fargate/airflow/config/sql_alchemy_conn
#  https://airflow.apache.org/docs/apache-airflow/stable/howto/set-config.html
resource "aws_secretsmanager_secret" "sql_alchemy_conn" {
  name_prefix = "deploy-airflow-on-ecs-fargate/airflow/config/sql_alchemy_conn/"
}
resource "aws_secretsmanager_secret_version" "sql_alchemy_conn" {
  secret_id     = aws_secretsmanager_secret.sql_alchemy_conn.id
  secret_string = "postgresql+psycopg2://${aws_db_instance.airflow_metadata_db.username}:${aws_db_instance.airflow_metadata_db.password}@${aws_db_instance.airflow_metadata_db.address}:${aws_db_instance.airflow_metadata_db.port}/${aws_db_instance.airflow_metadata_db.name}"
}

# A secret to hold our celery.result_backend setting for consumption by airflow SecretsManagerBackend
# eg. db+postgresql://airflow:airflow@airflow-db/airflow
resource "aws_secretsmanager_secret" "celery_result_backend" {
  name_prefix = "deploy-airflow-on-ecs-fargate/airflow/config/celery_result_backend/"
}
resource "aws_secretsmanager_secret_version" "celery_result_backend" {
  secret_id     = aws_secretsmanager_secret.celery_result_backend.id
  secret_string = "db+postgresql://${aws_db_instance.airflow_metadata_db.username}:${aws_db_instance.airflow_metadata_db.password}@${aws_db_instance.airflow_metadata_db.address}:${aws_db_instance.airflow_metadata_db.port}/${aws_db_instance.airflow_metadata_db.name}"
}
