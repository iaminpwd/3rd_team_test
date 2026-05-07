terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket-test140234"
    key            = "dr-project/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
  }
}


