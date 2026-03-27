# -----------------------------------------------
# Ubuntu 22.04 LTS AMI (동적 조회)
# SSM Parameter Store에서 최신 AMI ID 가져옴
# -----------------------------------------------
data "aws_ssm_parameter" "ubuntu_2204" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# -----------------------------------------------
# Bastion Host
# -----------------------------------------------
# Public Subnet 배치 — 운영자 SSH 진입점
# user → Bastion → k3s / Monitoring 접근 경로
resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.ubuntu_2204.value
  instance_type               = var.bastion_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true

    tags = {
      Name    = "${var.project_name}-${var.environment}-bastion-vol"
      Project = var.project_name
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-bastion"
    Project     = var.project_name
    Environment = var.environment
    Role        = "bastion"
  }
}

# -----------------------------------------------
# k3s Standby Node
# -----------------------------------------------
# Private Subnet 배치 — Public IP 없음
# Bastion 경유 SSH 접속
# cloudflared / k3s / node-exporter 설치는 Ansible에서 수행
# Cloudflare Tunnel 아웃바운드는 NAT Gateway 경유
resource "aws_instance" "k3s" {
  ami                         = data.aws_ssm_parameter.ubuntu_2204.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true

    tags = {
      Name    = "${var.project_name}-${var.environment}-k3s-vol"
      Project = var.project_name
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-k3s-node"
    Project     = var.project_name
    Environment = var.environment
    Role        = "standby"
  }
}

# -----------------------------------------------
# Monitoring Server
# -----------------------------------------------
# Private Subnet 배치 — Public IP 없음
# Bastion 경유 SSH 접속
# Prometheus / Grafana / Alertmanager / Discord Bot 설치는 Ansible에서 수행
resource "aws_instance" "monitoring" {
  ami                         = data.aws_ssm_parameter.ubuntu_2204.value
  instance_type               = var.monitoring_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  # t3.small (2GB RAM) 환경에서 OOM 방지를 위해 Swap 구성
  user_data = <<-EOF
              #!/bin/bash
              if [ ! -f /swapfile ]; then
                fallocate -l 2G /swapfile
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
              fi
              grep -q '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
              EOF

  root_block_device {
    volume_size           = var.monitoring_volume_size
    volume_type           = "gp3"
    delete_on_termination = true

    tags = {
      Name    = "${var.project_name}-${var.environment}-monitoring-vol"
      Project = var.project_name
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-monitoring"
    Project     = var.project_name
    Environment = var.environment
    Role        = "monitoring"
  }
}
