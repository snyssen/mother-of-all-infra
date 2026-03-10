# NixOS Printing Module

The `printing` NixOS module (`nix/modules/nixos/printing.nix`) provides integrated printing and scanning support, including an optional automatic upload action to [Paperless-ngx](https://docs.paperless-ngx.com/).

## Features

- CUPS printing via HP drivers (`hplip`)
- Scanner support via SANE and scanservjs web UI
- Optional automatic document upload to Paperless-ngx after scanning

## Module Options

### `printing.enable`

- **Type**: `boolean`
- **Default**: `true`
- **Description**: Enables CUPS printing support and HP printer drivers.

When enabled, the following NixOS services are configured:

```nix
services.printing.enable = true;
services.printing.drivers = [ pkgs.hplip ];
hardware.sane.enable = true;
hardware.sane.extraBackends = [ pkgs.hplipWithPlugin ];
```

---

### `printing.scanner.enable`

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Enables scanner support via [scanservjs](https://sbs20.github.io/scanservjs/), a web-based frontend for SANE.

When enabled, the `scanservjs` service is started and accessible at `http://localhost:8080`.

---

### `printing.scanner.paperless.enable`

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Adds an "Upload to Paperless" action to the scanservjs post-scan action menu. When triggered by the user, the scanned file is uploaded to a Paperless-ngx instance via its REST API.

Also makes the `paperless-upload` script available in the system `PATH` for manual uploads.

---

### `printing.scanner.paperless.url`

- **Type**: `string`
- **Default**: `"https://paperless.snyssen.be"` *(personal default — override with your own instance URL)*
- **Example**: `"https://paperless.example.com"`
- **Description**: The base URL of the Paperless-ngx instance to upload documents to (without a trailing slash).

---

### `printing.scanner.paperless.apiTokenPath`

- **Type**: `path`
- **Default**: *(none — required when `paperless.enable = true`)*
- **Example**: `config.sops.secrets."paperless/api-token".path`
- **Description**: Path to a file containing the Paperless-ngx API token. The file is read at runtime by the upload script.

This should always be provided using a SOPS secret to avoid storing the token in the Nix store. See [Secrets Management](../secrets-management.md) for details on how to create and reference SOPS secrets.

## Usage Example

```nix
# In nix/hosts/<hostname>/configuration.nix

imports = [
  inputs.sops-nix.nixosModules.sops
  flake.modules.nixos.sops
  flake.modules.nixos.printing
];

# Declare the SOPS secret for the API token
sops.secrets."paperless/api-token" = {
  sopsFile = ./data/secrets.yaml;
  owner    = "scanservjs";
  group    = "scanservjs";
  mode     = "0400";
};

# Enable printing, scanning, and Paperless upload
printing = {
  enable  = true;
  scanner = {
    enable    = true;
    paperless = {
      enable       = true;
      url          = "https://paperless.example.com";
      apiTokenPath = config.sops.secrets."paperless/api-token".path;
    };
  };
};
```

## The `paperless-upload` Script

When `printing.scanner.paperless.enable = true`, a helper script named `paperless-upload` is added to the system `PATH`. It can be used from the command line:

```sh
paperless-upload /path/to/document.pdf
```

The script:

1. Validates the file exists.
2. Reads the API token from `apiTokenPath`.
3. POSTs the file to `<url>/api/documents/post_document/` with a 30-second timeout.
4. Exits with a non-zero status on failure.

## Security Considerations

- The API token file must be owned by `scanservjs` and set to mode `0400` so that only the scanservjs service user can read it.
- The token file should always be provided via a SOPS secret — never hardcoded in the Nix configuration.
- All communication with Paperless-ngx uses HTTPS.

## Related Documentation

- [Scanner to Paperless](../scanner-to-paperless.md) — end-to-end setup guide
- [Secrets Management](../secrets-management.md) — how to store and use SOPS secrets
- [Paperless Stack](../../ansible/stacks/paperless.md) — the server-side Paperless-ngx deployment
