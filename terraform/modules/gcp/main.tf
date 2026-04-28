# GCP module — always-free e2-micro tier
#
# To activate:
#   1. mv resources.tf.disabled resources.tf
#   2. Set credentials:
#        export GOOGLE_PROJECT="your-project-id"
#        export GOOGLE_APPLICATION_CREDENTIALS="path/to/credentials.json"
#      Or: gcloud auth application-default login
#   3. tofu init   (downloads google provider)
#   4. tofu plan -var="cloud_provider=gcp" -var="region=us-central1" -var="instance_type=e2-micro"
#
# Always-free eligible regions: us-west1, us-central1, us-east1
# Always-free instance type:   e2-micro (only)
# Always-free disk:            30 GB pd-standard
