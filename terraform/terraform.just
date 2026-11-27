alias tf := terraform

# Setup state backend (s3 on backblaze) for Terraform: stored as TF_STATE_AWS_*, since AWS_* belongs to the binary cache (see nix-cache-setup)
terraform-state-backend-setup:
  scripts/set-private-var.sh TF_STATE_AWS_ACCESS_KEY_ID
  scripts/set-private-var.sh TF_STATE_AWS_SECRET_ACCESS_KEY

# Setup openstack for terraform operations on gandi.net
terraform-openstack-setup:
  scripts/set-private-var.sh OS_USERNAME
  scripts/set-private-var.sh OS_PROJECT_NAME
  scripts/set-private-var.sh OS_PASSWORD

# Run terraform in a stack under terraform/ with the state backend's credentials, e.g. `just terraform gandi/infra plan`
[positional-arguments]
terraform dir *args:
  #!/usr/bin/env bash
  set -euo pipefail
  : "${TF_STATE_AWS_ACCESS_KEY_ID:?not set, run just terraform-state-backend-setup}"
  : "${TF_STATE_AWS_SECRET_ACCESS_KEY:?not set, run just terraform-state-backend-setup}"
  # Only for this process: the shell's AWS_* stay the binary cache's.
  export AWS_ACCESS_KEY_ID="$TF_STATE_AWS_ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$TF_STATE_AWS_SECRET_ACCESS_KEY"
  shift
  exec terraform -chdir="terraform/{{dir}}" "$@"
