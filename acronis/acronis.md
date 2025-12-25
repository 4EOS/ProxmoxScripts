# Acronis Cyber Protect – Proxmox VE (MSP Quick Guide)

## Overview

Acronis Cyber Protect (v25.07+) supports **agentless backups for Proxmox VE 8.2+ / 9.x** using a lightweight host agent.
VMs and containers are protected via the Proxmox API—no in-guest agents required.

**Critical MSP Rule:**
Proxmox hosts **must be registered under a CLIENT (customer) organization**, not the MSP root tenant. This guide assumes registration tokens are generated using the provided MSP automation script.

---

## Requirements

* Proxmox VE 8.2+ or 9.x
* Root access on each Proxmox node
* Acronis Cyber Protect Cloud (MSP)
* One VM quota per VM/container
* Outbound internet access
* `curl` and `jq` (for token generation script)

---

## Network Requirements (Outbound Only)

**Ports**

* 443, 8443 – HTTPS / registration / management
* 7770–7800 – Agent communication
* 44445 – Backup data transfer

**Domains**

* `download.acronis.com`
* `dl.acronis.com`
* `dl.managed-protection.com`

---

## Step 1: Generate CLIENT Registration Tokens (MSP)

Use the **Acronis Registration Token Generator for MSPs** script.

### What the script does

* Authenticates using Acronis API credentials
* Lists all **client (customer) tenants**
* Generates **per-client registration tokens**
* Outputs tokens to `acronis_registrationkeys.json`
* Ensures tokens are scoped correctly for agent registration

### Run

```bash
./acronis_generate_tokens.sh
```

You will:

1. Select your Acronis datacenter
2. Authenticate with API Client ID / Secret
3. Select one, multiple, or all client orgs
4. Choose token expiration (default: 3 days)

**Output**

* `acronis_registrationkeys.json`
  Contains tenant name, tenant ID, token, expiration, and datacenter URL.

---

## Step 2: Prepare Proxmox Host

```bash
apt update && apt upgrade -y
apt install -y pve-headers-$(uname -r) gcc make perl rpm
```

Verify headers:

```bash
ls /lib/modules/$(uname -r)/build
```

---

## Step 3: Install Acronis Agent on Proxmox

Install **on every Proxmox node** (required for clusters and live migration).

```bash
cd /tmp
wget https://download.acronis.com/agent/lin/24.04/acronis_agent_x86_64.sh
chmod +x acronis_agent_x86_64.sh
```

Register using a **client token** from the JSON output:

```bash
./acronis_agent_x86_64.sh \
  --quiet \
  --registration by-token \
  --reg-token "CLIENT_REGISTRATION_TOKEN" \
  --reg-address "https://us15-cloud.acronis.com"
```

Replace the address if needed:

* US: `https://us15-cloud.acronis.com`
* EU: `https://eu-cloud.acronis.com`
* EU2: `https://eu2-cloud.acronis.com`
* APAC: `https://ap-cloud.acronis.com`

---

## Step 4: Verify Registration

```bash
systemctl status acronis_agent
/opt/acronis/bin/acronis_agent --show-registration-info
```

In the Acronis console:

* Switch to the **client organization**
* Devices → All Devices
* Confirm Proxmox host is **Online**

---

## Step 5: Configure Backups

From the **client organization**:

1. Devices → Select Proxmox host
2. VMs and containers are auto-discovered
3. Create a protection plan:

   * Incremental daily, full weekly
   * Encryption enabled
   * Cloud / local / S3 / NFS destination
   * Retention per client policy

**Recommended**

* Stagger backup start times
* Test restores immediately
* Install agent on all cluster nodes

---

## Cluster Deployment (Example)

```bash
NODES=("pve1" "pve2" "pve3")
TOKEN="CLIENT_REGISTRATION_TOKEN"
DC="https://us-cloud.acronis.com"

for node in "${NODES[@]}"; do
  ssh root@$node "
    cd /tmp &&
    wget -q https://download.acronis.com/agent/lin/24.04/acronis_agent_x86_64.sh &&
    chmod +x acronis_agent_x86_64.sh &&
    ./acronis_agent_x86_64.sh --quiet --registration by-token \
      --reg-token $TOKEN --reg-address $DC
  "
done
```

---

## Incorrect Registration (MSP Root)

If a host was registered under the MSP root tenant:

```bash
/opt/acronis/bin/acronis_agent unregister
```

* Delete the device from the MSP org
* Generate a **new client token**
* Re-register using the correct token

---

## Key Paths

* Binary: `/opt/acronis/bin/acronis_agent`
* Logs: `/var/log/acronis/agent/`
* Config: `/etc/acronis/`

---

## Key Takeaways

* Always register Proxmox hosts under **client tenants**
* Use the token-generation script for consistency and scale
* Install the agent on **every Proxmox node**
* No VM agents required (agentless)
* Verify backups and restores before production
