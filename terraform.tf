terraform {
  backend "s3" {}
  required_version = ">=1.0"
  required_providers {
    aws = {
      version = "~> 5.72"
      source  = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.AWS_REGION
}
