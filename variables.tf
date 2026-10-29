variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_id" {
  description = "Existing EC2 instance ID"
  type        = string
}

variable "eip_allocation_id" {
  description = "Existing Elastic IP allocation ID"
  type        = string
}

variable "security_group_id" {
  description = "Existing security group ID"
  type        = string
}

variable "home_ip" {
  description = "Your home public IP for SSH access (CIDR format)"
  type        = string
  sensitive   = true
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}
