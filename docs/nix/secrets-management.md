# Secrets Management with SOPS

This repository uses [SOPS](https://github.com/getsops/sops) (Secrets OPerationS) together with [sops-nix](https://github.com/Mic92/sops-nix) to store and deploy secrets securely in NixOS configurations.

## Overview

Secrets (API tokens, passwords, keys) are stored encrypted in YAML files inside the repository. They are decrypted at deployment time using [age](https://github.com/FiloSottile/age) keys derived from SSH keys. This means:

- Encrypted secrets can be committed to version control safely.
- Only machines and users whose keys are listed in `.sops.yaml` can decrypt a given secret file.
- Secrets are decrypted by NixOS at activation time and placed in `/run/secrets/` with the configured permissions.

## Key Files

| File | Purpose |
|---|---|
| `.sops.yaml` | Defines which age keys can decrypt which secret files |
| `nix/data/secrets.yaml` | Global secrets shared across all hosts |
| `nix/hosts/<host>/data/secrets.yaml` | Host-specific secrets |
| `nix/modules/nixos/sops.nix` | NixOS module wiring SOPS defaults |

## How SOPS Encryption Works

SOPS encrypts individual values in YAML files while keeping keys in plaintext, which makes diffs readable. The encryption key is derived from age public keys listed in `.sops.yaml`.

Example of an encrypted secrets file:

```yaml
paperless:
    api-token: ENC[AES256_GCM,data:...,type:str]
sops:
    age:
        - recipient: age1...
```

## Key Management

### Deriving an Age Key from an SSH Key

Age keys are derived from existing ED25519 SSH keys, so no separate key material needs to be stored:

```sh
just sops-gen-privkey
# or with a custom key path:
just sops-gen-privkey privKeyPath="~/.ssh/id_ed25519"
```

This writes the age private key to `~/.config/sops/age/keys.txt`, which is the default location SOPS looks for decryption keys.

### Getting Your Age Public Key

```sh
just sops-get-pubkey
```

This prints the age public key that corresponds to your private key. Add this to `.sops.yaml` to grant a new machine or user access to secrets.

### Registering a New Host or User

1. On the new machine, run `just sops-gen-privkey` to generate the age key.
2. Run `just sops-get-pubkey` and copy the printed public key.
3. Add the new key to `.sops.yaml` under the appropriate `creation_rules` entry.
4. Re-encrypt all affected secret files so they include the new key:

   ```sh
   just sops-update-keys nix/hosts/<host>/data/secrets.yaml
   just sops-update-keys nix/data/secrets.yaml
   ```

## Creating or Editing Secrets

Use SOPS to create or edit a secrets file. SOPS automatically encrypts on save:

```sh
just sops-update nix/hosts/<host>/data/secrets.yaml
```

Or for global secrets:

```sh
just sops-update nix/data/secrets.yaml
```

Your `$EDITOR` will open with the decrypted contents. Make your changes, save, and exit — SOPS re-encrypts the file automatically.

## Using Secrets in NixOS Configurations

Import `sops-nix` and the shared SOPS module, then declare the secrets you need:

```nix
imports = [
  inputs.sops-nix.nixosModules.sops
  flake.modules.nixos.sops   # sets defaultSopsFile and age key path
];

sops.secrets."paperless/api-token" = {
  sopsFile = ./data/secrets.yaml;  # override default file if needed
  owner    = "myservice";
  group    = "myservice";
  mode     = "0400";
};
```

At runtime, the decrypted value is available at the path returned by `config.sops.secrets."paperless/api-token".path`, which resolves to something like `/run/secrets/paperless/api-token`.

### Default SOPS File

`nix/modules/nixos/sops.nix` sets `nix/data/secrets.yaml` as the default SOPS file and configures the age key path and automatic key generation:

```nix
sops = {
  defaultSopsFile   = ../../data/secrets.yaml;
  age.sshKeyPaths   = [ "/home/<username>/.ssh/id_ed25519" ];
  age.generateKey   = true;
};
```

You can override `sopsFile` per secret when you need to reference a host-specific secrets file instead.

## Secret File Layout

### Global (`nix/data/secrets.yaml`)

Secrets accessible by all hosts listed in `.sops.yaml`.

### Host-Specific (`nix/hosts/<host>/data/secrets.yaml`)

Secrets encrypted only for a specific host. Use `sopsFile = ./data/secrets.yaml;` in the host configuration to reference them.

## `.sops.yaml` Structure

```yaml
keys:
  - &alias age1...  # age public key for a machine or user

creation_rules:
  - path_regex: nix/data/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - age:
          - *alias
  - path_regex: nix/hosts/myhost/data/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - age:
          - *alias
```

Each `creation_rules` entry maps a path pattern to a list of age keys. Any key in the list can decrypt the file.

## User Management

NixOS user accounts can have passwords managed through SOPS. Passwords must be stored as bcrypt hashes, then decrypted and used during system activation.

### Generating a Password Hash

Use `mkpasswd` to generate a bcrypt hash:

```sh
mkpasswd -m bcrypt
```

Enter your desired password when prompted. The output is a hashed password safe to store in version control.

### Storing Hashed Passwords in SOPS

Add the hash to your secrets file:

```sh
just sops-update nix/hosts/<host>/data/secrets.yaml
```

In the editor, add an entry like:

```yaml
users:
  snyssen:
    passwordHash: $2b$05$abcd...hashed...password
```

### Using Hashed Passwords in NixOS

Declare the secret and reference it in your user configuration:

```nix
sops.secrets."users/snyssen/passwordHash" = {
  sopsFile = ./data/secrets.yaml;
  neededForUsers = true;  # ensure secret is available before user creation
};

users.users.snyssen = {
  isNormalUser = true;
  hashedPasswordFile = config.sops.secrets."users/snyssen/passwordHash".path;
};
```

The `neededForUsers = true` option ensures the secret is decrypted before the user account is created.

## Related Documentation

- [Scanner to Paperless](./scanner-to-paperless.md) — example of consuming a SOPS secret in a NixOS module
- [Setup New Machine](./Setup%20New%20Machine.md) — includes steps for setting up age keys on a new host
