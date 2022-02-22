# deploy-airflow-on-ecs-fargate
An example of how to deploy [Apache Airflow](https://github.com/apache/airflow) on Amazon ECS Fargate.

#### Table of contents
- [Summary](#summary)
  - [Project structure](#project-structure)
- [Getting started](#getting-started)
  - [Setup a local development environment](#setup-a-local-development-environment)
  - [Setup an ECS cluster](#setup-an-ecs-cluster)
- [Standalone Tasks](#standalone-tasks)
- [Logging](#logging)
- [Cost](#cost)
- [Autoscaling](#autoscaling)
- [Examples](#examples)
  - [Run an arbitrary command as a standalone task](#run-an-arbitrary-command-as-a-standalone-task)
  - [Get a shell into a service container using ECS exec](#get-a-shell-into-a-service-container-using-ecs-exec)
  - [Manually scale a service to zero](#manually-scale-a-service-to-zero)

## Summary

The purpose of this project is to demonstrate how to deploy [Apache Airflow](https://github.com/apache/airflow) on AWS Elastic Container Service using the Fargate capacity provider. The code in this repository is meant as an example to assist programmers create their own configuration. However, one can deploy it using the steps described in [Setup an ECS cluster](#setup-an-ecs-cluster).

Airflow and ECS have many features and configuration options. This project covers many use cases. For example:
- autoscale workers to zero
- route airflow service logs to CloudWatch and to Kinesis Firehose using [fluentbit](https://fluentbit.io/)
- use [remote_logging](https://airflow.apache.org/docs/apache-airflow/stable/logging-monitoring/logging-tasks.html#logging-for-tasks) to send/receive worker logs to/from S3
- use the AWS provider [SecretsManagerBackend](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/secrets-backends/aws-secrets-manager.html) to store/consume sensitive configuration options in [SecretsManager](https://aws.amazon.com/secrets-manager/)
- run a single command as standalone ECS task (eg. `airflow db init`)
- get a shell into a running container via ECS exec
- send Airflow statsd metrics to CloudWatch

These configuration examples should prove helpful even to those who aren't running Airflow on ECS.

### Project structure

Please see the following tree for a description of the main directories/files. This layout is not based on any standard. One could move the contents of `scripts` into `deploy_airflow_on_ecs_fargate`. Files named `*_config.py` could be placed in a separate `config` directory. The location of a file is less important than the quality of the code inside it.

```
├── build .............................. anything related to building container images
│   ├── dev ............................ development config referenced by docker-compose.yml
│   └── prod ........................... production config used to build image sent to ECR
├── dags ............................... AIRFLOW_HOME/dags directory
├── deploy_airflow_on_ecs_fargate ...... arbitrary python package import-able from dags/plugins used to store config files / extra python modules
│   ├── celery_config.py ............... custom celery configuration
│   └── logging_config.py .............. custom logging configuration
├── docker-compose.yml ................. development environment build config
├── infrastructure ..................... ECS terraform configuration
│   ├── terraform.tfvars.template ...... a template variables file for defining sensitive information required to deploy infrastructure
│   └── *.tf ........................... example ECS cluster terraform configuration
├── plugins ............................ AIRFLOW_HOME/plugins directory
└── scripts
    ├── put_airflow_worker_xxx.py ...... script used by airflow_metrics ECS service to send custom autoscaling metrics to cloudwatch
    └── run_task.py .................... an example python script for running standalone tasks on the ECS cluster
```

## Getting started

### Setup a local development environment

1. Initialize the metadata db

```shell
docker compose run --rm airflow-cli db init
```

2. Create an admin user

```shell
docker compose run --rm airflow-cli users create --email airflow@example.com --firstname airflow --lastname airflow --password airflow --username airflow --role Admin
```

3. Start all services

```shell
docker compose up -d
```

### Setup an ECS cluster

1. Initialize the terraform directory
```shell
terraform -chdir=infrastructure init
```
2. (Optional) Create a `terraform.tfvars` file and set the variables `aws_region`, `metadata_db` and `fernet_key`
```
cp infrastructure/terraform.tfvars.template infrastructure/terraform.tfvars
```
3. Create the ECR repository to store the custom airflow image.
```shell
terraform -chdir=infrastructure apply -target=aws_ecr_repository.airflow
```
4. Obtain the repository URI via `awscli` or the [AWS console](https://console.aws.amazon.com/ecr/repositories).
```shell
aws ecr describe-repositories
{
    "repositories": [
        {
            "repositoryArn": "arn:aws:ecr:us-east-1:***:repository/deploy-airflow-on-ecs-fargate-airflow",
            "registryId": "***",
            "repositoryName": "deploy-airflow-on-ecs-fargate-airflow",
            "repositoryUri": "***.dkr.ecr.us-east-1.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow",
            "createdAt": "2022-02-02T06:27:15+09:00",
            "imageTagMutability": "MUTABLE",
            "imageScanningConfiguration": {
                "scanOnPush": true
            },
            "encryptionConfiguration": {
                "encryptionType": "AES256"
            }
        }
    ]
}
```
5. Authenticate your preferred container image build tool with AWS. The following works with Docker and [Podman](https://podman.io/).
```shell
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ***.dkr.ecr.us-east-1.amazonaws.com
```
6. Build and push the container image.
```shell
export REPO_URI="***.dkr.ecr.us-east-1.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow"
docker buildx build -t "${REPO_URI}" -f build/prod/Containerfile --platform linux/amd64 .
docker push "${REPO_URI}"
```
7. Deploy the remaining infrastructure.
```shell
terraform -chdir=infrastructure apply
```
8. Initialize the airflow metadata database. Here we run the `db init` command as a standalone ECS task.
```shell
python3 scripts/run_task.py --wait-tasks-stopped --command 'db init'
```
9. Create an admin user using the same method as `db init`.
```shell
python3 scripts/run_task.py --wait-tasks-stopped --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```
10. Find and open the airflow webserver load balancer URI.
```shell
aws elbv2 describe-load-balancers
{
    "LoadBalancers": [
        {
            "DNSName": "airflow-webserver-231209530.us-east-1.elb.amazonaws.com",
	    (..redacted)
        }
    ]
}
```

<img width="1563" alt="airflow-home" src="https://user-images.githubusercontent.com/11639738/151594663-0895e62e-2fb3-4a6d-8bd5-98e9d8f1af90.png">

## Standalone Tasks

A common requirement is the ability to execute an arbitrary command in the cluster context. AWS provides the [run-task](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_run_task.html) API for this purpose.

The terraform code in this repository registers a template task definition named `airflow-standalone-task`. To run arbitrary commands on the ECS cluster, override the default parameters in the task definition when calling `run-task`. For example, one can run the command `airflow db init` while specifying 1024 memory and 512 cpu.

```shell
python3 scripts/run_task.py --cpu 512 --memory 1024 --command 'db init'
```

## Logging

This repository demonstrates various logging configurations.

Component | Log destination
:- | :-
Airflow Webserver, Scheduler & Metrics | CloudWatch
Airflow Standalone Task | S3 via Kinesis Firehose (query-able with Athena)
Airflow Worker | S3 via Airflow's builtin remote log handler

## Cost

A conservative estimate **excluding free tier** in which all ECS services run 24 hours a day (workers run at max capacity for 6 hours) costs around 200 USD per month. A similar configuration with [Amazon Managed Workflows for Apache Airflow (MWAA)](https://aws.amazon.com/managed-workflows-for-apache-airflow) will cost at least 360 USD per month.

One can further limit costs by decreasing the max number of workers, or stopping the webserver and scheduler at night.

## Autoscaling

Airflow workers scale between 0-5 based on the current number of running, unpaused Airflow tasks. The Airflow statsd module does not provide this exact information, so I created a separate "metrics" ECS service to periodically query the metadata-db, compute the "desired worker count" using formulas described in the [MWAA documentation](https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-autoscaling.html) and [this AWS blog post](https://aws.amazon.com/blogs/containers/deep-dive-on-amazon-ecs-cluster-auto-scaling/), and send the custom metric data to CloudWatch. Metric data sent to CloudWatch is then used in a [target tracking scaling policy](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html) to scale worker service containers.

The webserver and scheduler each scale to 1 in the morning and 0 at night using scheduled autoscaling. One could go a step further by using the `ALBRequestCountPerTarget` predefined metric to scale the webserver via a target tracking scaling policy.

## Examples

### Run an arbitrary command as a standalone task

As described [above](#standalone-tasks), this repository registers a task definition named `airflow-standalone-task` for the purpose of running one-off commands in the cluster context. Take a look inside `scripts/run_task.py` to see how one can use the run-task API to override options like `command`, `cpu` and `memory` when running a standalone task.

```shell
python3 scripts/run_task.py --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```

### Get a shell into a service container using [ECS exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)

One can use [ECS exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html) to get a shell into a running container. Install the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for `awscli`, obtain the ID of the task container and execute the following command.

```shell
aws ecs execute-command --cluster airflow --task 9db18526dd8341169fbbe3e2b74547fb --container scheduler --interactive --command "/bin/bash"
```

If successful, a terminal prompt will appear.

```shell
The Session Manager plugin was installed successfully. Use the AWS CLI to start a session.


Starting session with SessionId: ecs-execute-command-0d94b5b2472323b7d
root@9db18526dd8341169fbbe3e2b74547fb-2568554522:/opt/airflow# ls -la
total 52
drwxrwxr-x 1 airflow root 4096 Feb  1 22:41 .
drwxr-xr-x 1 root    root 4096 Jan 17 23:22 ..
-rw-r--r-- 1 airflow root 1854 Feb  1 22:37 airflow.cfg
drwxrwxr-x 1 airflow root 4096 Feb  1 21:28 dags
drwxr-xr-x 1 airflow root 4096 Feb  1 21:28 deploy_airflow_on_ecs_fargate
drwxrwxr-x 1 airflow root 4096 Feb  1 22:41 logs
drwxr-xr-x 2 airflow root 4096 Feb  1 21:28 plugins
-rw-r--r-- 1 airflow root  199 Jan 31 00:45 requirements.txt
-rw-rw-r-- 1 airflow root 4695 Feb  1 22:41 webserver_config.py
root@9db18526dd8341169fbbe3e2b74547fb-2568554522:/opt/airflow# whoami
root
```

ECS exec may fail to create a session and display the following message. If this happens, one can often mitigate the problem by forcing a new container deployment.

```
An error occurred (InvalidParameterException) when calling the ExecuteCommand operation: The execute command failed because execute command was not enabled when the task was run or the execute command agent isn’t running. Wait and try again or run a new task with execute command enabled and try again.
```

### Manually scale a service to zero

There are multiple ways to scale services. Here are some options using the commandline.

#### Update the service definition

One can change the desired task count of a service via the `update-service` API. Scaling actions take effect immediately.

```shell
aws ecs update-service --cluster airflow --service airflow-webserver --desired-count 0
```
#### Use a scheduled autoscaling action

If the service is registered as an autoscaling target (it is in this project), one can also set the desired count via a scheduled autoscaling action. This may be helpful if one wants to scale to N at a certain time.

```shell
# macos
export TWO_HOURS_LATER=$(date -u -v+2H '+%Y-%m-%dT%H:%M:00')

# linux
export TWO_HOURS_LATER=$(date -u --date='2 hours' '+%Y-%m-%dT%H:%M:00')

aws application-autoscaling put-scheduled-action \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/airflow/airflow-webserver \
  --scheduled-action-name scale-webserver-to-zero \
  --schedule "at(${TWO_HOURS_LATER})" \
  --scalable-target-action MinCapacity=0,MaxCapacity=0
```
