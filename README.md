# deploy-airflow-on-ecs-fargate
An example of how to deploy [Apache Airflow](https://github.com/apache/airflow) on Amazon ECS Fargate

#### Table of contents
- [Project structure](#project-structure)
- [Getting started](#getting-started)
  - [Setup a local development environment](#setup-a-local-development-environment)
  - [Setup an ECS cluster](#setup-an-ecs-cluster)
- [Autoscaling](#autoscaling)
- [Standalone Tasks](#standalone-tasks)
- [Examples](#examples)

### Project structure

```
├── build .............................. anything related to building container images
│   ├── dev ............................ development image referenced by docker-compose.yml
│   ├── prod ........................... production image uploaded to ECR
│   └── requirements ................... pypi packages installed container images
├── dags ............................... mapped to AIRFLOW_HOME/dags
├── deploy_airflow_on_ecs_fargate ...... import-able python package for configuration files / use in dags (mapped to AIRFLOW_HOME/deploy_airflow_on_ecs_fargate)
│   ├── celery_config.py ............... custom celery configuration
│   └── logging_config.py .............. custom logging configuration
├── docker-compose.yml
├── infrastructure ..................... ECS terraform configuration
│   ├── terraform.tfvars.template ...... a template for defining sensitive variables required to deploy infrastructure
│   └── *.tf ........................... example ECS cluster terraform configuration
├── plugins ............................ mapped to AIRFLOW_HOME/plugins
└── scripts
    └── run_task.py .................... an example python script for running standalone tasks on the ECS cluster
```

## Getting started

### Setup a local development environment

```
docker compose up -d
docker compose run --rm airflow-cli db init
docker compose run --rm airflow-cli users create --email airflow@example.com --firstname airflow --lastname airflow --password airflow --username airflow --role Admin
```

### Setup an ECS cluster

1. Create the ECR repository to store the customized airflow image.
```shell
$ terraform -chdir=infrastructure apply -target=aws_ecr_repository.airflow
```

2. Obtain the repository URI via `awscli` or the [AWS console](https://console.aws.amazon.com/ecr/repositories).
```shell
$ aws ecr describe-repositories
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
3. Authenticate your preferred container image build tool with AWS.
```shell
$ aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ***.dkr.ecr.us-east-1.amazonaws.com
```
4. Build and push the container image.
```shell
$ export REPO_URI="***.dkr.ecr.us-east-1.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow"
$ docker buildx build -t "${REPO_URI}" -f build/prod/Containerfile --platform linux/amd64 .
$ docker push "${REPO_URI}"
```
5. Deploy the remaining infrastructure.
```shell
$ terraform -chdir=infrastructure plan
$ terraform -chdir=infrastructure apply
```
6. Initialize the airflow metadata database.
```shell
$ python3 scripts/run_task.py --public-subnet-ids subnet-*** --security-group sg-*** --command 'db init'
```
7. Create an admin user.
```shell
$ python3 scripts/run_task.py --public-subnet-ids subnet-*** --security-group sg-*** --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```
8. Find and open the airflow webserver load balancer URI.
```shell
$ aws elbv2 describe-load-balancers
{
    "LoadBalancers": [
        {
            "DNSName": "airweb20220201213050041900000016-231209530.us-east-1.elb.amazonaws.com",
	    (..redacted)
        }
    ]
}
```

<img width="1563" alt="airflow-home" src="https://user-images.githubusercontent.com/11639738/151594663-0895e62e-2fb3-4a6d-8bd5-98e9d8f1af90.png">

### Standalone Tasks

A common need is to be able to execute an arbitrary command in the cluster context. For this purpose, AWS has the [run-task](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_run_task.html) API.

This repository contains terraform code to register a template task definition named "airflow-standalone-task" for use with run-task. When we want to submit a standalone workload to the ECS cluster, we can run `aws ecs run-task` and specify the standalone task definition as well as override container definition parameters like cpu, memory and command. This gives us the ability to run arbitrary commands with customized resources.

### Autoscaling

The autoscaling policies documented in this repository are just examples based on personal preference. They may not be exactly what you need, but do offer a good starting point.

Autoscaling is accomplished in a different way depending on the component type. The webserver and scheduler use [scheduled scaling](https://docs.aws.amazon.com/autoscaling/application/userguide/application-auto-scaling-scheduled-scaling.html) to scale to zero at night (assuming you have no tasks running overnight) and 1 during the day. The number of celery workers increases and decreases in steps based on 2 Cloud Watch alarms tracking the SQS celery broker.
1. When `ApproximateNumberOfMessagesVisible` exceeds zero, we increase the number of tasks by 1. We check this condition every 60 seconds.
2. When `NumberOfEmptyReceives` exceeds zero for 15 consecutive minutes, we decrease the number of tasks by 1.

### Examples

#### Run an arbitrary workload as a standalone task
```shell
$ python3 scripts/run_task.py --public-subnet-ids subnet-*** --security-group sg-*** --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```

#### Get a shell into a service container using [ECS exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html).

This step requires your to first install the `awscli` [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).
```shell
$ aws ecs execute-command --cluster airflow --task 9db18526dd8341169fbbe3e2b74547fb --container scheduler --interactive --command "/bin/bash"

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

Sometimes ECS exec will fail with the following message:
```
An error occurred (InvalidParameterException) when calling the ExecuteCommand operation: The execute command failed because execute command was not enabled when the task was run or the execute command agent isn’t running. Wait and try again or run a new task with execute command enabled and try again.
```
If this happens, you can often mitigate the problem by forcing a new container deployment.

#### Manually scale the webserver to zero
```shell
# macos
$ export TWO_MINUTES_LATER=$(date -u -v+2M '+%Y-%m-%dT%H:%M:00')
# linux
$ export TWO_MINUTES_LATER=$(date -u --date='2 minutes' '+%Y-%m-%dT%H:%M:00')
$ docker run --rm -v "${HOME}/.aws:/root/.aws" amazon/aws-cli application-autoscaling put-scheduled-action \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/airflow/airflow-webserver \
  --scheduled-action-name scale-webserver-to-zero \
  --schedule "at(${TWO_MINUTES_LATER})" \
  --scalable-target-action MinCapacity=0,MaxCapacity=0
$ aws application-autoscaling describe-scheduled-actions --service-namespace ecs
{
    [
        (..redacted)
        {
            "ScheduledActionName": "single-scalein-action-test",
            "ScheduledActionARN": "arn:aws:autoscaling:us-east-1:***:scheduledAction:***:resource/ecs/service/airflow/airflow-webserver:scheduledActionName/single-scalein-action-test",
            "ServiceNamespace": "ecs",
            "Schedule": "at(2022-01-28T17:19:00)",
            "ResourceId": "service/airflow/airflow-webserver",
            "ScalableDimension": "ecs:service:DesiredCount",
            "ScalableTargetAction": {
                "MinCapacity": 1,
                "MaxCapacity": 1
            },
            "CreationTime": "2022-01-28T16:50:07.802000+00:00"
        }
    ]
}
```

### Notes
- To avoid collisions with other AWS resource, I often use `name_prefix` instead of `name` in terraform configuration files. This is also useful for resources like SecretManager secrets, which require a 7 day wait period before full deletion.

### Todo
- How many times does the airflow worker poll in 300 seconds? That should be the `NumberOfEmptyReceives` threshold, not zero.
