# Common Kinesis Firehose role
resource "aws_iam_role" "airflow_firehose" {
  name_prefix = "airflow-firehose-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })
}

# Permissions for firehose to access S3
# https://docs.aws.amazon.com/firehose/latest/dev/controlling-access.html
resource "aws_iam_policy" "airflow_firehose" {
  name_prefix = "airflow-firehose-"
  path        = "/"
  description = ""
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        Resource = [
          aws_s3_bucket.airflow.arn,
          # In a production environment, you may want to further restrict access to the
          # bucket by specifying a prefix. For this demonstration, we grant Kinesis
          # access to all directories
          "${aws_s3_bucket.airflow.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "airflow_firehose" {
  role       = aws_iam_role.airflow_firehose.name
  policy_arn = aws_iam_policy.airflow_firehose.arn
}
