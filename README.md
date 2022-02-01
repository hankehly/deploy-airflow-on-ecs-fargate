# deploy-airflow-on-ecs-fargate
An example of how to deploy Apache Airflow on Amazon ECS Fargate

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

Get a shell using [ECS exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html). [Install the Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) first.
```shell
aws ecs execute-command --cluster airflow --task {task_id} --container webserver --interactive --command "/bin/bash"
```

Manually scale the webserver to zero
```shell
# macos
export TWO_MINUTES_LATER=$(date -u -v+2M '+%Y-%m-%dT%H:%M:00')
# linux
export TWO_MINUTES_LATER=$(date -u --date='2 minutes' '+%Y-%m-%dT%H:%M:00')

docker run --rm -v "${HOME}/.aws:/root/.aws" amazon/aws-cli application-autoscaling put-scheduled-action \
	  --service-namespace ecs \
	  --scalable-dimension ecs:service:DesiredCount \
	  --resource-id service/airflow/airflow-webserver \
	  --scheduled-action-name scale-webserver-to-zero \
	  --schedule "at(${TWO_MINUTES_LATER})" \
	  --scalable-target-action MinCapacity=0,MaxCapacity=0

# Confirm the scheduled event was created
docker run --rm -it -v ~/.aws:/root/.aws amazon/aws-cli application-autoscaling describe-scheduled-actions \
  --service-namespace ecs
#
#         {
#             "ScheduledActionName": "single-scalein-action-test",
#             "ScheduledActionARN": "arn:aws:autoscaling:us-east-1:***:scheduledAction:***:resource/ecs/service/airflow/airflow-webserver:scheduledActionName/single-scalein-action-test",
#             "ServiceNamespace": "ecs",
#             "Schedule": "at(2022-01-28T17:19:00)",
#             "ResourceId": "service/airflow/airflow-webserver",
#             "ScalableDimension": "ecs:service:DesiredCount",
#             "ScalableTargetAction": {
#                 "MinCapacity": 1,
#                 "MaxCapacity": 1
#             },
#             "CreationTime": "2022-01-28T16:50:07.802000+00:00"
#         }
#     ]
# }
```

Notes:
- I use `name_prefix` to avoid name collisions with other AWS resources in global namespaces (like security groups, IAM roles, etc..). This is especially useful for SecretManager, where you must wait at least 7 days before you can fully delete a secret.

### Todo
- Create a shell script wrapper around `aws ecs run-task` to run standalone task. Options should be command, cpu, memory, capacityProvider (fargate or fargate spot, etc..)
- Document directory structure
- Describe technical decisions / tradeoffs
- Add infrastructure diagram
- Add development, deployment tips (eg. how to manage image versions, etc..)
```

Gotchas
- If you encounter a `ConcurrentUpdateException` saying you already have a pending update to an Auto Scaling resource, just run the apply command again.
