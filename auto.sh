#!/bin/bash

# Function to auto-detect the primary network interface
get_primary_interface() {
    PRIMARY_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n 1)
    if [[ -z "$PRIMARY_INTERFACE" ]]; then
        echo "No active network interface found."
        exit 1
    fi
    echo $PRIMARY_INTERFACE
}

# Function to get the current gateway and netmask
get_gateway_and_netmask() {
    # Get the current gateway
    GATEWAY=$(ip route | grep default | awk '{print $3}')
    
    if [[ -z "$GATEWAY" ]]; then
        echo "No gateway found."
        exit 1
    fi

    # Get the netmask of the primary interface
    NETMASK=$(ip addr show $PRIMARY_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d'/' -f2)
    
    if [[ -z "$NETMASK" ]]; then
        echo "No netmask found for interface $PRIMARY_INTERFACE."
        exit 1
    fi

    echo "Gateway: $GATEWAY, Netmask: $NETMASK"
}

# Ask the user for a new IP address (since DHCP IP is not used anymore)
echo -n "Enter the desired static IP address: "
read STATIC_IP

if [[ -z "$STATIC_IP" ]]; then
    echo "No IP address provided. Exiting."
    exit 1
fi

# Auto-detect primary network interface
INTERFACE=$(get_primary_interface)

# Auto-detect gateway and netmask
get_gateway_and_netmask

# Pause after detecting the network settings
echo "Network settings detected. Press Enter to continue..."
read

# Backup the original interfaces file
echo "Backing up /etc/network/interfaces..."
cp /etc/network/interfaces /etc/network/interfaces.bak

# Pause after backup
echo "Backup completed. Press Enter to continue..."
read

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

# Pause after modifying interfaces file
echo "Network interface configuration updated. Press Enter to continue..."
read

# Restart networking service to apply changes
echo "Restarting networking service..."
systemctl restart networking

# Pause after restarting networking
echo "Networking service restarted. Press Enter to continue..."
read

# Verify the new IP configuration
echo "Verifying the IP configuration..."
ip addr show $INTERFACE

# Pause after verifying IP configuration
echo "IP configuration verified. Press Enter to continue..."
read

# Run apt update and upgrade
echo "Running apt update and upgrade..."
apt update && apt upgrade -y

# Pause after apt update and upgrade
echo "System update completed. Press Enter to continue..."
read

# Install unattended-upgrades and reconfigure it
echo "Installing unattended-upgrades..."
apt install -y unattended-upgrades
dpkg-reconfigure unattended-upgrades

# Pause after installing unattended-upgrades
echo "Unattended-upgrades installed and configured. Press Enter to continue..."
read

# Install fail2ban
echo "Installing fail2ban..."
apt install -y fail2ban

# Pause after installing fail2ban
echo "Fail2ban installed. Press Enter to continue..."
read

echo "System updated and security tools installed successfully."

# ====================================
# Serial Console Setup for xterm.js in Proxmox

# Step 1: Modify GRUB configuration to enable serial console
echo "Modifying GRUB configuration for serial console..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"/' /etc/default/grub
sed -i 's/^#GRUB_TERMINAL="console"/GRUB_TERMINAL="console serial"/' /etc/default/grub
sed -i 's/^#GRUB_SERIAL_COMMAND="serial --speed=115200"/GRUB_SERIAL_COMMAND="serial --speed=115200"/' /etc/default/grub

# Pause after modifying GRUB
echo "GRUB configuration updated. Press Enter to continue..."
read

# Step 2: Update GRUB to apply changes
echo "Updating GRUB..."
update-grub

# Pause after updating GRUB
echo "GRUB updated. Press Enter to continue..."
read

# Step 3: Enable serial-getty service on ttyS0 (Serial Console)
echo "Enabling serial-getty service on ttyS0..."
systemctl enable serial-getty@ttyS0.service
systemctl start serial-getty@ttyS0.service

# Pause after enabling serial-getty service
echo "serial-getty service enabled. Press Enter to continue..."
read

# Step 4: Check the status of serial-getty service
echo "Checking status of serial-getty service..."
systemctl status serial-getty@ttyS0.service

# Pause after checking serial-getty service
echo "Serial-getty service status displayed. Press Enter to continue..."
read

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
