# ---------------------------------------------------------
# 보안 데이터 및 설정 (SSM Parameter Store)
# ---------------------------------------------------------
data "aws_ssm_parameter" "tunnel1_psk" {
  name            = "/vpn/home/tunnel1_psk"
  with_decryption = true
}

data "aws_ssm_parameter" "tunnel2_psk" {
  name            = "/vpn/home/tunnel2_psk"
  with_decryption = true
}

data "aws_ssm_parameter" "cgw_public_ip" {
  name = "/vpn/home/cgw_public_ip"
}