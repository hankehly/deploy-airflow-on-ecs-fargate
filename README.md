# deploy-airflow-on-ecs-fargate
An example of how to deploy Apache Airflow on Amazon ECS Fargate

- [Project structure](#project-structure)
- [Setup local](#setup-local)

### Project structure

```
├── Makefile
├── README.md
├── build .............................. anything related to building container images
│   ├── dev ............................ development image referenced by docker-compose.yml
│   │   ├── Containerfile
│   │   └── airflow.cfg
│   ├── prod ........................... production image uploaded to ECR
│   │   ├── Containerfile
│   │   └── airflow.cfg
│   └── requirements ................... pypi packages installed container images
│       ├── requirements.dev.txt
│       └── requirements.txt
├── dags
│   └── example_bash_operator.py ....... mapped to AIRFLOW_HOME/dags
├── deploy_airflow_on_ecs_fargate ...... import-able python package for configuration files / use in dags (mapped to AIRFLOW_HOME/deploy_airflow_on_ecs_fargate)
│   ├── __init__.py
│   ├── celery_config.py ............... custom celery configuration
│   └── logging_config.py .............. custom logging configuration
├── docker-compose.yml
├── infrastructure ..................... ECS terraform configuration
│   ├── airflow_metadata_db.tf
│   ├── airflow_scheduler.tf
│   ├── airflow_standalone_task.tf
│   ├── airflow_webserver.tf
│   ├── airflow_worker.tf
│   ├── celery_broker.tf
│   ├── ecr.tf
│   ├── ecs_cluster.tf
│   ├── main.tf
│   ├── secrets.tf
│   ├── terraform.tfvars.template ...... a template for defining sensitive variables required to deploy infrastructure
│   └── vpc.tf
├── plugins ............................ mapped to AIRFLOW_HOME/plugins
└── scripts
    └── run_task.py .................... an example python script for running standalone tasks on the ECS cluster
```

### Setup local
```
docker compose up -d
docker compose run --rm airflow-cli db init
docker compose run --rm airflow-cli users create --email airflow@example.com --firstname airflow --lastname airflow --password airflow --username airflow --role Admin
```

### Setup ECS

Create the ECR repository to store the customized airflow image.
```shell
$ terraform -chdir=infrastructure apply -target=aws_ecr_repository.airflow
```

Obtain the repository URI via `awscli` or the [AWS console](https://console.aws.amazon.com/ecr/repositories).
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

Authenticate your preferred container build tool with AWS.
```shell
$ aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ***.dkr.ecr.us-east-1.amazonaws.com
```

Build and push the container image.
```shell
$ export REPO_URI="{account}.dkr.ecr.{region}.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow"
$ docker buildx build -t "${REPO_URI}" -f build/prod/Containerfile --platform linux/amd64 .
$ docker push "${REPO_URI}"
```

Deploy the remaining infrastructure.
```shell
$ terraform -chdir=infrastructure plan
$ terraform -chdir=infrastructure apply
```

Initialize the airflow metadata database.
```shell
$ python3 scripts/run_task.py --public-subnet-ids subnet-*** --security-group sg-*** --command 'db init'
```

Create an admin user.
```shell
$ python3 scripts/run_task.py --public-subnet-ids subnet-*** --security-group sg-*** --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```

Find and open the airflow webserver load balancer URI.
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

### Autoscaling

TODO

### Examples

Run an arbitrary command as a standalone task in the ECS cluster.
```shell
$ python3 scripts/run_task.py --public-subnet-ids subnet-*** --security-group sg-*** --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```

Get a shell into the scheduler container using [ECS exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html). This step requires your to first install the `awscli` [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).
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

Manually scale the webserver to zero.
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

### Container image management

During development, your team could build adhoc images using the `git` commit hash. For example `deploy-airflow-on-ecs-fargate-2.2.3-python3.9:de4f657`. In production, you could tag images using semantic versioning. For example `deploy-airflow-on-ecs-fargate-2.2.3-python3.9:0.1`.

### Notes
- To avoid collisions with other AWS resource, I often use `name_prefix` instead of `name` in terraform configuration files. This is especially useful for SecretManager, which requires a 7 day wait period before fully deleting the secret.
- There are various "gotchas" in the terraform configuration that can be tricky to determine beforehand.

### Todo
- Add infrastructure diagram
- Describe technical decisions / tradeoffs
