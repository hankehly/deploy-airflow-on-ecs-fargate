import argparse
import datetime
import logging
import sys
import time
import datetime
from contextlib import contextmanager
from typing import List

from airflow.models import DagModel, TaskInstance
from airflow.settings import Session
from airflow.utils.state import State
from sqlalchemy import func

import botocore.session

logging.basicConfig(level=logging.INFO, stream=sys.stdout)


@contextmanager
def session_scope(session):
    """Provide a transactional scope around a series of operations."""
    try:
        yield session
    finally:
        session.close()


def get_task_count_where_state(states: List[str]) -> int:
    """
    Returns the number of tasks in one of {states}

    See below for a list of possible states for a Task Instance
    https://airflow.apache.org/docs/apache-airflow/stable/concepts/tasks.html#task-instances
    """
    with session_scope(Session) as session:
        tasks_query = (
            session.query(
                TaskInstance.dag_id,
                func.count("*").label("count"),
            )
            .filter(TaskInstance.state.in_(states))
            .group_by(TaskInstance.dag_id)
            .subquery()
        )
        count = (
            session.query(func.sum(tasks_query.c.count))
            .join(DagModel, DagModel.dag_id == tasks_query.c.dag_id)
            .filter(
                DagModel.is_active == True,
                DagModel.is_paused == False,
            )
            .scalar()
        )
        if count is None:
            return 0
        return int(count)


# Publish a custom metric for worker scaling
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html
if __name__ == "__main__":
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
    parser.add_argument(
        "--worker-service-name",
        type=str,
        required=True,
        help="The name of the airflow worker ECS service.",
    )
    args = parser.parse_args()
    logging.info("Arguments parsed successfully")

    session = botocore.session.get_session()
    cloudwatch = session.create_client("cloudwatch", region_name=args.region_name)
    ecs = session.create_client("ecs", region_name=args.region_name)

    while True:
        task_count = get_task_count_where_state(states=[State.QUEUED, State.RUNNING])
        logging.info(f"Number of tasks in queued/running state: {task_count}")

        worker_service = ecs.describe_services(
            cluster=args.cluster_name, services=[args.worker_service_name]
        )["services"][0]
        worker_count = worker_service["pendingCount"] + worker_service["runningCount"]
        logging.info(f"Number of workers: {worker_count}")

        if worker_count == 0:
            tasks_per_worker = task_count
        else:
            tasks_per_worker = task_count / worker_count
        logging.info(f"Tasks per worker: {tasks_per_worker}")

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
                    "Value": tasks_per_worker,
                    "Unit": "Count",
                },
            ],
        )
        logging.info(f"Sleeping for {args.period} seconds")
        time.sleep(args.period)
