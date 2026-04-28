# Placeholder outputs — replaced by resource references when activated.
# See resources.tf.disabled for the real output values.

output "instance_ip" {
  description = "Reserved public IP of the OCI instance"
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
  description = "OCI instance OCID"
  value       = ""
}
