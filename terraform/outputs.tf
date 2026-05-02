output "instance_ip" {
  description = "Public IP of the VM"
  value = (
    local.cloud == "aws"   ? module.aws[0].instance_ip :
    local.cloud == "gcp"   ? module.gcp[0].instance_ip :
    local.cloud == "azure" ? module.azure[0].instance_ip :
    module.oracle[0].instance_ip
  )
}

output "ssh_user" {
  description = "OS user to SSH as (ubuntu, ec2-user, etc.)"
  value = (
    local.cloud == "aws"   ? module.aws[0].ssh_user :
    local.cloud == "gcp"   ? module.gcp[0].ssh_user :
    local.cloud == "azure" ? module.azure[0].ssh_user :
    module.oracle[0].ssh_user
  )
}

output "ssh_connection" {
  description = "Ready-to-use SSH command"
  value = (
    local.cloud == "aws"   ? module.aws[0].ssh_connection :
    local.cloud == "gcp"   ? module.gcp[0].ssh_connection :
    local.cloud == "azure" ? module.azure[0].ssh_connection :
    module.oracle[0].ssh_connection
  )
}

output "instance_id" {
  description = "Cloud-specific resource ID"
  value = (
    local.cloud == "aws"   ? module.aws[0].instance_id :
    local.cloud == "gcp"   ? module.gcp[0].instance_id :
    local.cloud == "azure" ? module.azure[0].instance_id :
    module.oracle[0].instance_id
  )
}

output "ssh_key_path" {
  description = "Path to SSH private key for VM login"
  value       = pathexpand(var.ssh_key_path)
}
