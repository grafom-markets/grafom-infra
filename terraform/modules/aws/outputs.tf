output "instance_ip" {
  description = "Elastic IP of the EC2 instance"
  value       = aws_eip.grafom.public_ip
}

output "ssh_user" {
  description = "SSH user for Ubuntu AMI"
  value       = "ubuntu"
}

output "ssh_connection" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.ssh_key_path} ubuntu@${aws_eip.grafom.public_ip}"
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.grafom.id
}
