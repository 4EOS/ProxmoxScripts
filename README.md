# Proxmox Scripts

Automation scripts for Proxmox VE to simplify VM creation and management.


---

### 💬 Enable SNMP on Host 

```bash

bash <(curl -sSL https://raw.githubusercontent.com/4EOS/ProxmoxScripts/refs/heads/main/Setup-SNMP.sh)

```

---


### 🖥️ Windows VM Creator

Interactive script to quickly create Windows/Windows Server VMs in Proxmox.

#### Quick Run

```bash

bash <(curl -sSL https://raw.githubusercontent.com/4EOS/ProxmoxScripts/main/windows.sh)

```

#### Usage

1. Ensure your Windows ISO is uploaded to your Proxmox host so it shows up in `/var/lib/vz/template/iso/`

2. Run the script

3. Follow interactive prompts

4. Confirm and create

#### SCSI Controllers

- VirtIO - Best performance (+20-30%), needs drivers installed during setup which get added automatically

- LSI - Native Windows support, easiest setup


#### Windows 11

Select OVMF (UEFI) for BIOS type. The script auto-configures Secure Boot and TPM.

---

### 🔐 Acronis Registration Token Generator

Generate registration tokens for Acronis Cyber Protect agent deployment across customer organizations (MSP use).

#### Quick Run

```bash
bash <(curl -sSL https://raw.githubusercontent.com/4EOS/ProxmoxScripts/main/acronis/acronis_registrationcodegen.sh)
```

#### Usage

1. Set up Acronis API credentials in `~/.config/acronis/credentials`
2. Run the script to generate registration tokens for all customer tenants
3. Tokens are saved to `acronis_registrationkeys.json`
4. Use tokens to register Proxmox hosts with appropriate customer organizations

See [`acronis/acronis.md`](acronis/acronis.md) for detailed setup and deployment guide.
