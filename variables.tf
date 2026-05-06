variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_vpc_cidr" {
  description = "AWS VPC의 CIDR 대역"
  type        = string
  default     = "10.1.0.0/16"
}

variable "onprem_vpc_cidr" {
  description = "온프레미스(홈 랩)의 CIDR 대역"
  type        = string
  default     = "192.168.0.0/24"
}

variable "aws_asn" {
  description = "AWS Transit Gateway의 BGP ASN"
  type        = number
  default     = 64512
}

variable "onprem_asn" {
  description = "온프레미스(홈 랩)의 BGP ASN"
  type        = number
  default     = 65000
}
