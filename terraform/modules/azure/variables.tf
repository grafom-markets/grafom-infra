variable "region" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ssh_key_path" {
  type = string
}

variable "ssh_public_key_path" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "allowed_ips" {
  type = list(string)
}

variable "open_ports" {
  type = list(number)
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = ""
}

variable "azure_resource_group" {
  description = "Azure resource group name"
  type        = string
  default     = "grafom-dev-rg"
}

variable "azure_location" {
  description = "Azure region (overrides var.region for Azure-specific naming)"
  type        = string
  default     = "northeurope"
}
