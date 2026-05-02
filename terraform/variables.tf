# ---------------------------------------------------------
# variables.tf
# ---------------------------------------------------------
variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
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
