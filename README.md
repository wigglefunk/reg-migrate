# Satellite Host Re-Registration Automation

Automated migration of RHEL hosts from Red Hat Satellite 6.14 to 6.17 using Ansible Automation Platform (AAP).

## Overview

This project provides a complete automation solution for re-registering existing managed hosts from Satellite 6.14 to Satellite 6.17. Rather than performing an in-place migration, each host is cleanly re-registered to the new Satellite instance using the modern global registration API method.

**Key Features:**
- Exports host data from Satellite 6.14
- Creates lifecycle environments in Satellite 6.17
- Generates secure, time-limited registration commands
- Distributes hosts across multiple capsules using round-robin assignment
- Validates successful registration
- Comprehensive logging and error handling
- Fully idempotent and re-runnable

## Requirements

### Ansible Collections
- `redhat.satellite` >= 3.0.0
- `theforeman.foreman` >= 3.3.0
- `community.general` >= 6.0.0

Install collections:
```bash
ansible-galaxy collection install -r collections/requirements.yml
```

### System Requirements
- Ansible Automation Platform (AAP) or Ansible Core 2.12+
- Python 3 on control nodes and target hosts
- SSH access to target RHEL hosts
- API credentials for both Satellite 6.14 and 6.17

### Satellite Prerequisites
- Activation keys must exist in Satellite 6.17 for each RHEL version (6, 7, 8, 9)
- Organization must exist in both Satellite instances
- Capsule/Smart Proxy IDs must be configured in `group_vars/all.yml`

## Quick Start

### 1. Configure Variables

Edit `group_vars/all.yml`:
```yaml
# Update Satellite FQDNs
old_satellite_fqdn: "your-sat614.example.com"
new_satellite_fqdn: "your-sat617.example.com"

# Configure capsule IDs
smart_proxy_ids:
  - 1
  - 2
  - 3

# Verify activation keys match your Satellite 6.17 setup
activation_keys:
  rhel-6: "rhel-6"
  rhel-7: "rhel-7"
  rhel-8: "rhel-8"
  rhel-9: "rhel-9"
```

### 2. AAP Job Template Setup

Create an AAP job template with the following survey inputs:

| Variable | Type | Description |
|----------|------|-------------|
| `satellite_org` | Text | Organization name (e.g., "EO_ITRA") |
| `customer_uname` | Text | SSH username for target hosts |
| `customer_pass` | Password | SSH password for target hosts |

Configure credentials:
- **Satellite API**: Machine credential or Red Hat credential type
- **SSH**: Use survey inputs for customer host credentials

### 3. Run the Playbook

**Via AAP:**
1. Launch the job template
2. Fill in survey inputs
3. Monitor execution in AAP interface

**Via CLI (development/testing):**
```bash
ansible-playbook main.yml \
  -e "satellite_org=YOUR_ORG" \
  -e "customer_uname=host_user" \
  -e "customer_pass=host_password" \
  -e "app_username=satellite_user" \
  -e "app_password=satellite_password"
```

## How It Works

### Workflow Steps

1. **Export Hosts**: Retrieves host list from Satellite 6.14 for specified organization
2. **Filter Existing**: Checks Satellite 6.17 to avoid re-registering already migrated hosts
3. **Prepare Environment**: Creates lifecycle environment in Satellite 6.17 if needed
4. **Generate Commands**: Creates registration commands for each RHEL version × capsule combination
5. **Register Hosts**: Executes registration on each host with round-robin capsule assignment
6. **Validate**: Confirms hosts appear in Satellite 6.17 API
7. **Log Results**: Records success/failure with capsule assignments

### Round-Robin Capsule Distribution

Hosts are automatically distributed across available capsules based on their position in the inventory:
- Host 1 → Capsule 1
- Host 2 → Capsule 2
- Host 3 → Capsule 3
- Host 4 → Capsule 1 (cycle repeats)

This ensures even load distribution across your Satellite infrastructure.

## Execution at Scale

For organizations with 1,000+ hosts, configure AAP job template settings:

- **Forks**: 5-10 (balances speed vs. load)
- **Job Slicing**: 100-200 hosts per slice
- **Serial Batching**: 50 hosts per batch (default in playbook)
- **Enable Job Slicing**: ✓ (enables parallel execution)

## Idempotency and Safety

The playbook is designed to be 100% safe and re-runnable:

- Hosts already registered to Satellite 6.17 are automatically skipped
- Failed hosts can be re-processed by re-running the playbook
- No destructive operations are performed on hosts
- All actions are logged to `/var/log/aap_satellite_reregistration.log`

## Logging

All operations are logged with timestamps:

```
[2025-10-27T14:23:45Z] Exported 1247 hosts from organization 'EO_ITRA'
[2025-10-27T14:25:12Z] Generated 12 registration commands for org 'EO_ITRA'
[2025-10-27T14:27:33Z] SUCCESS: host001.example.com (RHEL 8) registered to capsule capsule1.example.com (proxy_id: 1)
[2025-10-27T14:27:35Z] VALIDATED: host001.example.com confirmed in Satellite 6.17
```

View logs on AAP control node:
```bash
tail -f /var/log/aap_satellite_reregistration.log
```

## Security Considerations

- **Credentials**: All credentials are managed via AAP credential store; never hardcoded
- **Registration Tokens**: Generated commands include time-limited JWT tokens
- **SSH Access**: Customer credentials collected via AAP survey at runtime
- **API Authentication**: Uses force_basic_auth for Satellite API calls
- **Certificate Validation**: Currently disabled (`validate_certs: false`) for testing; enable in production

## Troubleshooting

### No hosts found in organization
- Verify organization name matches exactly (case-sensitive)
- Check Satellite 6.14 API credentials
- Confirm hosts exist in the specified organization

### Registration command generation fails
- Verify activation keys exist in Satellite 6.17
- Check smart_proxy_ids are valid capsule IDs
- Confirm API user has sufficient permissions

### Host registration fails
- Verify SSH credentials are correct
- Check network connectivity between hosts and capsules
- Review host-specific errors in log file
- Ensure subscription-manager is installed on hosts

### All hosts already migrated
- This is expected if running playbook multiple times
- Check log file for previous successful registrations
- Use Satellite 6.17 UI to verify host status

## Support and Documentation

### Red Hat Documentation
- [Satellite 6.17 Global Registration](https://docs.redhat.com/en/documentation/red_hat_satellite/6.17/html/managing_hosts/registering-hosts-and-setting-up-host-integration_managing-hosts)
- [Red Hat Satellite Ansible Collection](https://catalog.redhat.com/en/software/collection/redhat/satellite#documentation)
- [Managing Satellite with Ansible Collections](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.17/html/administration_guide/managing_satellite_with_ansible_collections)

### Internal Documentation
- See `primer.md` for detailed technical architecture and LLM/agent guidance
- Review role-specific task files for implementation details

## License

Internal use only. Contact your organization's automation team for access and support.

## Contributing

This project follows standard GitLab workflow:
1. Create feature branch from `main`
2. Make changes and test thoroughly
3. Submit merge request with detailed description
4. Request review from automation team

---

**Version**: 1.0  
**Last Updated**: October 2025  
**Maintainer**: Infrastructure Automation Team