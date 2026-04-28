# db-checker-infra

## Prerequisites

Before running Terraform locally or through GitHub Actions, make sure the items below are in place.

### AWS remote state

Create the Terraform state backend resources before the first deploy:

- Dev S3 bucket: `db-checker-backend-aws-terraform-remote-state-centralized`
- Prod S3 bucket: `db-checker-aws-terraform-remote-state-centralized`
- Backend region: `us-east-2`

State locking with DynamoDB is currently commented out in `config/backend-dev.hcl` and `config/backend-prod.hcl`. If you re-enable it later, create the DynamoDB lock table with `LockID` as the partition key and give the deploy role read/write access to it.

### AWS deployment accounts

For each environment, create or choose an AWS account where Terraform will deploy resources:

- Dev deploys use `config/backend-dev.hcl` and `config/dev.tfvars`.
- Prod deploys use `config/backend-prod.hcl` and `config/prod.tfvars`.
- The AWS credentials active when Terraform runs determine which account receives the deployment.

If state is centralized in a different AWS account from dev/prod, each deploy role must also have cross-account access to the remote state bucket.

### GitHub Actions OIDC

Configure GitHub OIDC access in AWS for each target account:

- Add the GitHub Actions OIDC provider in AWS IAM.
- Create a dev deployment role trusted by the GitHub repo/branch or GitHub environment.
- Create a prod deployment role trusted by the GitHub repo/branch or GitHub environment.
- Give each role permission to manage the Terraform resources in that account.
- Give each role permission to access the remote state S3 bucket.

In GitHub, create environments named `dev` and `prod`. Add an environment secret named `GA_ROLE_ARN_DEV` in each environment:

- `dev` should point to the dev AWS OIDC role ARN.
- `prod` should point to the prod AWS OIDC role ARN.

### Local development

Install these tools locally:

- Terraform
- AWS CLI

Authenticate to the correct AWS account before running Terraform, for example:

```bash
export AWS_PROFILE=<your-profile>
```

Do not commit `.terraform/`, local state files, plans, or `.DS_Store`. Commit `.terraform.lock.hcl` so CI and local runs use consistent provider versions.

### Configuration

Check these files before deployment:

- `config/dev.tfvars` has `ENV = "dev"`.
- `config/prod.tfvars` has `ENV = "prod"`.
- `variables.tf` defaults `AWS_REGION` to `us-east-2`.
- The GitHub workflow `AWS_REGION` values match the Terraform/backend region.

## Deploying environments

Each environment uses its own remote state key and its own `tfvars` file. Reconfigure the backend when switching environments so Terraform reads and writes the correct state file.

For separate AWS accounts, authenticate CI with the environment-specific OIDC role before running Terraform. The assumed role controls which AWS account receives the deployment.

### Dev

```bash
terraform init -reconfigure -backend-config=config/backend-dev.hcl
terraform plan -var-file=config/dev.tfvars
terraform apply -var-file=config/dev.tfvars
```

### Prod

```bash
terraform init -reconfigure -backend-config=config/backend-prod.hcl
terraform plan -var-file=config/prod.tfvars
terraform apply -var-file=config/prod.tfvars
```

For local development, set your AWS credentials outside Terraform, for example with `AWS_PROFILE` in your shell. For CI/CD, assume the environment-specific OIDC role in the pipeline before Terraform runs.
