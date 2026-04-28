variable "cloud_provider" {
  description = "Cloud provider to deploy into: aws | gcp | azure | oracle"
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "gcp", "azure", "oracle"], var.cloud_provider)
    error_message = "cloud_provider must be one of: aws, gcp, azure, oracle"
  }
}

variable "region" {
  description = "Cloud region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "VM size per cloud: aws=t3.micro, gcp=e2-micro, azure=Standard_B1s, oracle=VM.Standard.A1.Flex"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_path" {
  description = "Local path to private SSH key"
  type        = string
  default     = "~/grafom/login.pem"
}

variable "ssh_public_key_path" {
  description = "Local path to public SSH key"
  type        = string
  default     = "~/grafom/login.pub"
}

variable "project_name" {
  description = "Used for resource naming and tags"
  type        = string
  default     = "grafom"
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

variable "allowed_ips" {
  description = "CIDRs allowed to access ports. Restrict to your IP in production. Find yours: curl ifconfig.me"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "open_ports" {
  description = "Ports to open in security group / firewall"
  type        = list(number)
  default     = [22, 3000, 5432, 6379, 8123, 9000, 9090, 9092, 9644]
}

# ---------------------------------------------------------------------------
# Azure-specific variables
# ---------------------------------------------------------------------------

variable "azure_subscription_id" {
  description = "Azure subscription ID (required when cloud_provider = azure)"
  type        = string
  default     = ""
}

variable "azure_resource_group" {
  description = "Azure resource group name"
  type        = string
  default     = "grafom-dev-rg"
}

variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "northeurope"
}
