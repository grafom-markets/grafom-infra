output "instance_ip" {
  description = "Static IP of the GCE instance"
  value       = google_compute_address.grafom.address
}

output "ssh_user" {
  description = "SSH user for Ubuntu image"
  value       = "ubuntu"
}

output "ssh_connection" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.ssh_key_path} ubuntu@${google_compute_address.grafom.address}"
}

output "instance_id" {
  description = "GCE instance ID"
  value       = google_compute_instance.grafom.instance_id
}
