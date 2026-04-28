# Placeholder outputs — replaced by resource references when activated.
# See resources.tf.disabled for the real output values.

output "instance_ip" {
  description = "Static IP of the GCE instance"
  value       = ""
}

output "ssh_user" {
  description = "SSH user for Ubuntu image"
  value       = "ubuntu"
}

output "ssh_connection" {
  description = "SSH command to connect"
  value       = ""
}

output "instance_id" {
  description = "GCE instance ID"
  value       = ""
}
