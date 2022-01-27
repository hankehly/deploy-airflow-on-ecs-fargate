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
terraform -chdir infrastructure apply -t aws_ecr_repository.airflow
```

Authenticate container build tool with aws
```shell
aws ecr get-login-password --region {region} | (docker/podman) login --username AWS --password-stdin {account}.dkr.ecr.{region}.amazonaws.com
```

Build and push the image
```shell
export REPO_URI="{account}.dkr.ecr.{region}.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow"
make build-prod-airflow-image
docker push $REPO_URI
```

Run terraform plan/apply
```shell
make terraform-plan
make terraform-apply
```

Notes:
- [Enabling ecs-exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- I use `name_prefix` to avoid name collisions with other AWS resources in global namespaces (like security groups, IAM roles, etc..). This is especially useful for SecretManager, where you must wait at least 7 days before you can fully delete a secret.

### Todo
- Document directory structure
- Describe technical decisions / tradeoffs
- Add infrastructure diagram
- Add development, deployment tips (eg. how to manage image versions, etc..)
