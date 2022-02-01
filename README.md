# deploy-airflow-on-ecs-fargate
An example of how to deploy Apache Airflow on Amazon ECS Fargate

### Setup local environment
```
docker compose up -d
docker compose run --rm airflow-cli db init
docker compose run --rm airflow-cli users create --email airflow@example.com --firstname airflow --lastname airflow --password airflow --username airflow --role Admin
```

### Setup ECS environment

Create the ECR repo first
```shell
# alias for `terraform -chdir=infrastructure apply -target=aws_ecr_repository.airflow`
make tf-apply-ecr
```

Go to the Elastic Container Registry console at `https://console.aws.amazon.com/ecr/repositories?region={region}` and copy the new repository URI.

Authenticate container build tool with aws
```shell
aws ecr get-login-password --region {region} | (docker/podman) login --username AWS --password-stdin {account}.dkr.ecr.{region}.amazonaws.com
```

Build and push the image
```shell
export REPO_URI="{account}.dkr.ecr.{region}.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow"
make build-prod
docker push $REPO_URI
```

Run terraform plan/apply. If you encounter a `ConcurrentUpdateException` saying you already have a pending update to an Auto Scaling resource, just run the apply command again.
```shell
# alias for `terraform -chdir=infrastructure plan`
make tf-plan
# alias for `terraform -chdir=infrastructure apply`
make tf-apply
```

Initialize the database
```shell
python3 scripts/run_task.py --public-subnet-ids subnet-xxx --security-group sg-xxx --command 'db init'
```

Add a login user
```shell
python3 scripts/run_task.py --public-subnet-ids subnet-xxx --security-group sg-xxx --command \
  'users create --username airflow --firstname airflow --lastname airflow --password airflow --email airflow@example.com --role Admin'
```

Find your load balancer DNS name and open the console
<img width="1563" alt="airflow-home" src="https://user-images.githubusercontent.com/11639738/151594663-0895e62e-2fb3-4a6d-8bd5-98e9d8f1af90.png">

Get a shell using [ECS exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html). [Install the Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) first.
```
aws ecs update-service \
  --cluster airflow \
  --service airflow-webserver \
  --task-definition airflow-webserver:{N} \
  --force-new-deployment \
  --enable-execute-command

aws ecs execute-command \
  --cluster airflow \
  --task {task_id} \
  --container webserver \
  --interactive \
  --command "/bin/bash"
```


Scale the webserver to zero
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

# View the scheduled event
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
