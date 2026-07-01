# Backups

## Current backup system

Backups are orchestrated with **autorestic** (Restic wrapper), configured and deployed by:

- playbook: `/home/runner/work/mother-of-all-infra/mother-of-all-infra/ansible/playbooks/backup-run.ansible.yml`
- role: `/home/runner/work/mother-of-all-infra/mother-of-all-infra/ansible/roles/setup_backups`
- generated config template: `/home/runner/work/mother-of-all-infra/mother-of-all-infra/ansible/roles/setup_backups/templates/autorestic_config.yaml`

### How autorestic is configured

`setup_backups` deploys:

- `/root/.autorestic.yml` (rendered from the template above)
- `/root/scripts/autorestic_log_wrapper.sh` (splits logs per location in `/var/log/autorestic`)
- cron jobs:
  - every 30 minutes: `autorestic --ci cron --lean`
  - weekly integrity check: `autorestic --ci check` (Monday at 16:10)

The autorestic config is generated from inventory vars:

- `autorestic__backends` (backend definitions)
- `autorestic__locations` (what to back up and where)

Those vars are sourced from vault values in:
`/home/runner/work/mother-of-all-infra/mother-of-all-infra/ansible/hosts/group_vars/apps/vars.yml`.

### Retention and hooks

Each location currently uses:

- keep daily: 14
- keep weekly: 4
- keep monthly: 6
- keep yearly: 1

The template also wires hooks for:

- per-location pre-backup commands
- optional backend before/after commands
- uptime kuma success/failure push monitoring

### Backup destinations

Destinations are the autorestic **backends** declared in `autorestic__backends` (vault-managed).

From the current backup playbook examples, commonly used backend names are:

- `backup-snyssen-be`
- `snyssen-be-autorestic`

Exact credentials and backend env vars are intentionally vault-managed and not documented in plain text in this repository.

## Restore workflows

### 1) Restore backup files from autorestic

Use this first when local files/dumps are missing:

```sh
ansible-playbook playbooks/backup-restore.ansible.yml -e '{"backup_backend":"backup-snyssen-be","backup_location":"postgres","backup_snapshot":"<snapshot-id>","backup_restore_directory":"/mnt/tmp"}'
```

Notes:

- `backup_location` is an autorestic location (for example `postgres`, `nextcloud`, ...).
- If `backup_snapshot` is omitted, latest snapshot is restored.
- If `backup_restore_directory` is omitted, restore is done with `/` as root.

### 2) Restore PostgreSQL databases from local dumps

Use the DR-oriented playbook:

```sh
ansible-playbook playbooks/backup-restore-databases.ansible.yml
```

Behavior:

- restores postgres-related databases from local dump files
- auto-selects latest dump per database (non-interactive)
- fails early with guidance if a local dump is missing

Scope control:

```sh
ansible-playbook playbooks/backup-restore-databases.ansible.yml -e '{"db_restore_include":["nextcloud"]}'
ansible-playbook playbooks/backup-restore-databases.ansible.yml -e '{"db_restore_exclude":["recipes"]}'
```

### 3) Suggested disaster-recovery sequence (high level)

1. Re-provision host/services baseline (Nix/Ansible deployment flow).
2. Restore backup files with `backup-restore.ansible.yml` for required locations.
3. Run `backup-restore-databases.ansible.yml` to restore all PostgreSQL-related DBs.
4. Start/restart application stacks and verify service health.
5. Run backup listing/integrity checks to validate backup system availability.

## B2 setup

The setup for the Backblaze B2 backups are based on [this write-up](https://scribe.rip/@benjamin.ritter/how-to-do-ransomware-resistant-backups-properly-with-restic-and-backblaze-b2-e649e676b7fa) (I recommend skipping to the TL;DR).

### Bucket creation

1. [Install the Backblaze CLI tools](https://www.backblaze.com/docs/cloud-storage-command-line-tools)
2. Create an [application key](https://secure.backblaze.com/app_keys.htm) with permissions to create buckets and other keys (I recommend creating temporary keys for this by setting a short expiration time) and authenticate with it

```sh
b2 account authorize [applicationKeyId] [applicationKey]
```

3. Create a new bucket with lifecycle rules:

```sh
b2 bucket create --default-server-side-encryption SSE-B2 --lifecycle-rule '{"daysFromHidingToDeleting": 30, "daysFromUploadingToHiding": null, "fileNamePrefix": ""}' [bucket-name] allPrivate
```

4. Create an application key with limited access to your specific bucket (I like to use the same key name as the bucket name):

```sh
b2 key create --bucket [bucket-name] [key-name] listBuckets,listFiles,readFiles,writeFiles
```

5. Take note of the key ID and its value that are outputted after running the previous command, you will need them to configure autorestic

In case of ransomware, lost data on the bucket can be restored using [this software](https://github.com/viltgroup/bucket-restore).
