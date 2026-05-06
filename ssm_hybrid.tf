# --------------------------------------------------------- 
# SSM Hybrid Activation
# ---------------------------------------------------------
resource "aws_iam_role" "ssm_hybrid_role" {
  name = "SSM-Hybrid-Windows-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_hybrid_attach" {
  role       = aws_iam_role.ssm_hybrid_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_ssm_activation" "windows_onprem" {
  name               = "windows-home-server-activation"
  iam_role           = aws_iam_role.ssm_hybrid_role.name
  registration_limit = 5
  depends_on         = [aws_iam_role_policy_attachment.ssm_hybrid_attach]
}

resource "aws_ssm_parameter" "activation_id" {
  name      = "/vpn/home/ssm_activation_id"
  type      = "String"
  value     = aws_ssm_activation.windows_onprem.id
  overwrite = true 
}

resource "aws_ssm_parameter" "activation_code" {
  name      = "/vpn/home/ssm_activation_code"
  type      = "SecureString"
  value     = aws_ssm_activation.windows_onprem.activation_code
  overwrite = true
}