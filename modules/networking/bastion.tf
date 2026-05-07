# ══════════════════════════════════════════════════════
# Bastion EC2 (VPN 구성 전 임시 접근 용도)
# ══════════════════════════════════════════════════════
resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami_id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[1].id # AZ-C 퍼블릭 서브넷 (내부 관리 관문)
  key_name                    = var.bastion_key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 강제
  }

  tags = {
    Name = "${local.name}-bastion"
    Role = "bastion"
  }
}
