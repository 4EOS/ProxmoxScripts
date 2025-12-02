#!/usr/bin/env bash
# Proxmox Windows VM Creator v2.0
# Interactive Windows VM creation with whiptail menus

function header_info {
  clear
  cat <<"EOF"
 _       ___           __                     _    ____  ___
| |     / (_)___  ____/ /___ _      _______  | |  / /  |/  /
| | /| / / / __ \/ __  / __ \ | /| / / ___/  | | / / /|_/ / 
| |/ |/ / / / / / /_/ / /_/ / |/ |/ (__  )   | |/ / /  / /  
|__/|__/_/_/ /_/\__,_/\____/|__/|__/____/    |___/_/  /_/   
                                                              
EOF
}

set -eEuo pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occurred.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON" 1>&2
  [ ! -z ${VMID-} ] && cleanup_vm
  exit $EXIT
}

function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}

function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}

function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

function cleanup_vm() {
  if qm status $VMID &>/dev/null; then
    if [ "$(qm status $VMID | awk '{print $2}')" == "running" ]; then
      qm stop $VMID
    fi
    qm destroy $VMID
  fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    die "Please run as root or with sudo"
fi

# Function to select storage
function select_storage() {
  local USAGE=$1
  local MSG_MAX_LENGTH=0
  local -a MENU

  while read -r line; do
    local TAG=$(echo $line | awk '{print $1}')
    local TYPE=$(echo $line | awk '{printf "%-10s", $2}')
    local FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    local ITEM="  Type: $TYPE Free: $FREE "
    local OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content images | awk 'NR>1')

  if [ $((${#MENU[@]} / 3)) -eq 0 ]; then
    die "No storage locations available for VM disks."
  elif [ $((${#MENU[@]} / 3)) -eq 1 ]; then
    printf ${MENU[0]}
  else
    local STORAGE
    STORAGE=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Storage Selection" --radiolist \
      "Select storage for $USAGE:\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${MENU[@]}" 3>&1 1>&2 2>&3) || die "Storage selection cancelled."
    printf $STORAGE
  fi
}

# Function to select ISO
function select_iso() {
  local ISO_DIR="/var/lib/vz/template/iso"
  local MSG_MAX_LENGTH=0
  local -a MENU

  if [ ! -d "$ISO_DIR" ]; then
    die "ISO directory not found: $ISO_DIR"
  fi

  while IFS= read -r iso_file; do
    local BASENAME=$(basename "$iso_file")
    local SIZE=$(ls -lh "$iso_file" | awk '{print $5}')
    local ITEM="  Size: $SIZE"
    local OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    MENU+=("$iso_file" "$ITEM" "OFF")
  done < <(find "$ISO_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null | sort)

  if [ $((${#MENU[@]} / 3)) -eq 0 ]; then
    die "No ISO files found in $ISO_DIR. Please upload a Windows ISO first."
  fi

  local ISO
  ISO=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "ISO Selection" --radiolist \
    "Select Windows ISO:\n" \
    20 $(($MSG_MAX_LENGTH + 58)) 12 \
    "${MENU[@]}" 3>&1 1>&2 2>&3) || die "ISO selection cancelled."
  printf "$ISO"
}

header_info
echo "Loading..."

# Confirm creation
whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Windows VM Creation" --yesno \
  "This will create a new Windows VM on this Proxmox host.\n\nProceed?" 10 60 || die "Cancelled by user."

# Get next available VM ID or allow custom
NEXT_VMID=$(pvesh get /cluster/nextid)
VMID=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "VM ID" --inputbox \
  "Enter VM ID (or press Enter for next available: $NEXT_VMID):" 10 60 "$NEXT_VMID" 3>&1 1>&2 2>&3) || die "VM ID input cancelled."

# Validate VM ID doesn't exist
if qm status $VMID &>/dev/null; then
  die "VM ID $VMID already exists!"
fi

# Get VM Name
VMNAME=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "VM Name" --inputbox \
  "Enter VM Name:" 10 60 "Windows-VM" 3>&1 1>&2 2>&3) || die "VM name input cancelled."

[ -z "$VMNAME" ] && die "VM name cannot be empty"

# Select Windows ISO
ISO_PATH=$(select_iso)
info "Selected ISO: $ISO_PATH"

# Memory configuration
MEMORY=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Memory Allocation" --inputbox \
  "Enter memory in MB:" 10 60 "4096" 3>&1 1>&2 2>&3) || die "Memory input cancelled."

# CPU Cores
CORES=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "CPU Cores" --inputbox \
  "Enter number of CPU cores:" 10 60 "2" 3>&1 1>&2 2>&3) || die "CPU cores input cancelled."

# CPU Sockets
SOCKETS=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "CPU Sockets" --inputbox \
  "Enter number of CPU sockets:" 10 60 "1" 3>&1 1>&2 2>&3) || die "CPU sockets input cancelled."

# CPU Type
CPU_TYPE=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "CPU Type" --radiolist \
  "Select CPU type:\n" 12 60 2 \
  "host" "Best performance (recommended)" ON \
  "kvm64" "Better migration compatibility" OFF \
  3>&1 1>&2 2>&3) || die "CPU type selection cancelled."

# Storage selection
STORAGE=$(select_storage "VM disk")
info "Using storage: $STORAGE"

# Disk size
DISKSIZE=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Disk Size" --inputbox \
  "Enter disk size in GB:" 10 60 "100" 3>&1 1>&2 2>&3) || die "Disk size input cancelled."

# SCSI Controller
SCSIHW=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "SCSI Controller" --radiolist \
  "Select SCSI controller type:\n" 14 70 3 \
  "lsi" "LSI Logic SAS (recommended, native Windows)" ON \
  "virtio-scsi-pci" "VirtIO SCSI (best performance, needs drivers)" OFF \
  "megasas" "MegaRAID SAS" OFF \
  3>&1 1>&2 2>&3) || die "SCSI controller selection cancelled."

# Check for VirtIO ISO if needed
VIRTIO_ISO=""
if [ "$SCSIHW" == "virtio-scsi-pci" ]; then
  if whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "VirtIO Drivers" --yesno \
    "VirtIO SCSI requires drivers during Windows installation.\n\nDo you have the VirtIO driver ISO available?" 12 60; then
    
    # Try to find VirtIO ISO automatically
    VIRTIO_FOUND=$(find /var/lib/vz/template/iso -name "*virtio*.iso" 2>/dev/null | head -n1)
    if [ -n "$VIRTIO_FOUND" ]; then
      VIRTIO_ISO="$VIRTIO_FOUND"
      info "Found VirtIO ISO: $VIRTIO_ISO"
    else
      warn "No VirtIO ISO found automatically. Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/"
    fi
  fi
fi

# Network Bridge
BRIDGE=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Network Bridge" --inputbox \
  "Enter network bridge:" 10 60 "vmbr0" 3>&1 1>&2 2>&3) || die "Network bridge input cancelled."

# VGA Type
VGA_TYPE=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Display Type" --radiolist \
  "Select VGA type:\n" 13 70 3 \
  "qxl" "QXL (best for Windows/SPICE)" ON \
  "std" "Standard VGA" OFF \
  "virtio" "VirtIO (better for Linux)" OFF \
  3>&1 1>&2 2>&3) || die "VGA type selection cancelled."

# BIOS Type
BIOS_TYPE=$(whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "BIOS Type" --radiolist \
  "Select BIOS type:\n" 12 70 2 \
  "seabios" "SeaBIOS (legacy BIOS, compatible)" ON \
  "ovmf" "OVMF (UEFI, required for Windows 11)" OFF \
  3>&1 1>&2 2>&3) || die "BIOS type selection cancelled."

# Additional options
ENABLE_AGENT=0
if whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "QEMU Guest Agent" --yesno \
  "Enable QEMU Guest Agent?\n(Recommended for better VM integration)" 10 60; then
  ENABLE_AGENT=1
fi

START_ON_BOOT=0
if whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Start on Boot" --yesno \
  "Start VM automatically on host boot?" 10 60; then
  START_ON_BOOT=1
fi

# Build summary for confirmation
SUMMARY="VM Configuration:\n\n"
SUMMARY+="VM ID: $VMID\n"
SUMMARY+="Name: $VMNAME\n"
SUMMARY+="Memory: ${MEMORY}MB\n"
SUMMARY+="CPU: ${CORES} cores, ${SOCKETS} socket(s), type ${CPU_TYPE}\n"
SUMMARY+="Storage: $STORAGE\n"
SUMMARY+="Disk: ${DISKSIZE}GB\n"
SUMMARY+="SCSI: $SCSIHW\n"
SUMMARY+="Network: $BRIDGE\n"
SUMMARY+="VGA: $VGA_TYPE\n"
SUMMARY+="BIOS: $BIOS_TYPE\n"
SUMMARY+="Guest Agent: $([ $ENABLE_AGENT -eq 1 ] && echo 'Enabled' || echo 'Disabled')\n"
SUMMARY+="Start on Boot: $([ $START_ON_BOOT -eq 1 ] && echo 'Yes' || echo 'No')"

whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Confirm VM Creation" --yesno \
  "$SUMMARY\n\nCreate VM with these settings?" 24 70 || die "VM creation cancelled."

# Create the VM
msg "Creating Windows VM $VMID..."

# Build base command
qm create $VMID \
    --name "$VMNAME" \
    --memory $MEMORY \
    --cores $CORES \
    --sockets $SOCKETS \
    --cpu $CPU_TYPE \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw $SCSIHW \
    --bios $BIOS_TYPE \
    --ostype win11 \
    --tablet 1 \
    --smbios1 uuid=$(uuidgen) || die "Failed to create VM"

# Add EFI disk if UEFI
if [ "$BIOS_TYPE" == "ovmf" ]; then
    info "Adding EFI disk..."
    qm set $VMID --efidisk0 ${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=1 || die "Failed to add EFI disk"
fi

# Add hard drive
info "Adding ${DISKSIZE}GB disk..."
qm set $VMID --scsi0 ${STORAGE}:${DISKSIZE},ssd=1 || die "Failed to add disk"

# Attach Windows ISO
info "Attaching Windows ISO..."
qm set $VMID --ide2 ${ISO_PATH},media=cdrom || die "Failed to attach ISO"

# Attach VirtIO ISO if provided
if [ -n "$VIRTIO_ISO" ]; then
    info "Attaching VirtIO driver ISO..."
    qm set $VMID --ide0 ${VIRTIO_ISO},media=cdrom
fi

# Set VGA
qm set $VMID --vga $VGA_TYPE || die "Failed to set VGA"

# Set boot order
qm set $VMID --boot order=scsi0\;ide2 || die "Failed to set boot order"

# Enable QEMU Guest Agent if requested
if [ $ENABLE_AGENT -eq 1 ]; then
    info "Enabling QEMU Guest Agent..."
    qm set $VMID --agent enabled=1
fi

# Set start on boot if requested
if [ $START_ON_BOOT -eq 1 ]; then
    info "Setting VM to start on boot..."
    qm set $VMID --onboot 1
fi

header_info
echo
info "VM $VMID '$VMNAME' created successfully!"
echo

# Save VM details to file
CREDS_FILE=~/vm-${VMID}-${VMNAME}.info
cat > "$CREDS_FILE" <<EOF
Windows VM Created: $(date)
VM ID: $VMID
VM Name: $VMNAME
Memory: ${MEMORY}MB
CPU: ${CORES} cores, ${SOCKETS} socket(s)
Disk: ${DISKSIZE}GB on $STORAGE
ISO: $ISO_PATH
Network: $BRIDGE
BIOS: $BIOS_TYPE

Useful Commands:
  Start VM: qm start $VMID
  Stop VM: qm stop $VMID
  View config: qm config $VMID
  Console: qm terminal $VMID
  Delete VM: qm destroy $VMID
EOF

info "VM details saved to: $CREDS_FILE"
echo

# Ask to start VM
if whiptail --backtitle "Proxmox VE - Windows VM Creator" --title "Start VM" --yesno \
  "VM created successfully!\n\nStart VM now?" 10 60; then
  msg "Starting VM $VMID..."
  qm start $VMID
  info "VM $VMID started!"
  echo
  info "Access via Proxmox web interface console"
else
  info "VM not started. Start manually with: qm start $VMID"
fi

echo
msg "Done!"
