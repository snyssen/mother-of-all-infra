# Why this exists

In order to use the OVH provider, we need to generate Oauth2 client credentials. This should be doable from the API web UI directly, but said interface was very bugged for me and I was unable to connect. This bootstrap module is thus used as a way to create the initial credentials from Terraform.

# How to use it

1. Go to https://api.ovh.com/createToken/?GET=/*&POST=/*&PUT=/*&DELETE=/* and create a temporary API key. Keep the page open to reference the secrets later.
2. Setup credentials for tfstate bucket "infra-snyssen-be-tfstate" on Backblaze: from the repository root, run `just terraform-state-backend-setup` and enter the application key ID and secret.
3. From the repository root, run `just terraform ovh/bootstrap init` then `just terraform ovh/bootstrap apply`. The second command should ask for the application key, secret and consumer key created at the first step.
4. Confirm the changes. Once applied, the `provider_ovh.tf` is created in the `infra` module for you. Since the created file contains the newly created OAuth2 credentials, **you should not commit it!** It should be in the `.gitignore` already so you should not have to worry.
