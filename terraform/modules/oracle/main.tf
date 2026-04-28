# Oracle Cloud module — Ampere A1 always-free tier
#
# To activate:
#   1. mv resources.tf.disabled resources.tf
#   2. Set credentials in terraform.tfvars or env vars:
#        oracle_tenancy_ocid, oracle_user_ocid, oracle_fingerprint,
#        oracle_private_key_path, oracle_compartment_id
#   3. tofu init   (downloads oci provider)
#   4. tofu plan -var="cloud_provider=oracle" -var="region=us-ashburn-1" \
#        -var="instance_type=VM.Standard.A1.Flex"
#
# Always-free (no expiry): 4 OCPU, 24 GB RAM, 200 GB boot volume
# Best free tier for running the full Grafom dev stack.
