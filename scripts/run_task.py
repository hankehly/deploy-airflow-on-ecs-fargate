import argparse
import sys
from textwrap import dedent
from typing import List

if sys.version_info.major < 3:
    print("Please try again with python version 3+")
    sys.exit(1)

try:
    import botocore.session
except ImportError:
    print("Please install botocore and try again")
    print("python -m pip install botocore")
    sys.exit(1)


def list_public_subnet_ids(botocore_ec2_client, vpc_name: str) -> List[str]:
    """
    Use botocore_ec2_client to obtain a list of public subnet ids for vpc named {vpc_name}
    """
    vpcs = botocore_ec2_client.describe_vpcs(
        Filters=[{"Name": "tag:Name", "Values": ["deploy-airflow-on-ecs-fargate"]}]
    )
    if not vpcs["Vpcs"]:
        raise Exception(f"Vpc with tag:Name='{vpc_name}' does not exist")

    vpc_id = vpcs["Vpcs"][0]["VpcId"]
    subnets = botocore_ec2_client.describe_subnets(
        Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
    )
    public_subnet_ids = [
        subnet["SubnetId"]
        for subnet in subnets["Subnets"]
        if subnet["MapPublicIpOnLaunch"]
    ]
    return public_subnet_ids


def get_security_group_id(botocore_ec2_client, security_group_name: str) -> str:
    """
    Use botocore_ec2_client to obtain the id of the security group named {security_group_name}
    """
    res = botocore_ec2_client.describe_security_groups(
        Filters=[{"Name": "group-name", "Values": [security_group_name]}]
    )
    if not res["SecurityGroups"]:
        raise Exception(
            f"Security group where tag:Name='{security_group_name}' does not exist"
        )
    return res["SecurityGroups"][0]["GroupId"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description=dedent(
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
    parser.add_argument(
        "--profile",
        type=str,
        default="default",
        help="The name of the awscli profile to use. Defaults to 'default'.",
    )
    parser.add_argument(
        "--vpc-name",
        type=str,
        default="deploy-airflow-on-ecs-fargate",
        help="The name of the ECS cluster VPC. Defaults to 'deploy-airflow-on-ecs-fargate'.",
    )
    parser.add_argument(
        "--security-group-name",
        type=str,
        default="airflow-standalone-task",
        help="The name of the standalone task security group. Defaults to 'airflow-standalone-task'.",
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
    parser.add_argument(
        "--wait-tasks-stopped",
        action="store_true",
        default=False,
        help="After calling run-task, wait  until the task status returns STOPPED",
    )
    parser.add_argument(
        "--cpu",
        type=int,
        default=1024,
        help="Specify cpu as an integer. Defaults to 1024.",
    )
    parser.add_argument(
        "--memory",
        type=int,
        default=2048,
        help="Specify memory as an integer. Defaults to 2048.",
    )
    parser.add_argument(
        "--capacity-provider",
        type=str,
        default="FARGATE",
        choices=["FARGATE", "FARGATE_SPOT"],
    )
    args = parser.parse_args()
    print("Arguments valid")

    print("Finding public subnet ids")
    session = botocore.session.Session(profile=args.profile)
    ec2_client = session.create_client("ec2")
    public_subnet_ids = list_public_subnet_ids(ec2_client, args.vpc_name)

    if not public_subnet_ids:
        raise Exception(f"No public subnets available on VPC '{args.vpc_name}'")

    print("Finding security group id")
    security_group_id = get_security_group_id(ec2_client, args.security_group_name)

    print("Submitting task to cluster")
    ecs_client = session.create_client("ecs")
    response = ecs_client.run_task(
        capacityProviderStrategy=[{"capacityProvider": args.capacity_provider}],
        cluster=args.cluster,
        count=1,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": public_subnet_ids,
                "securityGroups": [security_group_id],
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
        },
        platformVersion="1.4.0",
        taskDefinition=args.task_definition,
    )
    task_arn = response["tasks"][0]["taskArn"]
    print(f"Task arn: {task_arn}")
    if args.wait_tasks_stopped:
        print("Waiting until task stops")
        waiter = ecs_client.get_waiter("tasks_stopped")
        waiter.wait(cluster=args.cluster, tasks=[task_arn])
    print("Done")
