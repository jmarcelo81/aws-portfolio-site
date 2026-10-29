output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.portfolio.id
}

output "public_ip" {
  description = "Elastic IP address"
  value       = aws_eip.portfolio.public_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.portfolio.id
}
