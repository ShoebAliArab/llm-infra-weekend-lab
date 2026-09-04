# terraform/backend.tf
terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket         = "llm-infra-weekend-tfstate"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "llm-infra-weekend-tflock"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
