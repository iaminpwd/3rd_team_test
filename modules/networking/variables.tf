# 파일 위치: modules/networking/variables.tf

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "aws_vpc_cidr" {
  description = "AWS VPC의 CIDR 대역"
  type        = string
}

variable "onprem_vpc_cidr" {
  description = "온프레미스(홈 랩)의 CIDR 대역"
  type        = string
}

variable "aws_asn" {
  description = "AWS Transit Gateway의 BGP ASN"
  type        = number
}

variable "onprem_asn" {
  description = "온프레미스(홈 랩)의 BGP ASN"
  type        = number
}

# --- 아래는 SSM에서 읽어와 루트가 넘겨줄 보안 데이터 ---
variable "cgw_public_ip" {
  description = "CGW 퍼블릭 IP"
  type        = string
}

variable "tunnel1_psk" {
  description = "VPN Tunnel 1 PSK"
  type        = string
  sensitive   = true
}

variable "tunnel2_psk" {
  description = "VPN Tunnel 2 PSK"
  type        = string
  sensitive   = true
}