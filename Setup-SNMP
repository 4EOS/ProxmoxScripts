#!/bin/bash

# Install SNMP daemon
apt update && apt install -y snmpd

# Backup original configuration
cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.backup

# Get hostname for default sysLocation
HOSTNAME=$(hostname)

# Prompt for sysLocation
read -p "Enter sysLocation [default: $HOSTNAME]: " SYS_LOCATION
SYS_LOCATION=${SYS_LOCATION:-$HOSTNAME}

# Prompt for sysContact
read -p "Enter sysContact [default: blank]: " SYS_CONTACT
SYS_CONTACT=${SYS_CONTACT:-""}

# Prompt for authentication
read -p "Use authentication and encryption? (y/N): " USE_AUTH
USE_AUTH=${USE_AUTH:-N}

if [[ "$USE_AUTH" =~ ^[Yy]$ ]]; then
    # Prompt for auth password
    while true; do
        read -sp "Enter authentication password (min 8 characters): " AUTH_PASS
        echo
        if [ ${#AUTH_PASS} -lt 8 ]; then
            echo "Error: Password must be at least 8 characters"
            continue
        fi
        read -sp "Confirm authentication password: " AUTH_PASS_CONFIRM
        echo
        if [ "$AUTH_PASS" = "$AUTH_PASS_CONFIRM" ]; then
            break
        else
            echo "Error: Passwords do not match"
        fi
    done

    # Prompt for privacy password
    while true; do
        read -sp "Enter privacy password (min 8 characters): " PRIV_PASS
        echo
        if [ ${#PRIV_PASS} -lt 8 ]; then
            echo "Error: Password must be at least 8 characters"
            continue
        fi
        read -sp "Confirm privacy password: " PRIV_PASS_CONFIRM
        echo
        if [ "$PRIV_PASS" = "$PRIV_PASS_CONFIRM" ]; then
            break
        else
            echo "Error: Passwords do not match"
        fi
    done

    # Stop snmpd to create user
    systemctl stop snmpd

    # Create SNMPv3 user with MD5 auth and AES encryption
    net-snmp-create-v3-user -ro -A "$AUTH_PASS" -a MD5 -X "$PRIV_PASS" -x AES auvik

    # Configure with authPriv
    cat > /etc/snmp/snmpd.conf <<EOF
# SNMPv3 Configuration for Auvik (authPriv)
agentAddress udp:161

# Grant read-only access to auvik user with authPriv
rouser auvik authpriv

# System information
sysLocation    "$SYS_LOCATION"
sysContact     "$SYS_CONTACT"
sysServices    72

# Enable full MIB access
view systemonly included .1
EOF

    echo ""
    echo "========================================="
    echo "SNMPv3 Configuration (authPriv)"
    echo "========================================="
    echo "Username:        auvik"
    echo "Auth Protocol:   MD5"
    echo "Auth Password:   [hidden]"
    echo "Privacy Protocol: AES"
    echo "Privacy Password: [hidden]"
    echo "========================================="

else
    # Configure SNMPv3 without authentication (noAuthNoPriv)
    cat > /etc/snmp/snmpd.conf <<EOF
# SNMPv3 Configuration for Auvik (noAuthNoPriv)
agentAddress udp:161

# Create SNMPv3 user 'auvik' with noAuthNoPriv
createUser auvik

# Grant read-only access to the auvik user
rouser auvik noauth

# System information
sysLocation    "$SYS_LOCATION"
sysContact     "$SYS_CONTACT"
sysServices    72

# Enable full MIB access
view systemonly included .1
EOF

    echo ""
    echo "========================================="
    echo "SNMPv3 Configuration (noAuthNoPriv)"
    echo "========================================="
    echo "Username:        auvik"
    echo "Auth Protocol:   None"
    echo "Privacy Protocol: None"
    echo "========================================="
fi

# Restart SNMP service
systemctl restart snmpd

# Enable SNMP service to start on boot
systemctl enable snmpd

# Verify service status
echo ""
systemctl status snmpd --no-pager

echo ""
echo "========================================="
echo "System Information"
echo "========================================="
echo "sysLocation: $SYS_LOCATION"
echo "sysContact:  $SYS_CONTACT"
echo "========================================="
echo ""
echo "Note: Ensure UDP port 161 is open in your firewall for Auvik's collector IP"
