# Satellite Host Re-Registration Project — LLM/Agent Primer
**Project:** Migration of Hosts from Red Hat Satellite 6.14 → 6.17  
**Intended Audience:** AI agents, LLMs, or developers tasked with generating or extending automation playbooks for this project.  

---

## 1. Project Context and Objective

### 1.1 Overview
This project automates **re-registration of existing managed hosts** from **Red Hat Satellite 6.14** to **Satellite 6.17** using **Ansible Automation Platform (AAP)**.  
The process is **not an in-place migration**; each host is **re-registered cleanly** to the new Satellite, maintaining minimal metadata continuity (hostname,organization).

### 1.2 Why Re-Registration
Satellite 6.17 introduces changes in repository architecture, Capsule communication, and content view design.  
Rather than migrating metadata and database contents, the project **re-registers each host cleanly** into the new system for:
- Simplified lifecycle management (single lifecycle environment per org)
- Reduced complexity in content promotion and synchronization
- Clean state for Puppet/Facter removal or transition

### 1.3 Design Philosophy
- **Idempotent:** All playbooks must be 100% re-runnable.  
- **Safe:** No destructive operations on hosts.  
- **Logged:** Each host’s registration success/failure and capsule mapping recorded.  
- **Concurrent:** Scales to 2,000+ hosts per org using AAP slicing and forking.  
- **Credential-isolated:** AAP handles credentials securely; no secrets are written to disk.

---

## 2. System Architecture

### 2.1 Components

| Component | Description |
|------------|--------------|
| **AAP Controller** | Orchestrates workflows, stores credentials, collects survey data per org. |
| **Satellite 6.14** | Legacy instance — source of current host registrations. Used only for host export. |
| **Satellite 6.17** | Target instance — destination for all re-registrations. |
| **Customer Hosts** | Existing RHEL systems to be re-registered. SSH access provided per-org. |
| **Capsules** | Content proxies associated with 6.17. Hosts will register to capsules automatically. |

### 2.2 Data Flow

1. **AAP Job Launch:** Operator selects an organization and provides SSH credentials via survey.  
2. **Host Export:** From Satellite 6.14, retrieve hostnames/IPs for that organization.  
3. **Lifecycle Environment Preparation:** Ensure a simple, default environment exists in Satellite 6.17.  
4. **Registration Command Generation:** Generate a registration command via Satellite 6.17 API (curl-based).  
5. **Re-Registration:** SSH into each host, copy and execute the generated script.  
6. **Validation:** Confirm host appears in 6.17 via API.  
7. **Logging:** Record hostname and capsule mapping.  

---

## 3. Key Technical Assumptions

| Category | Detail |
|----------|---------|
| **Provisioning** | Not used. Hosts are pre-existing and only re-registered. |
| **Content Views** | Already available in 6.17. No import of metadata. |
| **Orgs** | Not 1:1 across Satellites; selected subset only. |
| **Locations** | All new hosts default to `default_location`. |
| **Satellite Credentials** | Managed via AAP credential store. |
| **Host Credentials** | Collected per-org per run via AAP survey. |
| **Python** | `/usr/bin/python3` on controllers and hosts. |
| **Logging** | Only host + capsule information. |
| **Failure Handling** | Log failure, skip host; never halt global workflow. |

---

## 4. Execution Environment (AAP)

### 4.1 Integration
The project is fully compatible with **Ansible Automation Platform (AAP)**.

- **Job Template Survey Inputs:**
  - `satellite_org`
  - `customer_host_username`
  - `customer_host_password`
- **Credentials:**  
  - Satellite API credential (machine or Red Hat credential type).  
  - SSH credential to target hosts (from survey).  
- **Slicing/Forking:**  
  - Slicing size: 100–200 hosts.  
  - Forks: 5–10.  
- **Workflow compatibility:**  
  Can be integrated into multi-stage workflows (e.g., pre-export, re-register, validate).

