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

# Function to get the current IP address assigned by DHCP
get_current_ip() {
    CURRENT_IP=$(ip addr show $PRIMARY_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    echo $CURRENT_IP
}

# Auto-detect primary network interface
INTERFACE=$(get_primary_interface)

# Auto-detect gateway and netmask
get_gateway_and_netmask

# Get the current DHCP-assigned IP address
CURRENT_IP=$(get_current_ip)

# Ask the user for a new IP address (defaulting to the current DHCP IP)
echo -n "Current IP address (DHCP-assigned): $CURRENT_IP"
read -p " Enter a new static IP (press Enter to keep the current IP): " NEW_IP

# If the user didn't enter a new IP, use the current IP
if [[ -z "$NEW_IP" ]]; then
    STATIC_IP=$CURRENT_IP
else
    STATIC_IP=$NEW_IP
fi

# Backup the original interfaces file
echo "Backing up /etc/network/interfaces..."
cp /etc/network/interfaces /etc/network/interfaces.bak

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
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"/' /etc/default/grub
sudo sed -i 's/^#GRUB_TERMINAL="console"/GRUB_TERMINAL="console serial"/' /etc/default/grub
sudo sed -i 's/^#GRUB_SERIAL_COMMAND="serial --speed=115200"/GRUB_SERIAL_COMMAND="serial --speed=115200"/' /etc/default/grub

# Step 2: Update GRUB to apply changes
echo "Updating GRUB..."
sudo update-grub

# Step 3: Enable serial-getty service on ttyS0 (Serial Console)
echo "Enabling serial-getty service on ttyS0..."
sudo systemctl enable serial-getty@ttyS0.service
sudo systemctl start serial-getty@ttyS0.service

# Step 4: Check the status of serial-getty service
echo "Checking status of serial-getty service..."
sudo systemctl status serial-getty@ttyS0.service

# ====================================
# Reboot Query

echo "Would you like to reboot the system now to apply changes? (y/n)"
read REBOOT

if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
    echo "Rebooting the system..."
    sudo reboot
else
    echo "Reboot skipped. You may want to reboot the system later for all changes to take effect."
fi
