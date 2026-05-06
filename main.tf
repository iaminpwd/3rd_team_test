terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket-test140234"
    key            = "dr-project/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------
# 2. Networking 모듈 호출
# ---------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  # 기본 변수 전달
  aws_region      = var.aws_region
  aws_vpc_cidr    = var.aws_vpc_cidr
  onprem_vpc_cidr = var.onprem_vpc_cidr
  aws_asn         = var.aws_asn
  onprem_asn      = var.onprem_asn

  # 데이터 소스에서 읽어온 민감 정보 주입
  cgw_public_ip   = data.aws_ssm_parameter.cgw_public_ip.value
  tunnel1_psk     = data.aws_ssm_parameter.tunnel1_psk.value
  tunnel2_psk     = data.aws_ssm_parameter.tunnel2_psk.value
}

# ---------------------------------------------------------
# 3. 테스트 자원 (Security Group + EC2)
# ---------------------------------------------------------
resource "aws_security_group" "ping_sg" {
  name        = "allow_icmp_from_home"
  description = "Allow ICMP Ping from On-Premise"
  vpc_id      = module.networking.vpc_id # 모듈 아웃풋 참조

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.onprem_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "SG-Allow-Home-Ping" }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "test_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.networking.subnet_id # 모듈 아웃풋 참조
  vpc_security_group_ids = [aws_security_group.ping_sg.id]
  tags = { Name = "Test-EC2-Target" }
}

