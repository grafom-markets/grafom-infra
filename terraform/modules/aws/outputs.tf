output "instance_ip" {
  description = "Public IP of the EC2 instance"
  value       = ""
}

output "ssh_user" {
  description = "SSH user for Ubuntu AMI"
  value       = "ubuntu"
}

output "ssh_connection" {
  description = "SSH command to connect"
  value       = ""
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = ""
}
