# ---------------------------------------------------------------------------
# Providers — configured at root, inherited by child modules
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.cloud_provider == "aws" ? var.region : "us-east-1"

  skip_credentials_validation = var.cloud_provider != "aws"
  skip_requesting_account_id  = var.cloud_provider != "aws"
  skip_region_validation      = var.cloud_provider != "aws"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "opentofu"
    }
  }
}

provider "google" {
  project     = var.gcp_project_id
  region      = var.cloud_provider == "gcp" ? var.region : "us-central1"
  credentials = var.gcp_credentials_file != "" ? file(pathexpand(var.gcp_credentials_file)) : null
}

provider "oci" {
  tenancy_ocid     = var.oracle_tenancy_ocid
  user_ocid        = var.oracle_user_ocid
  fingerprint      = var.oracle_fingerprint
  private_key_path = pathexpand(var.oracle_private_key_path)
  region           = var.region
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

  region               = var.region
  instance_type        = var.instance_type
  ssh_key_path         = var.ssh_key_path
  ssh_public_key_path  = var.ssh_public_key_path
  project_name         = var.project_name
  environment          = var.environment
  allowed_ips          = var.allowed_ips
  open_ports           = var.open_ports
  gcp_project_id       = var.gcp_project_id
  gcp_credentials_file = var.gcp_credentials_file
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

  region                  = var.region
  instance_type           = var.instance_type
  ssh_key_path            = var.ssh_key_path
  ssh_public_key_path     = var.ssh_public_key_path
  project_name            = var.project_name
  environment             = var.environment
  allowed_ips             = var.allowed_ips
  open_ports              = var.open_ports
  oracle_tenancy_ocid     = var.oracle_tenancy_ocid
  oracle_user_ocid        = var.oracle_user_ocid
  oracle_fingerprint      = var.oracle_fingerprint
  oracle_private_key_path = var.oracle_private_key_path
  oracle_compartment_id   = var.oracle_compartment_id
  oracle_ocpus            = var.oracle_ocpus
  oracle_memory_gb        = var.oracle_memory_gb
}
