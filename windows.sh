#!/bin/bash

# Proxmox Windows VM Creator

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Proxmox Windows VM Creator v1.0       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

# List available ISOs
echo -e "${BLUE}=== Step 1: Select ISO ===${NC}"
ISO_DIR="/var/lib/vz/template/iso"
if [ -d "$ISO_DIR" ]; then
    echo -e "${YELLOW}Available ISO files:${NC}"
    ls -lh "$ISO_DIR"/*.iso 2>/dev/null | awk '{print NR") " $9 " (" $5 ")"}' || echo "No ISOs found in $ISO_DIR"
    echo ""
else
    echo -e "${RED}ISO directory not found: $ISO_DIR${NC}"
    exit 1
fi

read -p "Enter the full path to the Windows ISO: " ISO_PATH
if [ ! -f "$ISO_PATH" ]; then
    echo -e "${RED}ISO file not found: $ISO_PATH${NC}"
    exit 1
fi

# Prompt for VM ID
echo -e "\n${BLUE}=== Step 2: VM Identification ===${NC}"
read -p "Enter VM ID (100-999999): " VMID
if qm status $VMID &>/dev/null; then
    echo -e "${RED}VM ID $VMID already exists!${NC}"
    exit 1
fi

# Prompt for VM Name
read -p "Enter VM Name: " VMNAME
if [ -z "$VMNAME" ]; then
    echo -e "${RED}VM Name cannot be empty${NC}"
    exit 1
fi

# Prompt for Resources
echo -e "\n${BLUE}=== Step 3: Resource Allocation ===${NC}"
read -p "Enter Memory in MB (default: 4096): " MEMORY
MEMORY=${MEMORY:-4096}

read -p "Enter number of CPU cores (default: 2): " CORES
CORES=${CORES:-2}

read -p "Enter number of CPU sockets (default: 1): " SOCKETS
SOCKETS=${SOCKETS:-1}

# Prompt for CPU Type
echo -e "\n${YELLOW}CPU Type options:${NC}"
echo "1) host (best performance, recommended)"
echo "2) kvm64 (better compatibility for migration)"
read -p "Select CPU type [1-2] (default: 1): " CPU_CHOICE
case $CPU_CHOICE in
    2) CPU_TYPE="kvm64" ;;
    *) CPU_TYPE="host" ;;
esac

# List available storage
echo -e "\n${BLUE}=== Step 4: Storage Configuration ===${NC}"
echo -e "${YELLOW}Available storage:${NC}"
pvesm status | grep -v "^[[:space:]]*$"
echo ""

read -p "Enter storage location (default: local-lvm): " STORAGE
STORAGE=${STORAGE:-local-lvm}

# Verify storage exists
if ! pvesm status | grep -q "^$STORAGE "; then
    echo -e "${YELLOW}Warning: Storage '$STORAGE' not found in list, continuing anyway...${NC}"
fi

read -p "Enter disk size in GB (default: 100): " DISKSIZE
DISKSIZE=${DISKSIZE:-100}

# Prompt for SCSI Controller Type
echo -e "\n${YELLOW}SCSI Controller Type:${NC}"
echo "1) LSI Logic SAS (native Windows support, recommended for easy setup)"
echo "2) VirtIO SCSI (best performance, requires VirtIO drivers during install)"
echo "3) MegaRAID SAS (alternative with good performance)"
read -p "Select SCSI controller [1-3] (default: 1): " SCSI_CHOICE
case $SCSI_CHOICE in
    2) 
        SCSIHW="virtio-scsi-pci"
        echo -e "${YELLOW}Note: You'll need VirtIO drivers during Windows installation!${NC}"
        echo "Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/"
        read -p "Do you have VirtIO driver ISO available? (y/n): " HAS_VIRTIO
        if [[ $HAS_VIRTIO =~ ^[Yy]$ ]]; then
            read -p "Enter path to VirtIO driver ISO: " VIRTIO_ISO
            if [ ! -f "$VIRTIO_ISO" ]; then
                echo -e "${RED}VirtIO ISO not found, continuing without it${NC}"
                VIRTIO_ISO=""
            fi
        fi
        ;;
    3) SCSIHW="megasas" ;;
    *) SCSIHW="lsi" ;;
esac

# Network Configuration
echo -e "\n${BLUE}=== Step 5: Network Configuration ===${NC}"
read -p "Enter network bridge (default: vmbr0): " BRIDGE
BRIDGE=${BRIDGE:-vmbr0}

read -p "Set static MAC address? (y/n, default: n): " SET_MAC
if [[ $SET_MAC =~ ^[Yy]$ ]]; then
    read -p "Enter MAC address (format: XX:XX:XX:XX:XX:XX): " MAC_ADDR
    NET_CONFIG="virtio,bridge=$BRIDGE,macaddr=$MAC_ADDR"
else
    NET_CONFIG="virtio,bridge=$BRIDGE"
fi

# Display Options
echo -e "\n${BLUE}=== Step 6: Display Configuration ===${NC}"
echo -e "${YELLOW}VGA Type options:${NC}"
echo "1) qxl (best for SPICE, recommended for Windows)"
echo "2) std (standard VGA)"
echo "3) virtio (better for Linux guests)"
read -p "Select VGA type [1-3] (default: 1): " VGA_CHOICE
case $VGA_CHOICE in
    2) VGA_TYPE="std" ;;
    3) VGA_TYPE="virtio" ;;
    *) VGA_TYPE="qxl" ;;
esac

# BIOS Configuration
echo -e "\n${YELLOW}BIOS Type:${NC}"
echo "1) SeaBIOS (legacy BIOS, better compatibility)"
echo "2) OVMF (UEFI, required for Windows 11, Secure Boot)"
read -p "Select BIOS type [1-2] (default: 1): " BIOS_CHOICE
case $BIOS_CHOICE in
    2) 
        BIOS_TYPE="ovmf"
        # For UEFI, we need to add EFI disk
        EFI_DISK="--efidisk0 ${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=1"
        ;;
    *) 
        BIOS_TYPE="seabios"
        EFI_DISK=""
        ;;
esac

# Additional Options
echo -e "\n${BLUE}=== Step 7: Additional Options ===${NC}"
read -p "Enable QEMU Guest Agent? (recommended) (y/n, default: y): " ENABLE_AGENT
ENABLE_AGENT=${ENABLE_AGENT:-y}

read -p "Set VM to start on boot? (y/n, default: n): " START_ON_BOOT
START_ON_BOOT=${START_ON_BOOT:-n}

# Summary
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     VM Configuration Summary           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}VM ID:${NC} $VMID"
echo -e "${YELLOW}VM Name:${NC} $VMNAME"
echo -e "${YELLOW}Memory:${NC} ${MEMORY}MB"
echo -e "${YELLOW}CPU Cores:${NC} $CORES"
echo -e "${YELLOW}CPU Sockets:${NC} $SOCKETS"
echo -e "${YELLOW}CPU Type:${NC} $CPU_TYPE"
echo -e "${YELLOW}Storage:${NC} $STORAGE"
echo -e "${YELLOW}Disk Size:${NC} ${DISKSIZE}GB"
echo -e "${YELLOW}SCSI Controller:${NC} $SCSIHW"
echo -e "${YELLOW}Network Bridge:${NC} $BRIDGE"
echo -e "${YELLOW}VGA Type:${NC} $VGA_TYPE"
echo -e "${YELLOW}BIOS Type:${NC} $BIOS_TYPE"
echo -e "${YELLOW}ISO:${NC} $ISO_PATH"
[ -n "$VIRTIO_ISO" ] && echo -e "${YELLOW}VirtIO ISO:${NC} $VIRTIO_ISO"
echo -e "${YELLOW}Guest Agent:${NC} $([[ $ENABLE_AGENT =~ ^[Yy]$ ]] && echo 'Enabled' || echo 'Disabled')"
echo -e "${YELLOW}Start on Boot:${NC} $([[ $START_ON_BOOT =~ ^[Yy]$ ]] && echo 'Yes' || echo 'No')"
echo ""

read -p "Create VM with these settings? (y/n): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
fi

# Create the VM
echo -e "\n${GREEN}Creating VM $VMID...${NC}"

qm create $VMID \
    --name "$VMNAME" \
    --memory $MEMORY \
    --cores $CORES \
    --sockets $SOCKETS \
    --cpu $CPU_TYPE \
    --net0 $NET_CONFIG \
    --scsihw $SCSIHW \
    --bios $BIOS_TYPE \
    --ostype win11

# Add EFI disk if UEFI
if [ -n "$EFI_DISK" ]; then
    echo "Adding EFI disk..."
    qm set $VMID $EFI_DISK
fi

# Add hard drive
echo "Adding ${DISKSIZE}GB disk..."
qm set $VMID --scsi0 ${STORAGE}:${DISKSIZE},ssd=1

# Attach Windows ISO
echo "Attaching Windows ISO..."
qm set $VMID --ide2 ${ISO_PATH},media=cdrom

# Attach VirtIO ISO if provided
if [ -n "$VIRTIO_ISO" ]; then
    echo "Attaching VirtIO driver ISO..."
    qm set $VMID --ide0 ${VIRTIO_ISO},media=cdrom
fi

# Set VGA
qm set $VMID --vga $VGA_TYPE

# Set boot order
qm set $VMID --boot order=scsi0\;ide2

# Set SMBIOS UUID
qm set $VMID --smbios1 uuid=$(uuidgen)

# Enable QEMU Guest Agent if requested
if [[ $ENABLE_AGENT =~ ^[Yy]$ ]]; then
    echo "Enabling QEMU Guest Agent..."
    qm set $VMID --agent enabled=1
fi

# Set start on boot if requested
if [[ $START_ON_BOOT =~ ^[Yy]$ ]]; then
    echo "Setting VM to start on boot..."
    qm set $VMID --onboot 1
fi

# Enable tablet for better mouse support
qm set $VMID --tablet 1

echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   VM $VMID Created Successfully! ✓     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

# Ask if user wants to start the VM
read -p "Start VM now? (y/n): " START_VM
if [[ $START_VM =~ ^[Yy]$ ]]; then
    qm start $VMID
    echo -e "${GREEN}VM $VMID started!${NC}"
    echo -e "\n${YELLOW}Access the VM:${NC}"
    echo "  Console: Access via Proxmox web interface"
    echo "  Terminal: qm terminal $VMID"
    echo "  Monitor: qm monitor $VMID"
else
    echo -e "\n${YELLOW}VM not started. Start manually with:${NC}"
    echo "  qm start $VMID"
fi

echo -e "\n${BLUE}Useful commands:${NC}"
echo "  View VM config: qm config $VMID"
echo "  Stop VM: qm stop $VMID"
echo "  Delete VM: qm destroy $VMID"
echo ""