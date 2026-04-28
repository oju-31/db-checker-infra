# db-checker-infra

Terraform infrastructure for the KoRo PHP visit logger coding test. The stack runs the provided PHP image on ECS Fargate with three replicas behind an Application Load Balancer, plus single-node MySQL and Redis containers for the data tier.

## Architecture

- Public Application Load Balancer on HTTP port `80`.
- ECS Fargate cluster with:
  - PHP app service, desired count `3`, image `ghcr.io/korohandelsgmbh/coding-test-2025:latest`.
  - MySQL service, desired count `1`, image `mysql:8`.
  - Redis service, desired count `1`, image `redis:7`.
- Public subnets across two Availability Zones.
- AWS Cloud Map private DNS names for service discovery:
  - `mysql.<env>-db-checker.local`
  - `redis.<env>-db-checker.local`
- AWS Secrets Manager stores generated MySQL passwords.
- CloudWatch Logs collects app, MySQL, and Redis container logs.

MySQL and Redis are intentionally ephemeral in this practical deployment. Task replacement recreates their container filesystems and loses stored visit data. See [design.md](design.md) for the production HA proposal.

## Prerequisites

- Terraform.
- AWS CLI credentials for local deployment.
- Existing S3 backend buckets:
  - Dev: `db-checker-backend-aws-terraform-remote-state-centralized`
  - Prod: `db-checker-aws-terraform-remote-state-centralized`
- GitHub Actions OIDC roles for CI/CD.

The backend region and deployment region are both `us-east-2`.

## GitHub Actions Setup

Create GitHub environments named `dev` and `prod`.

Add these environment secrets:

- `GA_ROLE_ARN_DEV` in the `dev` environment.
- `GA_ROLE_ARN_PROD` in the `prod` environment.

Each role needs permissions to manage the AWS resources in this Terraform stack and access its environment-specific remote state bucket.

The workflows run:

- `terraform fmt -check -recursive`
- `terraform validate`
- `terraform plan`
- `terraform apply` on branch pushes only

`dev` deploys from the `dev` branch with `config/dev.tfvars`.

`prod` deploys from the `main` branch with `config/prod.tfvars`.

## Local Deployment

Authenticate to the target AWS account first:

```bash
export AWS_PROFILE=<your-profile>
```

Deploy dev:

```bash
terraform init -reconfigure -backend-config=config/backend-dev.hcl
terraform plan -var-file=config/dev.tfvars
terraform apply -var-file=config/dev.tfvars
```

Deploy prod:

```bash
terraform init -reconfigure -backend-config=config/backend-prod.hcl
terraform plan -var-file=config/prod.tfvars
terraform apply -var-file=config/prod.tfvars
```

## Accessing the Application

After apply, Terraform prints:

```bash
application_url = "http://<alb-dns-name>"
alb_dns_name    = "<alb-dns-name>"
```

Open `application_url` in a browser or test it with:

```bash
curl "$(terraform output -raw application_url)"
```

## Verification

Useful checks after deployment:

```bash
terraform output application_url
aws ecs list-services --cluster <env>-db-checker-cluster
aws ecs describe-services --cluster <env>-db-checker-cluster --services <env>-db-checker-app <env>-db-checker-mysql <env>-db-checker-redis
```

Expected service counts:

- App: `3` running tasks.
- MySQL: `1` running task.
- Redis: `1` running task.

The ALB target group should show the PHP app tasks as healthy once the containers can connect to MySQL and Redis.
