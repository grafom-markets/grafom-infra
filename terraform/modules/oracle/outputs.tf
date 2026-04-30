output "instance_ip" {
  description = "Reserved public IP of the OCI instance"
  value       = oci_core_public_ip.grafom.ip_address
}

output "ssh_user" {
  description = "SSH user for Ubuntu image"
  value       = "ubuntu"
}

output "ssh_connection" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.ssh_key_path} ubuntu@${oci_core_public_ip.grafom.ip_address}"
}

output "instance_id" {
  description = "OCI instance OCID"
  value       = oci_core_instance.grafom.id
}
