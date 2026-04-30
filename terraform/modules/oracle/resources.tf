# Oracle Cloud resources — provider configured at root main.tf

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# ---------------------------------------------------------------------------
# VCN + Internet Gateway + Route Table
# ---------------------------------------------------------------------------

resource "oci_core_vcn" "grafom" {
  compartment_id = var.oracle_compartment_id
  display_name   = "${var.project_name}-${var.environment}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = var.project_name

  freeform_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "opentofu"
  }
}

resource "oci_core_internet_gateway" "grafom" {
  compartment_id = var.oracle_compartment_id
  vcn_id         = oci_core_vcn.grafom.id
  display_name   = "${var.project_name}-${var.environment}-igw"
  enabled        = true
}

resource "oci_core_route_table" "grafom" {
  compartment_id = var.oracle_compartment_id
  vcn_id         = oci_core_vcn.grafom.id
  display_name   = "${var.project_name}-${var.environment}-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.grafom.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# ---------------------------------------------------------------------------
# Security list — dynamic ingress per port, open egress
# ---------------------------------------------------------------------------

resource "oci_core_security_list" "grafom" {
  compartment_id = var.oracle_compartment_id
  vcn_id         = oci_core_vcn.grafom.id
  display_name   = "${var.project_name}-${var.environment}-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  dynamic "ingress_security_rules" {
    for_each = var.open_ports
    content {
      protocol  = "6" # TCP
      source    = var.allowed_ips[0]
      stateless = false

      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Subnet
# ---------------------------------------------------------------------------

resource "oci_core_subnet" "grafom" {
  compartment_id = var.oracle_compartment_id
  vcn_id         = oci_core_vcn.grafom.id
  display_name   = "${var.project_name}-${var.environment}-subnet"
  cidr_block     = "10.0.1.0/24"
  dns_label      = var.environment
  route_table_id = oci_core_route_table.grafom.id
  security_list_ids = [
    oci_core_security_list.grafom.id,
  ]
}

# ---------------------------------------------------------------------------
# Data sources — availability domain + Ubuntu image
# ---------------------------------------------------------------------------

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oracle_tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.oracle_compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_type
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------------------------------------------------------------------------
# Compute instance — Ampere A1 Flex, 4 OCPU, 24 GB RAM, 50 GB boot volume
# ---------------------------------------------------------------------------

resource "oci_core_instance" "grafom" {
  compartment_id      = var.oracle_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${var.project_name}-${var.environment}"
  shape               = var.instance_type

  shape_config {
    ocpus         = var.oracle_ocpus
    memory_in_gbs = var.oracle_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.grafom.id
    display_name     = "${var.project_name}-${var.environment}-vnic"
    assign_public_ip = false
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
  }

  freeform_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "opentofu"
  }
}

# ---------------------------------------------------------------------------
# Reserved public IP — survives instance stop/start
# ---------------------------------------------------------------------------

data "oci_core_vnic_attachments" "grafom" {
  compartment_id = var.oracle_compartment_id
  instance_id    = oci_core_instance.grafom.id
}

data "oci_core_private_ips" "grafom" {
  vnic_id = data.oci_core_vnic_attachments.grafom.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "grafom" {
  compartment_id = var.oracle_compartment_id
  display_name   = "${var.project_name}-${var.environment}-pip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.grafom.private_ips[0].id

  freeform_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "opentofu"
  }
}
