# ---------------------------------------------------------------------------
# Providers — configured at root, inherited by child modules
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "opentofu"
    }
  }
}

# ---------------------------------------------------------------------------
# Cloud selector — exactly one module is active at a time
# ---------------------------------------------------------------------------

locals {
  cloud = var.cloud_provider
}

# ---------------------------------------------------------------------------
# AWS module
# ---------------------------------------------------------------------------

module "aws" {
  source = "./modules/aws"
  count  = local.cloud == "aws" ? 1 : 0

  region              = var.region
  instance_type       = var.instance_type
  ssh_key_path        = var.ssh_key_path
  ssh_public_key_path = var.ssh_public_key_path
  project_name        = var.project_name
  environment         = var.environment
  allowed_ips         = var.allowed_ips
  open_ports          = var.open_ports
}

# ---------------------------------------------------------------------------
# GCP module
# ---------------------------------------------------------------------------

module "gcp" {
  source = "./modules/gcp"
  count  = local.cloud == "gcp" ? 1 : 0

  region              = var.region
  instance_type       = var.instance_type
  ssh_key_path        = var.ssh_key_path
  ssh_public_key_path = var.ssh_public_key_path
  project_name        = var.project_name
  environment         = var.environment
  allowed_ips         = var.allowed_ips
  open_ports          = var.open_ports
}

# ---------------------------------------------------------------------------
# Azure module
# ---------------------------------------------------------------------------

module "azure" {
  source = "./modules/azure"
  count  = local.cloud == "azure" ? 1 : 0

  region                = var.region
  instance_type         = var.instance_type
  ssh_key_path          = var.ssh_key_path
  ssh_public_key_path   = var.ssh_public_key_path
  project_name          = var.project_name
  environment           = var.environment
  allowed_ips           = var.allowed_ips
  open_ports            = var.open_ports
  azure_subscription_id = var.azure_subscription_id
  azure_resource_group  = var.azure_resource_group
  azure_location        = var.azure_location
}

# ---------------------------------------------------------------------------
# Oracle module
# ---------------------------------------------------------------------------

module "oracle" {
  source = "./modules/oracle"
  count  = local.cloud == "oracle" ? 1 : 0

  region              = var.region
  instance_type       = var.instance_type
  ssh_key_path        = var.ssh_key_path
  ssh_public_key_path = var.ssh_public_key_path
  project_name        = var.project_name
  environment         = var.environment
  allowed_ips         = var.allowed_ips
  open_ports          = var.open_ports
}
