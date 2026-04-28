# ---------------------------------------------------------------------------
# Data sources — VPC and subnet are never managed, only referenced
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.region}a"
  default_for_az    = true
}

# ---------------------------------------------------------------------------
# AMI — Ubuntu 24.04 LTS (Noble) amd64, latest patch
# ---------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---------------------------------------------------------------------------
# Key pair — references your existing login.pem public key
# ---------------------------------------------------------------------------

resource "aws_key_pair" "grafom" {
  key_name   = "${var.project_name}-${var.environment}"
  public_key = file(var.ssh_public_key_path)
}

# ---------------------------------------------------------------------------
# Security group — 9 TCP ingress rules matching confirmed live setup
# ---------------------------------------------------------------------------

resource "aws_security_group" "grafom" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Grafom infrastructure ports"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.open_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_ips
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg"
  }
}

# ---------------------------------------------------------------------------
# EC2 instance — t3.micro, Ubuntu 24.04, 20 GB gp3
# ---------------------------------------------------------------------------

resource "aws_instance" "grafom" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.grafom.key_name
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.grafom.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

# ---------------------------------------------------------------------------
# Elastic IP — prevents IP change on stop/start. Free while instance running.
# ---------------------------------------------------------------------------

resource "aws_eip" "grafom" {
  instance = aws_instance.grafom.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip"
  }
}
