import argparse
import time
from contextlib import contextmanager
from enum import Enum

import botocore.session
from airflow.models import DagModel, DagRun
from airflow.settings import Session
from sqlalchemy import func


@contextmanager
def session_scope(session):
    try:
        yield session
    finally:
        session.close()


class DagRunState(str, Enum):
    RUNNING = "running"

    def __str__(self) -> str:
        return self.value


def get_number_of_active_running_dags() -> int:
    """
    Get the total number of active (non-paused) dag runs in "running" state
    """
    with session_scope(Session) as session:
        dag_status_query = (
            session.query(
                DagRun.dag_id,
                func.count("*").label("count"),
            )
            .filter(DagRun.state == DagRunState.RUNNING)
            .group_by(DagRun.dag_id)
            .subquery()
        )
        count = (
            session.query(
                func.sum(dag_status_query.c.count),
            )
            .join(DagModel, DagModel.dag_id == dag_status_query.c.dag_id)
            .filter(DagModel.is_active == True, DagModel.is_paused == False)
            .scalar()
        )
        return 0 if count is None else int(count)


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
    args = parser.parse_args()
    session = botocore.session.get_session()
    cloudwatch = session.create_client("cloudwatch", region_name=args.region_name)
    while True:
        count = get_number_of_active_running_dags()
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
                    "Value": count,
                    "Unit": "Count",
                },
            ],
        )
        time.sleep(args.period)
