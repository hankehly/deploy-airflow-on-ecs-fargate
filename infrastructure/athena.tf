resource "aws_glue_catalog_database" "main" {
  name = "deploy_airflow_on_ecs_fargate"
}

locals {
  table_type = "EXTERNAL_TABLE"
  parameters = {
    EXTERNAL                            = "TRUE"
    "projection.datehour.type"          = "date"
    "projection.datehour.range"         = "2022/01/01/00,NOW"
    "projection.datehour.format"        = "yyyy/MM/dd/HH"
    "projection.datehour.interval"      = "1"
    "projection.datehour.interval.unit" = "HOURS"
    "projection.enabled"                = "true"
  }
  storage_descriptor = {
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info = {
      serialization_library = "org.apache.hive.hcatalog.data.JsonSerDe"
      parameters = {
        "serialization.format"  = "1"
        "ignore.malformed.json" = "true"
      }
    }
    columns = [
      {
        name = "source"
        type = "string"
      },
      {
        name = "log"
        type = "string"
      },
      {
        name = "container_id"
        type = "string"
      },
      {
        name = "container_name"
        type = "string"
      },
      {
        name = "ecs_cluster"
        type = "string"
      },
      {
        name = "ecs_task_arn"
        type = "string"
      },
      {
        name = "ecs_task_definition"
        type = "string"
      },
      {
        name = "timestamp"
        type = "string"
      }
    ]
  }
}

resource "aws_glue_catalog_table" "airflow_worker_logs" {
  name          = "airflow_worker_logs"
  database_name = aws_glue_catalog_database.main.name
  table_type    = local.table_type
  parameters = merge(
    local.parameters,
    { "storage.location.template" = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-worker/$${datehour}/" }
  )
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-worker"
    input_format  = local.storage_descriptor.input_format
    output_format = local.storage_descriptor.output_format
    ser_de_info {
      serialization_library = local.storage_descriptor.ser_de_info.serialization_library
      parameters            = local.storage_descriptor.ser_de_info.parameters
    }
    dynamic "columns" {
      for_each = local.storage_descriptor.columns
      content {
        name = columns.value["name"]
        type = columns.value["type"]
      }
    }
  }
  partition_keys {
    name = "datehour"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "airflow_scheduler_logs" {
  name          = "airflow_scheduler_logs"
  database_name = aws_glue_catalog_database.main.name
  table_type    = local.table_type
  parameters = merge(
    local.parameters,
    { "storage.location.template" = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-scheduler/$${datehour}/" }
  )
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-scheduler"
    input_format  = local.storage_descriptor.input_format
    output_format = local.storage_descriptor.output_format
    ser_de_info {
      serialization_library = local.storage_descriptor.ser_de_info.serialization_library
      parameters            = local.storage_descriptor.ser_de_info.parameters
    }
    dynamic "columns" {
      for_each = local.storage_descriptor.columns
      content {
        name = columns.value["name"]
        type = columns.value["type"]
      }
    }
  }
  partition_keys {
    name = "datehour"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "airflow_webserver_logs" {
  name          = "airflow_webserver_logs"
  database_name = aws_glue_catalog_database.main.name
  table_type    = local.table_type
  parameters = merge(
    local.parameters,
    { "storage.location.template" = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-webserver/$${datehour}/" }
  )
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-webserver"
    input_format  = local.storage_descriptor.input_format
    output_format = local.storage_descriptor.output_format
    ser_de_info {
      serialization_library = local.storage_descriptor.ser_de_info.serialization_library
      parameters            = local.storage_descriptor.ser_de_info.parameters
    }
    dynamic "columns" {
      for_each = local.storage_descriptor.columns
      content {
        name = columns.value["name"]
        type = columns.value["type"]
      }
    }
  }
  partition_keys {
    name = "datehour"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "airflow_metrics_logs" {
  name          = "airflow_metrics_logs"
  database_name = aws_glue_catalog_database.main.name
  table_type    = local.table_type
  parameters = merge(
    local.parameters,
    { "storage.location.template" = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-metrics/$${datehour}/" }
  )
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.airflow.bucket}/kinesis-firehose/airflow-metrics"
    input_format  = local.storage_descriptor.input_format
    output_format = local.storage_descriptor.output_format
    ser_de_info {
      serialization_library = local.storage_descriptor.ser_de_info.serialization_library
      parameters            = local.storage_descriptor.ser_de_info.parameters
    }
    dynamic "columns" {
      for_each = local.storage_descriptor.columns
      content {
        name = columns.value["name"]
        type = columns.value["type"]
      }
    }
  }
  partition_keys {
    name = "datehour"
    type = "string"
  }
}
