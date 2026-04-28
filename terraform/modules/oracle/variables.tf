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

variable "oracle_tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string
  default     = ""
}

variable "oracle_user_ocid" {
  description = "OCI user OCID"
  type        = string
  default     = ""
}

variable "oracle_fingerprint" {
  description = "OCI API key fingerprint"
  type        = string
  default     = ""
}

variable "oracle_private_key_path" {
  description = "Path to OCI API private key"
  type        = string
  default     = ""
}

variable "oracle_compartment_id" {
  description = "OCI compartment OCID to deploy into"
  type        = string
  default     = ""
}

variable "oracle_ocpus" {
  description = "Number of OCPUs (always-free max: 4)"
  type        = number
  default     = 4
}

variable "oracle_memory_gb" {
  description = "Memory in GB (always-free max: 24)"
  type        = number
  default     = 24
}
