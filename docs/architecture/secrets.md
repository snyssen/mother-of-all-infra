# Secrets Management with SOPS

Every secret in this repository is stored encrypted with [SOPS](https://github.com/getsops/sops)
and [age](https://github.com/FiloSottile/age). NixOS hosts decrypt them at activation time
through [sops-nix](https://github.com/Mic92/sops-nix); the remaining Ansible playbooks decrypt
them on the controller through the `community.sops` vars plugin (see [Ansible](#ansible)).

## Overview

SOPS encrypts the values of a YAML file and leaves its keys in plaintext, so encrypted files
can be committed and their diffs stay readable:

```yaml
paperless:
  api-token: ENC[AES256_GCM,data:...,type:str]
sops:
  age:
    - recipient: age1...
```

- Who can decrypt a file is decided by the `creation_rules` in `.sops.yaml`, matched on the
  file's path.
- age keys are derived from ED25519 SSH keys, so there is no separate key material to keep.
- On NixOS, decrypted secrets land in `/run/secrets/` with the owner, group and mode each
  secret declares.

## Key files

| File | Purpose |
| --- | --- |
| `.sops.yaml` | age recipients per path (`creation_rules`) |
| `nix/hosts/<host>/data/secrets.yaml` | A host's secrets; the default SOPS file for that host |
| `nix/hosts/<host>/data/*.yaml` | Further per-host files, e.g. `syncthing.yaml`, or one file per stack on apps-01 |
| `nix/modules/nixos/sops.nix` | NixOS module wiring sops-nix defaults |
| `ansible/hosts/host_vars/<host>/secrets.sops.yaml` | Ansible variables for one inventory host |

There are no secrets shared across hosts: every file belongs to exactly one host (`nix/data/`
holds only the plain `syncthing.nix` device list).

## `.sops.yaml` structure

```yaml
keys:
  - &breakglass age1...
  - &root_myhost age1...       # the host's own key (from its SSH host key)
  - &snyssen_mylaptop age1...  # a person's key on a given machine

creation_rules:
  - path_regex: nix/hosts/myhost/data/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - age:
          - *breakglass
          - *root_myhost
          - *snyssen_mylaptop
```

There is one rule per NixOS host, covering every file in its `data/` directory. A rule lists:

- on servers, the host's own `root_<host>` key, since they decrypt with their SSH host key
  (see [Default settings](#default-settings)). The workstations purplehaze, gaming and
  blackfog decrypt with the user's key instead, so their rules list no root key;
- the `snyssen_<machine>` keys of the machines allowed to edit the file;
- a **breakglass** key, which is a recipient on every rule so secrets stay recoverable if all
  other keys are lost.

Any single recipient of a rule can decrypt the file. Editing `.sops.yaml` changes nothing about
files that are already encrypted: re-encrypt them afterwards with `just sops-update-keys` or
`just sops-update-keys-all`.

## Helper recipes

All recipes are in the root `justfile` and take positional arguments. The `sops-gen-secret`
and `sops-set-stdin` scripts never print a value, write it to disk in plaintext, or pass it on a
command line. Neither overwrites an existing key (rotating a secret is done deliberately with
`sops-update`), and both create the target file from `.sops.yaml`'s rules if it does not exist.

| Recipe | What it does |
| --- | --- |
| `just sops-update <file>` | Opens `<file>` decrypted in `$EDITOR`; SOPS re-encrypts on save. Also creates new files. |
| `just sops-update-keys <file>` | Re-encrypts `<file>` to the recipients `.sops.yaml` currently lists for it. |
| `just sops-update-keys-all [--yes]` | Does the same for every tracked file matched by a `path_regex` in `.sops.yaml`. Run it after adding or removing a key. |
| `just sops-gen-secret [--length N] <file> <key/path>` | Writes a random alphanumeric value (64 characters by default) at `<key/path>`. |
| `just sops-gen-secret --oidc-client <file> <key/prefix>` | Writes an Authelia OIDC client under `<prefix>`: `client_id`, `client_secret` and its `client_secret_hash`. |
| `cmd \| just sops-set-stdin <file> <key/path>` | Stores whatever arrives on stdin, byte for byte, at `<key/path>`, then reads it back to check. |
| `just sops-gen-privkey [sshKey] [ageKey]` | Derives an age private key from an SSH key. Defaults: `~/.ssh/id_ed25519` → `~/.config/sops/age/keys.txt`. |
| `just sops-get-pubkey [ageKey]` | Prints the age public key for an age private key (same default path). |

Example: copy an existing key file from another machine into SOPS without it touching the
screen:

```sh
ssh gaming cat ~/Documents/.config/syncthing/key.pem \
  | just sops-set-stdin nix/hosts/gaming/data/secrets.yaml syncthing/key
```

## Key management

### Deriving your age key

```sh
just sops-gen-privkey
# or from another SSH key:
just sops-gen-privkey ~/.ssh/id_ed25519_other
```

This writes the age private key to `~/.config/sops/age/keys.txt`, where SOPS looks by default.
`just sops-get-pubkey` then prints the matching public key to put in `.sops.yaml`.

### Registering a new host or user

1. Derive the age public key of the host (from `/etc/ssh/ssh_host_ed25519_key`) or the user
   (from their SSH key) with `just sops-gen-privkey` and `just sops-get-pubkey`. For a new
   machine this is part of [Setup a New Machine](../operations/new-machine/index.md); for
   libvirt VMs the `libvirt-image-build` playbook generates host keys and authorizes them for
   you.
2. Add the key under `keys:` in `.sops.yaml` and reference it from the relevant
   `creation_rules`, adding a rule for `nix/hosts/<host>/data/` if the host is new.
3. Re-encrypt the affected files:

   ```sh
   just sops-update-keys nix/hosts/<host>/data/secrets.yaml
   # or every file at once:
   just sops-update-keys-all
   ```

## Using secrets in NixOS

### Default settings

`nix/modules/nixos/sops.nix` imports sops-nix and sets:

- `sops.defaultSopsFile` to `nix/hosts/<host>/data/secrets.yaml`, where `<host>` is
  `config.system.name`. Secrets without a `sopsFile` are read from there.
- `sops.age.sshKeyPaths` from `sops.defaultSshKeys.mode` (table below), plus anything in
  `sops.extraSshKeyPaths`.
- `sops.age.generateKey = true`.

| `defaultSshKeys.mode` | Key used | Used by |
| --- | --- | --- |
| `host` (default) | `/etc/ssh/ssh_host_ed25519_key` (`defaultSshKeys.hostKeyPath`) | servers and VMs |
| `user` | `/home/snyssen/.ssh/id_ed25519` (`defaultSshKeys.userKeyPath`) | workstations: purplehaze, gaming, blackfog |
| `both` | both of the above | — |

### Declaring a secret

```nix
imports = [
  flake.modules.nixos.sops   # also imports sops-nix itself
];

sops.secrets."paperless/api-token" = {
  # sopsFile = ./data/other.yaml;  # only when not in data/secrets.yaml
  owner = "myservice";
  group = "myservice";
  mode  = "0400";
};
```

The decrypted value is at `config.sops.secrets."paperless/api-token".path`, i.e.
`/run/secrets/paperless/api-token`. Nested YAML keys are addressed with `/`.

### apps-01: one file per stack

apps-01 has no `secrets.yaml`. Its secrets are split into one file per concern under
`nix/hosts/apps-01/data/`:

- `common.yaml` for host-wide values (Tailscale auth key, user password hash, the shared
  `smtp/*` relay settings), declared in `configuration.nix`;
- `<stack>.yaml` for each compose stack (`immich.yaml`, `ntfy.yaml`, …), declared in that
  stack's `compose/<stack>/default.nix` under keys prefixed `compose-stacks/<stack>/`;
- `syncthing.yaml` for Syncthing's identity.

Since the default file does not exist, every secret on apps-01 sets `sopsFile` explicitly.
Stacks usually feed secrets into the container through a `sops.templates` env file, and list
the data file in `restartTriggers` so the stack restarts when a secret changes:

```nix
sops.secrets."compose-stacks/ntfy/users/hass/password_hash" = {
  sopsFile = ../../data/ntfy.yaml;
};

sops.templates."compose-ntfy.env".content = ''
  NTFY_AUTH_USERS=hass:${config.sops.placeholder."compose-stacks/ntfy/users/hass/password_hash"}:user
'';

compose-stacks.stacks.ntfy = {
  environmentFile = config.sops.templates."compose-ntfy.env".path;
  restartTriggers = [
    ../../data/ntfy.yaml
    config.sops.templates."compose-ntfy.env".content
  ];
  # ...
};
```

### User passwords

NixOS user passwords are stored as hashes in SOPS. Generate one with `mkpasswd -m bcrypt`, add
it with `just sops-update nix/hosts/<host>/data/secrets.yaml`:

```yaml
users:
  snyssen:
    passwordHash: $2b$05$...
```

and reference it:

```nix
sops.secrets."users/snyssen/passwordHash" = {
  neededForUsers = true;  # decrypted before users are created
};

users.users.snyssen.hashedPasswordFile =
  config.sops.secrets."users/snyssen/passwordHash".path;
```

## Ansible

There is no Ansible Vault. The few remaining playbooks read their secrets from SOPS files that
sit next to the plain variables:

- **Location**: `ansible/hosts/host_vars/<host>/secrets.sops.yaml`.
- **Format**: the keys are plain variable names (`ansible_user`, `ansible_become_pass`, …), so
  each value becomes a host variable as-is.
- **Loading**: the `community.sops` vars plugin, enabled in `ansible/ansible.cfg`
  (`vars_plugins_enabled = host_group_vars,community.sops.sops`), decrypts the files while
  the inventory loads, with the operator's own age key (`~/.config/sops/age/keys.txt` or
  `SOPS_AGE_KEY_FILE`).
- **Access**: `.sops.yaml` has one rule per inventory host (the two Technitium servers share
  one), matching `ansible/hosts/host_vars/<host>/*.sops.yaml`. These rules list human
  recipients only, plus the breakglass key: decryption happens on the controller, so host root
  keys have no business there.

One rule per host gives per-host access where a vault password was all or nothing: adding
someone's key to the Technitium rule (then running `just sops-update-keys-all`) lets them run
`technitium-setup` and read nothing else. Edit with `just sops-update`, add values with
`just sops-gen-secret` or `just sops-set-stdin`, as above.

> [!NOTE]
> `host_group_vars` also reads these files as plain YAML, so a `sops` metadata variable shows
> up in each host's vars. `community.sops` runs after it, so the decrypted values always win.

See `ansible/README.md` for the playbooks themselves.

## Related documentation

- [Scanner to Paperless](../services/scanner-to-paperless.md): consuming a SOPS secret in a NixOS module
- [Printing module](../modules/printing.md): takes its Paperless API token from a SOPS secret
- [Setup a New Machine](../operations/new-machine/index.md): authorizing a new host's age key
- [Full Disk Encryption](../operations/disk-encryption.md)
