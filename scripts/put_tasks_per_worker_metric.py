import argparse
import datetime
import logging
import sys
import time

import botocore.session

logging.basicConfig(level=logging.INFO, stream=sys.stdout)


def _build_metric_data_queries(namespace: str, period: int = 60):
    return [
        {
            "Id": "queued_tasks",
            "MetricStat": {
                "Metric": {
                    "Namespace": namespace,
                    "MetricName": "airflow_executor_queued_tasks",
                    "Dimensions": [
                        {"Name": "metric_type", "Value": "gauge"},
                    ],
                },
                "Period": period,
                "Stat": "Average",
            },
            # When used in GetMetricData , this option indicates whether to return
            # the timestamps and raw data values of this metric. If you are performing
            # this call just to do math expressions and do not also need the raw data
            # returned, you can specify False . If you omit this, the default of True is used.
            "ReturnData": False,
        },
        {
            "Id": "running_tasks",
            "MetricStat": {
                "Metric": {
                    "Namespace": namespace,
                    "MetricName": "airflow_executor_running_tasks",
                    "Dimensions": [
                        {"Name": "metric_type", "Value": "gauge"},
                    ],
                },
                "Period": period,
                "Stat": "Average",
            },
            "ReturnData": False,
        },
        {
            "Id": "running_worker_count",
            "MetricStat": {
                "Metric": {
                    "Namespace": "ECS/ContainerInsights",
                    "MetricName": "RunningTaskCount",
                    "Dimensions": [
                        {"Name": "ClusterName", "Value": "airflow"},
                        {"Name": "ServiceName", "Value": "airflow-worker"},
                    ],
                },
                "Period": period,
                "Stat": "Average",
            },
            "ReturnData": False,
        },
        {
            "Id": "pending_worker_count",
            "MetricStat": {
                "Metric": {
                    "Namespace": "ECS/ContainerInsights",
                    "MetricName": "PendingTaskCount",
                    "Dimensions": [
                        {"Name": "ClusterName", "Value": "airflow"},
                        {"Name": "ServiceName", "Value": "airflow-worker"},
                    ],
                },
                "Period": period,
                "Stat": "Average",
            },
            "ReturnData": False,
        },
        {
            "Id": "worker_count",
            "Expression": "running_worker_count + pending_worker_count",
            "ReturnData": False,
        },
        {
            "Id": "task_count",
            "Expression": "queued_tasks + running_tasks",
            "ReturnData": False,
        },
        {
            "Id": "tasks_per_worker",
            "Expression": "task_count / worker_count",
        },
    ]


# Publish a custom metric for worker scaling
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html
if __name__ == "__main__":
    logging.info("Script started")
    parser = argparse.ArgumentParser()
    parser.add_argument("--namespace", type=str, required=True, help="Metric namespace")
    parser.add_argument(
        "--cluster-name",
        type=str,
        required=True,
        help="Cluster name used as metric dimension",
    )
    parser.add_argument("--metric-name", type=str, required=True)
    parser.add_argument(
        "--period",
        type=int,
        default=60,
        help="The interval (in seconds) to call the put_metric_data API",
    )
    parser.add_argument(
        "--region-name", type=str, required=True, help="AWS region name"
    )
    args = parser.parse_args()
    logging.info("Arguments parsed successfully")
    session = botocore.session.get_session()
    cloudwatch = session.create_client("cloudwatch", region_name=args.region_name)
    metric_data_queries = _build_metric_data_queries(args.namespace)
    while True:
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        logging.info(f"Get metric data for '{now}'")
        metric_data = cloudwatch.get_metric_data(
            MetricDataQueries=metric_data_queries,
            StartTime=now - datetime.timedelta(minutes=5),
            EndTime=now,
        )
        tasks_per_worker = next(
            filter(lambda v: v["Id"] == "tasks_per_worker", metric_data)
        )
        value_latest = tasks_per_worker["Values"][0]
        logging.info(f"Put metric data: {value_latest}")
        cloudwatch.put_metric_data(
            Namespace=args.namespace,
            MetricData=[
                {
                    "MetricName": args.metric_name,
                    "Dimensions": [
                        {
                            "Name": "ClusterName",
                            "Value": args.cluster_name,
                        }
                    ],
                    "Value": value_latest,
                    "Unit": "Count",
                },
            ],
        )
        logging.info(f"Sleeping for {args.period} seconds")
        time.sleep(args.period)
