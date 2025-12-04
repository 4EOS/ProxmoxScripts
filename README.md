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

- LSI - Native Windows support, easiest setup

- VirtIO - Best performance (+20-30%), needs drivers

- MegaRAID - Good balance


#### Windows 11

Select OVMF (UEFI) for BIOS type. The script auto-configures Secure Boot and TPM.


#### VirtIO Drivers

For VirtIO SCSI performance:

1. Download: https://fedorapeople.org/groups/virt/virtio-win/

2. Place in `/var/lib/vz/template/iso/`

3. Load during Windows installation
