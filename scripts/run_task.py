import argparse
import sys
import textwrap

if sys.version_info.major < 3:
    print("Please try again with python version 3+")
    sys.exit(1)

try:
    import botocore.session
except ImportError:
    print("Please install botocore and try again")
    print("python -m pip install botocore")
    sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description=textwrap.dedent(
            """
            Examples
            --------
            Initialize the db
            $ python3 scripts/run_task.py --public-subnet-ids subnet-xxx --security-group sg-xxx --command 'db init'

            Create an admin user
            $ python3 scripts/run_task.py --public-subnet-ids subnet-xxx --security-group sg-xxx --command \\
                'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
            """
        ),
    )
    parser.add_argument(
        "--cluster",
        type=str,
        default="airflow",
        help="The name of the target cluster. Defaults to 'airflow'.",
    )
    parser.add_argument(
        "--task-definition",
        type=str,
        default="airflow-standalone-task",
        help="The name of the standalone task definition. Defaults to 'airflow-standalone-task'.",
    )
    parser.add_argument(
        "--container-name",
        type=str,
        default="airflow",
        help="The name of the container in the standalone task definition. Defaults to 'airflow'.",
    )
    parser.add_argument("--profile", type=str, default="default")
    parser.add_argument(
        "--public-subnet-ids",
        type=str,
        nargs="+",
        required=True,
        help=(
            "Required to pull images from ECR. You could instead specify the VPC name "
            "and look-up the public subnet ids dynamically, but this would be out of "
            "the scope of this demonstration."
        ),
    )
    parser.add_argument(
        "--security-group",
        type=str,
        required=True,
        help="Specify the airflow standalone task security group id.",
    )
    parser.add_argument(
        "--command",
        type=str,
        required=True,
        help=(
            "Specify the command string *as a single string* to prevent parsing errors "
            "(eg. 'users create --role Admin')"
        ),
    )
    parser.add_argument("--cpu", type=int, default=1024)
    parser.add_argument("--memory", type=int, default=2048)
    parser.add_argument(
        "--capacity-provider",
        type=str,
        default="FARGATE",
        choices=["FARGATE", "FARGATE_SPOT"],
    )
    args = parser.parse_args()
    print("Arguments valid. Running task.")
    session = botocore.session.Session(profile=args.profile)
    client = session.create_client("ecs")
    client.run_task(
        capacityProviderStrategy=[{"capacityProvider": args.capacity_provider}],
        cluster=args.cluster,
        count=1,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": args.public_subnet_ids,
                "securityGroups": [args.security_group],
                "assignPublicIp": "ENABLED",
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": args.container_name,
                    "command": args.command.split(" "),
                    "cpu": args.cpu,
                    "memory": args.memory,
                },
            ],
            "cpu": str(args.cpu),
            "memory": str(args.memory),
            "ephemeralStorage": {"sizeInGiB": 123},
        },
        platformVersion="1.4.0",
        referenceId="string",
        taskDefinition=args.task_definition,
    )
    print("Task submitted.")
