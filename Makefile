build-dev:
	@docker compose build

build-prod:
	@docker buildx build -t "${REPO_URI}" -f build/prod/Containerfile --platform linux/amd64 .

tf-apply-ecr:
	@terraform -chdir=infrastructure apply -target=aws_ecr_repository.airflow

tf-plan:
	@terraform -chdir=infrastructure plan

tf-apply:
	@terraform -chdir=infrastructure apply

tf-destroy:
	@terraform -chdir=infrastructure destroy

