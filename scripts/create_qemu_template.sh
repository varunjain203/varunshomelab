#!/bin/bash

# A script to connect to your Proxmox server via ssh and keys and automate the creation of an Ubuntu 22.04 Cloud-Init template on Proxmox.

# --- Configuration ---
# Set the VMID you want to use for the template.
VMID="9000"
# Set the Ubuntu cloud image URL.
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
# Get the filename from the URL.
IMAGE_FILENAME=$(basename "$IMAGE_URL")
# Define the storage path on the Proxmox server.
IMAGE_STORAGE_PATH="/var/lib/vz/template/iso"

# --- Script Start ---
echo "Proxmox Ubuntu Cloud-Init Template Setup"
echo "========================================"

# 1. Get Proxmox server details from user
read -p "Enter the Proxmox server IP address or hostname: " PROXMOX_HOST
if [ -z "$PROXMOX_HOST" ]; then
    echo "❌ Error: Hostname/IP cannot be empty."
    exit 1
fi

# 2. Check for and generate SSH keys if they don't exist
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "🔑 SSH key not found. Generating a new one..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" # -N "" for no passphrase
else
    echo "🔑 SSH key already exists at $SSH_KEY_PATH."
fi

# 3. Copy SSH key to the Proxmox server
echo "🔐 Attempting to copy SSH key to root@$PROXMOX_HOST..."
ssh-copy-id "root@$PROXMOX_HOST"
if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to copy SSH key."
    echo "Please check the following:"
    echo "  - Ensure SSH is enabled for the 'root' user on your Proxmox server."
    echo "  - Verify the IP/hostname and the root password are correct."
    exit 1
fi

echo "SSH key copied successfully."

# 4. SSH into the Proxmox server and execute commands
echo "Connecting to Proxmox server to create the template..."

ssh "root@$PROXMOX_HOST" <<EOF
# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Executing on Proxmox Server ---"

# Check if a VM or template with the specified ID already exists
if qm status $VMID > /dev/null 2>&1; then
    echo "⚠️ Warning: VM/Template $VMID already exists. Stopping and destroying it first."
    # The '|| true' will prevent the script from exiting if the VM is already stopped.
    qm stop $VMID || true
    qm destroy $VMID
fi

# Create the directory for images if it doesn't exist
mkdir -p "$IMAGE_STORAGE_PATH"

# Download the cloud image
echo "Downloading Ubuntu 22.04 cloud image..."
wget -O "$IMAGE_STORAGE_PATH/$IMAGE_FILENAME" "$IMAGE_URL"

# Create the VM
echo "🔧 Creating new VM (ID: $VMID)..."
qm create $VMID --name "ubuntu-2204-cloudinit-template" --memory 2048 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci

# Import the downloaded disk to the 'local-lvm' storage
echo "Importing disk to 'local-lvm'..."
qm set $VMID --scsi0 local-lvm:0,import-from="$IMAGE_STORAGE_PATH/$IMAGE_FILENAME"

# Add the cloud-init drive
echo "Adding cloud-init drive..."
qm set $VMID --ide2 local-lvm:cloudinit

# Set the boot order to the imported disk
echo "Setting boot order..."
qm set $VMID --boot order=scsi0

# Convert the VM into a template
echo "Converting VM to template..."
qm template $VMID

echo "--- Finished on Proxmox Server ---"
EOF

# Check the exit status of the SSH command
if [ $? -eq 0 ]; then
    echo "Success! Ubuntu 22.04 Cloud-Init template (ID: $VMID) is now available on $PROXMOX_HOST."
else
    echo "An error occurred during the remote execution on the Proxmox server."
fi