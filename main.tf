# -------------------------------------------------------
# Existing EC2 instance
# Import: terraform import aws_instance.portfolio i-0cf8c5811cffc33fe
# -------------------------------------------------------
resource "aws_instance" "portfolio" {
  ami           = "ami-084568db4383264d4"
  instance_type = "t3.small"

  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.portfolio.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    encrypted             = false
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_protocol_ipv6          = "disabled"
    instance_metadata_tags      = "disabled"
  }

  tags = {
    Name      = "Marcelo Website"
    Type      = "Python and Flask"
    ManagedBy = "terraform"
  }
}

# -------------------------------------------------------
# Elastic IP association
# Import: terraform import aws_eip.portfolio eipalloc-0c5e57851bf7a4075
# -------------------------------------------------------
resource "aws_eip" "portfolio" {
  domain = "vpc"

  tags = {
    Name      = "portfolio-eip"
    ManagedBy = "terraform"
  }
}

resource "aws_eip_association" "portfolio" {
  instance_id   = aws_instance.portfolio.id
  allocation_id = aws_eip.portfolio.id
}

# -------------------------------------------------------
# Security group
# Import: terraform import aws_security_group.portfolio sg-07f8c3c39aa44dd0a
# -------------------------------------------------------
resource "aws_security_group" "portfolio" {
  name        = "launch-wizard-1"
  description = "launch-wizard-1 created 2025-04-02T22:55:28.818Z"
  vpc_id      = "vpc-0185af5c5a97ae290"

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from home only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.home_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "portfolio-sg"
    ManagedBy = "terraform"
  }
}

# -------------------------------------------------------
# State bucket lifecycle - keep last 30 days of versions
# -------------------------------------------------------
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = "jmarcelo-portfolio-tfstate"
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = "jmarcelo-portfolio-tfstate"

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {
      prefix = "" 

}

    noncurrent_version_expiration {
      noncurrent_days = 30
      newer_noncurrent_versions = 3
    }
  }
}
