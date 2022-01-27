build-prod-airflow-image:
	@docker buildx build -t "${REPO_URI}" -f build/prod/Containerfile --platform linux/amd64 .

terraform-plan:
	@terraform -chdir=infrastructure plan

terraform-apply:
	@terraform -chdir=infrastructure apply

