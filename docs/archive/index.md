# Archive

> [!WARNING]
> Everything in this section is **obsolete**. It is kept because it records why the
> infrastructure looks the way it does, not as instructions. Hosts, paths and commands in
> it may no longer exist.

- **[apps VM migration plan](apps-migration-plan.md)** — the architecture decisions and
  per-stack record of moving the Ansible-managed bare-metal apps server (`snyssen.be`)
  onto the NixOS VM that became `apps-01`. The place to look for *why* a stack was set up
  the way it is.
- **[Phase B — production cutover](apps-migration-phase-b.md)** — the runbook for the
  cutover itself (completed 2026-11-23): reinstalling the old box as `hypervisor-01`,
  importing production's data and switching over.

A plan from [Plans](../plans/index.md) that has been carried out lands here if its
record is worth keeping; otherwise it is deleted.

The legacy Ansible code (the `container_*` roles, backup playbooks, inventories) was
removed after the cutover; it is in the git history before that removal.
