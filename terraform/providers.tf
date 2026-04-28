terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# All four providers declared so `tofu init` downloads them all.
# Only the active cloud (set by cloud_provider variable) needs credentials.
# Inactive modules stay at count=0 and their resources live in
# .tf.disabled files, so unused providers are never configured.
