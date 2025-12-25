terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
#  region = "ap-northeast-1"
  region = "ap-south-1"
  profile = "aws180"
}

data "aws_region" "current" {}

############################
# SSH Key Pair
############################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  key_name   = "tf-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  filename        = "${path.module}/tf-key.pem"
  content         = tls_private_key.ssh.private_key_pem
  file_permission = "0600"
}

############################
# Module
############################
module "redirect" {
  source   = "./modules/redirect_ec2"
  key_name = aws_key_pair.ssh.key_name
}

