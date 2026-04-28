# Placeholder outputs — replaced by resource references when activated.
# See resources.tf.disabled for the real output values.

output "instance_ip" {
  description = "Public IP of the Azure VM"
  value       = ""
}

output "ssh_user" {
  description = "SSH user for Azure VM"
  value       = "ubuntu"
}

output "ssh_connection" {
  description = "SSH command to connect"
  value       = ""
}

output "instance_id" {
  description = "Azure VM resource ID"
  value       = ""
}
