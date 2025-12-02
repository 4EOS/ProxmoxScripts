\# Proxmox Scripts



Automation scripts for Proxmox VE to simplify VM creation and management.



---



\## 🖥️ Windows VM Creator



Interactive script to quickly create Windows/Windows Server VMs in Proxmox.



\### Quick Run

```bash

curl -sSL https://raw.githubusercontent.com/4EOS/ProxmoxScripts/main/windows.sh | sudo bash

```



\### Features



\- ✅ Interactive guided setup

\- ✅ Lists available ISOs and storage

\- ✅ SCSI controller options (LSI/VirtIO/MegaRAID)

\- ✅ UEFI support for Windows 11

\- ✅ Custom network and display configs

\- ✅ Input validation and error checking



\### What It Configures



| Setting | Options | Default |

|---------|---------|---------|

| CPU Type | host / kvm64 | host |

| Memory | Custom MB | 4096 |

| Disk Size | Custom GB | 100 |

| SCSI | LSI / VirtIO / MegaRAID | LSI |

| BIOS | SeaBIOS / OVMF (UEFI) | SeaBIOS |

| Network | Custom bridge | vmbr0 |



\### Usage



1\. Ensure Windows ISO is in `/var/lib/vz/template/iso/`

2\. Run the script

3\. Follow interactive prompts

4\. Confirm and create



\### SCSI Controllers



\- \*\*LSI\*\* - Native Windows support, easiest setup

\- \*\*VirtIO\*\* - Best performance (+20-30%), needs drivers

\- \*\*MegaRAID\*\* - Good balance



\### Windows 11



Select \*\*OVMF (UEFI)\*\* for BIOS type. The script auto-configures Secure Boot and TPM.



\### Common Commands

```bash

\# Start VM

qm start <VMID>



\# View config

qm config <VMID>



\# Stop VM

qm stop <VMID>

```



\### VirtIO Drivers



For VirtIO SCSI performance:

1\. Download: https://fedorapeople.org/groups/virt/virtio-win/

2\. Place in `/var/lib/vz/template/iso/`

3\. Load during Windows installation



