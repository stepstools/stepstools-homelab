#!/bin/bash

# Log output to a file for debugging
LOG_FILE="/var/log/setup-vm.log"
exec > >(tee -i $LOG_FILE)
exec 2>&1

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
    PRIMARY_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n 1)
    if [[ -z "$PRIMARY_INTERFACE" ]]; then
        echo "No active network interface found."
        exit 1
    fi
    echo $PRIMARY_INTERFACE
}

# Ask the user for static IP, netmask, and gateway
echo -n "Enter the desired static IP address: "
read STATIC_IP
if ! is_valid_ip "$STATIC_IP"; then
    echo "Invalid IP address. Exiting."
    exit 1
fi

echo -n "Enter the netmask (e.g., 255.255.255.0 or /24): "
read NETMASK
if [[ -z "$NETMASK" ]]; then
    echo "No netmask provided. Exiting."
    exit 1
fi

echo -n "Enter the gateway IP address: "
read GATEWAY
if ! is_valid_ip "$GATEWAY"; then
    echo "Invalid gateway address. Exiting."
    exit 1
fi

# Auto-detect primary network interface
INTERFACE=$(get_primary_interface)

# Backup the original /etc/network/interfaces file
echo "Backing up /etc/network/interfaces..."
cp /etc/network/interfaces /etc/network/interfaces.bak

# Backup the original GRUB config file
echo "Backing up GRUB configuration..."
cp /etc/default/grub /etc/default/grub.bak

# Update /etc/network/interfaces to configure a static IP (without DNS)
echo "Configuring static IP on interface $INTERFACE..."
cat <<EOL > /etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)

# Please note that this file is managed by the script.

# Loopback network interface
auto lo
iface lo inet loopback

# Primary network interface
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $NETMASK
    gateway $GATEWAY
EOL

# Restart networking service to apply changes
echo "Restarting networking service..."
systemctl restart networking

# Verify the new IP configuration
echo "Verifying the IP configuration..."
ip addr show $INTERFACE

# Run apt update and upgrade
echo "Running apt update and upgrade..."
apt update && apt upgrade -y

# Install unattended-upgrades and reconfigure it
echo "Installing unattended-upgrades..."
apt install -y unattended-upgrades
dpkg-reconfigure unattended-upgrades

# Install fail2ban
echo "Installing fail2ban..."
apt install -y fail2ban

echo "System updated and security tools installed successfully."

# ====================================
# Serial Console Setup for xterm.js in Proxmox

# Step 1: Modify GRUB configuration to enable serial console
echo "Modifying GRUB configuration for serial console..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"/' /etc/default/grub
sed -i 's/^#GRUB_TERMINAL="console"/GRUB_TERMINAL="console serial"/' /etc/default/grub
sed -i 's/^#GRUB_SERIAL_COMMAND="serial --speed=115200"/GRUB_SERIAL_COMMAND="serial --speed=115200"/' /etc/default/grub

# Step 2: Update GRUB to apply changes
echo "Updating GRUB..."
update-grub

# Step 3: Enable serial-getty service on ttyS0 (Serial Console)
echo "Enabling serial-getty service on ttyS0..."
systemctl enable serial-getty@ttyS0.service
systemctl start serial-getty@ttyS0.service

# Step 4: Check the status of serial-getty service
echo "Checking status of serial-getty service..."
systemctl status serial-getty@ttyS0.service

# ====================================
# Reboot Query

echo "Would you like to reboot the system now to apply changes? (y/n)"
read REBOOT

if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
    echo "Rebooting the system..."
    reboot
else
    echo "Reboot skipped. You may want to reboot the system later for all changes to take effect."
fi