### 4.2 Example Survey Inputs
```yaml
satellite_org: "EO_ITRA"
customer_host_username: "customer_user"
customer_host_password: "customer_pass"
```

---

## 5. Role Overview

| Role | Purpose |
|------|----------|
| **export_hosts** | Retrieve list of hosts from Satellite 6.14. |
| **prepare_import** | Normalize/clean host data. |
| **provision_lifecycle_env** | Ensure lifecycle environment `{{ satellite_org }}_ALL` exists on 6.17. |
| **generate_registration_command** | Use the Satellite 6.17 API to produce a curl-based registration script. |
| **register_hosts** | SSH into each host and execute the generated script. |
| **log_results** | Record outcome (hostname + capsule). |
| **validate** | Optional API verification post-registration. |
| **retry_failed** | Separate workflow for re-processing failed hosts. |

---

## 6. Core Variable Definitions

```yaml
old_satellite_fqdn: "614satellite.example.com"
new_satellite_fqdn: "617satellite.example.com"
old_satellite_server_url: "https://{{ old_satellite_fqdn }}"
new_satellite_server_url: "https://{{ new_satellite_fqdn }}"

satellite_org: "EO_ITRA"
satellite_location: "default_location"
new_default_env: "{{ satellite_org }}_ALL"
capsule_download_policy: "on_demand"

ansible_python_interpreter: /usr/bin/python3
customer_host_username: "{{ customer_uname }}"
customer_host_password: "{{ customer_pass }}"
```

---

## 7. Core Collections and API Dependencies

### 7.1 Primary Collection
**Red Hat Satellite Ansible Collection**  
Official documentation:  
https://catalog.redhat.com/en/software/collection/redhat/satellite#documentation  
→ *Managing Satellite with Ansible Collections in the Satellite Admin Guide (6.17)*

Modules of interest:
- `redhat.satellite.lifecycle_environment`
- `redhat.satellite.organization_info`
- `redhat.satellite.activation_key`
- `redhat.satellite.host_info`
- `redhat.satellite.content_view_info`

This is the basis for the satellite collection. It has much better usage examples:
https://docs.ansible.com/ansible/latest/collections/theforeman/foreman/index.html

### 7.2 Registration API (Global Registration)
Satellite 6.17 supports **global registration**, which generates a registration command using a REST API.  
This replaces the older `subscription-manager` manual registration flow and Katello Agent methods.

**Documentation Reference:**  
https://docs.redhat.com/en/documentation/red_hat_satellite/6.17/html/managing_hosts/registering-hosts-and-setting-up-host-integration_managing-hosts

**API Endpoint:** `/api/registration_commands`  
The API returns a JSON object containing a curl or wget command embedding a JWT registration token and activation key.

---

## 8. Lifecycle Environment Management

### Example Task
```yaml
- name: Ensure base lifecycle environment exists
  redhat.satellite.lifecycle_environment:
    name: "{{ new_default_env }}"
    label: "{{ new_default_env }}"
    description: "Base working environment for 6.17 and beyond"
    prior: "Library"
    organization: "{{ satellite_org }}"
    state: present
  register: lifecycle_env_result

- name: Report lifecycle environment status
  ansible.builtin.debug:
    msg: "Lifecycle environment '{{ new_default_env }}': {{ lifecycle_env_result.changed | ternary('Created', 'Already exists') }}"
```

---

## 9. Host Re-Registration Logic (Modern Curl-Based Method)

### 9.1 Overview
In Satellite 6.17, host registration uses **global registration**, which generates a secure, time-limited command via the Satellite API or Hammer CLI.  
The resulting command typically uses **curl** or **wget** and includes a registration token.  
This replaces manual subscription-manager invocations.

### 9.2 Playbook Example

