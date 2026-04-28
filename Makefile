CLOUD  ?= aws
REGION ?= eu-north-1
ENV    ?= dev

.PHONY: init plan apply destroy output ssh validate

init:
	cd terraform && tofu init

validate:
	cd terraform && tofu validate

plan:
	cd terraform && tofu plan \
		-var="cloud_provider=$(CLOUD)" \
		-var="region=$(REGION)" \
		-var="environment=$(ENV)"

apply:
	cd terraform && tofu apply \
		-var="cloud_provider=$(CLOUD)" \
		-var="region=$(REGION)" \
		-var="environment=$(ENV)"

destroy:
	cd terraform && tofu destroy \
		-var="cloud_provider=$(CLOUD)" \
		-var="region=$(REGION)" \
		-var="environment=$(ENV)"

output:
	cd terraform && tofu output

ssh:
	$$(cd terraform && tofu output -raw ssh_connection)

# Usage:
#   make init                                  # download providers
#   make plan                                  # defaults: aws, eu-north-1, dev
#   make plan CLOUD=gcp REGION=us-central1     # GCP always-free region
#   make plan CLOUD=oracle REGION=us-ashburn-1 # Oracle always-free
#   make plan CLOUD=azure REGION=northeurope   # Azure 12-month free
#   make apply CLOUD=aws                       # provision AWS
#   make ssh                                   # connect to running instance
