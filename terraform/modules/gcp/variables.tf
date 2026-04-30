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

variable "gcp_project_id" {
  type = string
}

variable "gcp_credentials_file" {
  type = string
}
