# Satellite Host Re-Registration Automation

Automated re-registration of RHEL hosts from Red Hat Satellite 6.14 to Satellite 6.18 using Ansible Automation Platform (AAP).

This is not an in-place Satellite upgrade. Each host is cleanly re-registered to the new Satellite instance using the modern global registration method (curl-based, JWT-authenticated).

## How It Works

The playbook (`dev_reg.yml`) runs four plays in sequence. All Satellite API work happens on localhost. SSH to hosts only happens during connectivity testing, registration, and validation.

### Play 1 -- Export and Prepare (localhost)

Four roles run back-to-back to build everything needed before touching a single host:

1. **export_hosts** -- Queries Satellite 6.14 API for all hosts in the specified organization. Filters out infrastructure hosts (capsules, satellites) defined in `excluded_hostnames`. Then queries Satellite 6.18 to see which hosts are already registered there and removes them from the list. Finally, applies the `max_hosts_per_run` cap so large orgs can be migrated incrementally across multiple job runs. Each subsequent run automatically picks up where the last one left off because the 6.18 check handles state.

2. **prepare_import** -- Takes the filtered host list and adds each host to an in-memory Ansible inventory group (`satellite_migration_hosts`). This is how a playbook that starts with only `localhost` ends up being able to SSH to actual hosts in later plays.

3. **provision_lifecycle_env** -- Ensures the lifecycle environment (`{{ satellite_org }}_ALL`) exists in Satellite 6.18. Creates it if missing, skips if it already exists. Idempotent.

4. **generate_registration_command** -- Calls the Satellite 6.18 registration command API once per RHEL major version (6, 7, 8, 9), each with its own activation key. Produces a dictionary of curl commands keyed by RHEL version. All commands use a single load-balanced smart proxy and 24-hour JWT tokens.

A post-task validates that the dynamic inventory group was built correctly before proceeding.

### Play 1.5 -- SSH Connectivity Test (satellite_migration_hosts)

Runs `ansible.builtin.ping` with `become: true` against every host in the migration group. This validates that the AAP Machine Credential can actually reach each host and escalate privileges. Hosts that pass are added to a `reachable_hosts` group. Unreachable hosts are silently skipped via `ignore_unreachable: true`.

### Play 1.6 -- Unreachable Host Notification (localhost)

Compares the original migration list against `reachable_hosts` to identify failures. If any hosts were unreachable, sends an email to the team with the list of hostnames that need manual investigation. If zero hosts are reachable, the playbook ends gracefully.

### Play 2 -- Register Hosts (reachable_hosts)

Runs the **register_hosts** role against only the hosts that passed connectivity testing. Processes hosts in batches controlled by `batch_size`. For each host, it detects the RHEL major version from gathered facts, selects the matching registration command, copies it as a temp script, executes it with `become: true`, then cleans up. Results (success or failure with stderr) are logged to the control node.

### Play 3 -- Validate Registration (reachable_hosts)

Runs the **validate** role, which queries the Satellite 6.18 API to confirm each host actually appears there. Retries up to 3 times with 30-second delays to allow for propagation. Logs validation success or failure.

### Play 4 -- Final Summary (localhost)

Runs the **log_results** role to append a summary block to the log file with counts of successful and failed registrations.

## AAP Requirements

Two credentials must be attached to the job template:

- **Satellite API Credential** -- Provides `app_username` and `app_password` for all Satellite 6.14 and 6.18 API calls.
- **Machine Credential** -- Provides SSH access (`ansible_user`, `ansible_password` or `ansible_ssh_private_key_file`) to the RHEL hosts being re-registered. AAP injects these automatically.

One survey input is required:

- **satellite_org** -- The organization name to migrate (e.g., `EO_ITRA`).

## Configuration

All environment-specific settings live in `group_vars/dev.yml`, including Satellite FQDNs, activation keys, excluded hostnames, batch size, per-run host cap, smart proxy FQDN, and email notification settings.

## Collections

Defined in `collections/requirements.yml`:

- `redhat.satellite` >= 3.0.0
- `theforeman.foreman` >= 3.3.0
- `community.general` >= 6.0.0

## Safety and Idempotency

The playbook is safe to re-run. Hosts already registered in Satellite 6.18 are automatically skipped during export. The lifecycle environment creation is idempotent. Registration commands are generated fresh each run with new JWT tokens. The `max_hosts_per_run` cap combined with the 6.18 skip logic means you can run the same job repeatedly until an entire org is migrated without any manual state tracking.
