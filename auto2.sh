#!/bin/bash

# --- Safety & Configuration ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
# Fail a pipeline if any command in it fails.
set -o pipefail

# Set DEBIAN_FRONTEND to noninteractive to prevent prompts
export DEBIAN_FRONTEND=noninteractive

# Log output to a file for debugging
LOG_FILE="/var/log/setup-vm.log"
# Redirect stdout and stderr to a log file AND the console
exec &> >(tee -a "$LOG_FILE")

# --- Logging Function ---

# Prepends a timestamp to all log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Root Check ---

log "Checking for root privileges..."
if [[ $EUID -ne 0 ]]; then
   log "This script must be run as root. Exiting."
   exit 1
fi

log "Script started. Logging to $LOG_FILE"

# --- Helper Functions ---

# Function to validate IP address format
is_valid_ip() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to auto-detect the primary network interface
get_primary_interface() {
    # This finds the interface used for the default route
    local interface
    interface=$(ip route get 1.1.1.1 | awk -F 'dev' '{print $2}' | awk '{print $1}')
    if [[ -z "$interface" ]]; then
        log "Could not auto-detect primary network interface. Exiting."
        exit 1
    fi
    echo "$interface"
}

# --- User Input ---

log "Gathering network information..."

read -p "Enter the desired static IP address: " STATIC_IP
if ! is_valid_ip "$STATIC_IP"; then
    log "Invalid IP address: $STATIC_IP. Exiting."
    exit 1
fi

read -p "Enter the netmask (e.g., 255.255.255.0): " NETMASK
if [[ -z "$NETMASK" ]]; then
    log "No netmask provided. Exiting."
    exit 1
fi

read -p "Enter the gateway IP address: " GATEWAY
if ! is_valid_ip "$GATEWAY"; then
    log "Invalid gateway address: $GATEWAY. Exiting."
    exit 1
fi

# *** ADDED DNS PROMPTS ***
read -p "Enter DNS servers (space-separated, e.g., '1.1.1.1 8.8.8.8'): " DNS_SERVERS
if [[ -z "$DNS_SERVERS" ]]; then
    log "No DNS servers provided. apt update will likely fail. Exiting."
    exit 1
fi

# Auto-detect primary network interface
INTERFACE=$(get_primary_interface)
log "Detected primary interface: $INTERFACE"

# --- Network Configuration (/etc/network/interfaces) ---

# Backup the original /etc/network/interfaces file
log "Backing up /etc/network/interfaces..."
cp /etc/network/interfaces /etc/network/interfaces.bak

log "Configuring static IP on interface $INTERFACE..."
cat <<EOL > /etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# This file is managed by the setup-vm.sh script.

# Loopback network interface
auto lo
iface lo inet loopback

# Primary network interface
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVERS
EOL

# Restart networking service to apply changes
log "Restarting networking service..."
# ifdown/ifup is often safer than a full restart
ifdown "$INTERFACE" || log "ifdown failed, proceeding..."
ifup "$INTERFACE"

log "Waiting 5 seconds for network..."
sleep 5

# Verify the new IP configuration
log "Verifying the IP configuration..."
ip addr show "$INTERFACE"
log "Pinging gateway to test connectivity..."
ping -c 3 "$GATEWAY"

# --- System Updates & Packages ---

log "Running apt update and full-upgrade..."
apt update && apt full-upgrade -y

log "Installing security packages..."
# Install all at once, much faster
apt install -y unattended-upgrades fail2ban

# Removed interactive dpkg-reconfigure
log "unattended-upgrades and fail2ban installed with default settings."
log "To customize, run 'dpkg-reconfigure unattended-upgrades' manually."

# --- Serial Console Setup ---

log "Backing up GRUB configuration..."
cp /etc/default/grub /etc/default/grub.bak

# Robustly set GRUB options (idempotent)
set_grub_config() {
    local key=$1
    local value=$2
    log "Setting GRUB config: $key = $value"
    # If key already exists (commented or not), replace it
    if grep -q "^.*${key}=.*" /etc/default/grub; then
        sed -i -E "s/^.*${key}=.*/${key}=${value}/" /etc/default/grub
    # Otherwise, add it to the end of the file
    else
        echo "${key}=${value}" >> /etc/default/grub
    fi
}

log "Modifying GRUB configuration for serial console..."

# Get current CMDLINE, remove "quiet" if it exists, then add our options
CURRENT_CMDLINE=$(grep 'GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub | cut -d'"' -f2 || echo "")
# Remove "quiet"
CURRENT_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed 's/quiet//g')
# Add new options, avoiding duplicates
NEW_CMDLINE="$CURRENT_CMDLINE console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"
# Clean up potential double spaces
NEW_CMDLINE=$(echo "$NEW_CMDLINE" | tr -s ' ')

set_grub_config "GRUB_CMDLINE_LINUX_DEFAULT" "\"$NEW_CMDLINE\""
set_grub_config "GRUB_TERMINAL" "\"console serial\""
set_grub_config "GRUB_SERIAL_COMMAND" "\"serial --speed=115200\""

log "Updating GRUB..."
update-grub

log "Enabling and starting serial-getty service on ttyS0..."
systemctl enable serial-getty@ttyS0.service
systemctl start serial-getty@ttyS0.service

log "Checking status of serial-getty service..."
# --no-pager prevents 'status' from hanging the script
systemctl --no-pager status serial-getty@ttyS0.service

# --- Reboot Query ---

log "Setup complete."
read -p "Would you like to reboot the system now? (y/n) " -n 1 -r REPLY
echo # Move to a new line

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    log "Rebooting the system..."
    reboot
else
    log "Reboot skipped. Please reboot later for all changes (especially GRUB) to take effect."
fi
