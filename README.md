# deploy-airflow-on-ecs-fargate
An example of how to deploy Apache Airflow on Amazon ECS Fargate

### Procedure

Run terraform plan/apply
```shell
make terraform-plan
make terraform-apply
```

Authenticate container build tool with aws
```shell
aws ecr get-login-password --region {region} | (docker/podman) login --username AWS --password-stdin {account}.dkr.ecr.{region}.amazonaws.com
```

Build and push the image
```shell
REPO_URI={account}.dkr.ecr.{region}.amazonaws.com/deploy-airflow-on-ecs-fargate-airflow make build-prod-airflow-image
docker push $REPO_URI
```

Notes:
- [Enabling ecs-exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- I use `name_prefix` to avoid name collisions with other AWS resources in global namespaces (like security groups, IAM roles, etc..)
