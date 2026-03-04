# Setup state backend (s3 on backblaze) for Terraform
terraform-state-backend-setup:
  scripts/set-private-var.sh AWS_ACCESS_KEY_ID
  scripts/set-private-var.sh AWS_SECRET_ACCESS_KEY

# Setup openstack for terraform operations on gandi.net
terraform-openstack-setup:
  scripts/set-private-var.sh OS_USERNAME
  scripts/set-private-var.sh OS_PROJECT_NAME
  scripts/set-private-var.sh OS_PASSWORD
