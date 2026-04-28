# Azure module — Standard_B1s free tier (12 months)
#
# To activate:
#   1. mv resources.tf.disabled resources.tf
#   2. Authenticate:
#        az login
#        export ARM_SUBSCRIPTION_ID="your-subscription-id"
#      Or set azure_subscription_id variable
#   3. tofu init   (downloads azurerm provider)
#   4. tofu plan -var="cloud_provider=azure" -var="region=northeurope" -var="instance_type=Standard_B1s"
#
# Free tier: Standard_B1s (1 vCPU, 1 GB RAM), 64 GB Standard SSD, 750 hrs/month for 12 months