```yaml
- name: Generate registration command via Satellite API
  ansible.builtin.uri:
    url: "{{ satellite_server_url }}/api/registration_commands"
    method: POST
    user: "{{ satellite_setup_username }}"
    password: "{{ satellite_initial_admin_password }}"
    force_basic_auth: yes
    headers:
      Content-Type: application/json
    body_format: json
    body:
      registration_command:
        activation_keys: ["{{ activation_key_name }}"]
        insecure: false
        organization_id: "{{ satellite_org }}"
    status_code: 201
    validate_certs: false
  register: reg_cmd_response

- name: Extract registration command shell snippet
  set_fact:
    registration_command: "{{ reg_cmd_response.json.registration_command.command }}"

- name: Copy registration script to host
  ansible.builtin.copy:
    dest: /tmp/register_to_sat.sh
    content: |
      #!/bin/bash
      set -eux
      {{ registration_command }}
    mode: '0755'

- name: Execute registration script on host
  ansible.builtin.shell: /tmp/register_to_sat.sh
  become: true

- name: Validate host appears in Satellite
  redhat.satellite.host_info:
    name: "{{ inventory_hostname }}"
    organization: "{{ satellite_org }}"
  register: host_info
  retries: 3
  delay: 30
  until: host_info is succeeded
```

### 9.3 Notes for Agents and Developers
- This curl-based command internally calls `subscription-manager` using Satellite’s embedded registration endpoint.  
- The registration token (JWT) expires, ensuring secure execution.  
- Always regenerate a fresh command for each re-registration batch.  
- Do **not** store the generated command in plain text outside of memory or secure temporary storage.

---

## 10. Validation and Logging

```yaml
- name: Log host registration result
  ansible.builtin.lineinfile:
    path: "/var/log/aap_satellite_reregistration.log"
    line: "{{ inventory_hostname }} registered to capsule {{ capsule_name }}"
  delegate_to: localhost
```

---

## 11. Idempotency and Error Handling

```yaml
- name: Verify host registration status
  ansible.builtin.shell: subscription-manager identity
  register: sub_check
  ignore_errors: true

- name: Skip registration if already registered
  ansible.builtin.meta: end_host
  when: "'{{ satellite_fqdn }}' in sub_check.stdout"
```

---

## 12. Recommended Project Structure

```
satellite_host_reregistration/
├── roles/
│   ├── export_hosts/
│   ├── prepare_import/
│   ├── provision_lifecycle_env/
│   ├── generate_registration_command/
│   ├── register_hosts/
│   ├── log_results/
│   └── validate/
├── vars/
│   ├── main.yml
│   └── activation_keys.yml
├── inventories/
│   ├── dev/
│   └── prod/
├── playbooks/
│   ├── main.yml
│   ├── register.yml
│   └── validate.yml
└── README.md
```

---

## 13. Reference Documentation

| Resource | URL |
|-----------|-----|
| **Red Hat Satellite Ansible Collection Documentation** | https://catalog.redhat.com/en/software/collection/redhat/satellite#documentation |
| **Managing Satellite with Ansible Collections (Satellite 6.17 Admin Guide)** | https://access.redhat.com/documentation/en-us/red_hat_satellite/6.17/html/administration_guide/managing_satellite_with_ansible_collections |
| **Global Registration (6.17)** | https://docs.redhat.com/en/documentation/red_hat_satellite/6.17/html/managing_hosts/registering-hosts-and-setting-up-host-integration_managing-hosts |
| **TheForeman.Foreman Collection Documentation** | https://docs.ansible.com/ansible/latest/collections/theforeman/foreman/index.html |
| **Satellite REST API Reference** | https://access.redhat.com/documentation/en-us/red_hat_satellite/6.17/html/api_guide/ |

---

## 14. Summary

This project re-registers existing RHEL hosts from Satellite 6.14 to 6.17 via **AAP** using the **global registration API method**.  
Automation flow:

1. Export existing host data from 6.14  
2. Prepare minimal lifecycle environment on 6.17  
3. Generate curl-based registration commands via API  
4. Copy and execute registration script on each host  
5. Validate and log success/failure results  

By following this updated flow, automation remains aligned with **Red Hat’s supported global registration mechanism** while remaining **fully compatible with AAP and enterprise security standards**.

---

**End of Document — `primer.md`**
