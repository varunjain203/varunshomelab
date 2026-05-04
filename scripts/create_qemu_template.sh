#!/bin/bash

# A script to automate the creation of an Ubuntu 22.04 Cloud-Init template on Proxmox.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- Configuration ---
VMID="${VMID:-9000}"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILENAME=$(basename "$IMAGE_URL")
IMAGE_STORAGE_PATH="/var/lib/vz/template/iso"
STORAGE_POOL="${STORAGE_POOL:-local-lvm}"

# --- Color output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Functions ---
log_info() {
    echo -e "${GREEN}ℹ️  $*${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

# --- Script Start ---
echo "Proxmox Ubuntu Cloud-Init Template Setup"
echo "========================================"

# Try to extract Proxmox host from terraform.tfvars
TFVARS_FILE="$(dirname "$0")/../terraform/terraform.tfvars"
PROXMOX_HOST=""

if [ -f "$TFVARS_FILE" ]; then
    if grep -qE '^[[:space:]]*PROXMOX_URL' "$TFVARS_FILE"; then
        PROXMOX_URL=$(grep -E '^[[:space:]]*PROXMOX_URL' "$TFVARS_FILE" | cut -d'"' -f2 | head -n 1)
        if [ -n "$PROXMOX_URL" ] && [[ "$PROXMOX_URL" != *"your-proxmox-server"* ]]; then
            PROXMOX_HOST=$(echo "$PROXMOX_URL" | sed -E 's~^https?://([^/:]+).*~\1~')
            log_info "Extracted Proxmox host ($PROXMOX_HOST) from terraform.tfvars."
        fi
    fi
fi

# Fallback to manual input if not found
if [ -z "$PROXMOX_HOST" ]; then

    read -p "Enter the Proxmox server IP address or hostname: " PROXMOX_HOST
    if [ -z "$PROXMOX_HOST" ]; then
        log_error "Hostname/IP cannot be empty."
        exit 1
    fi
fi

# Validate SSH connectivity
log_info "Validating SSH connection to root@$PROXMOX_HOST..."
if ! ssh -o ConnectTimeout=5 "root@$PROXMOX_HOST" "echo 'SSH OK'" > /dev/null 2>&1; then
    log_error "Cannot connect to root@$PROXMOX_HOST"
    exit 1
fi

# Check for and generate SSH keys
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    log_info "SSH key not found. Generating a new one..."
    read -sp "Enter passphrase for SSH key (empty for no passphrase): " ssh_pass
    echo
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "$ssh_pass" -C "proxmox-template"
else
    log_info "SSH key already exists at $SSH_KEY_PATH."
fi

# Copy SSH key to Proxmox server
log_info "Copying SSH key to root@$PROXMOX_HOST..."
if ! ssh-copy-id -o ConnectTimeout=5 "root@$PROXMOX_HOST" 2>/dev/null; then
    log_error "Failed to copy SSH key."
    echo "Please check:"
    echo "  - SSH is enabled for the 'root' user on Proxmox"
    echo "  - IP/hostname and root password are correct"
    exit 1
fi

log_info "SSH setup complete."

# Connect and create template
log_info "Connecting to Proxmox server..."

if ! ssh "root@$PROXMOX_HOST" bash << 'REMOTE_EOF'
set -euo pipefail

VMID="9000"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILENAME=$(basename "$IMAGE_URL")
IMAGE_STORAGE_PATH="/var/lib/vz/template/iso"
STORAGE_POOL="local-lvm"
FULL_IMAGE_PATH="$IMAGE_STORAGE_PATH/$IMAGE_FILENAME"
MAX_RETRIES=3
RETRY_DELAY=5

retry_curl() {
    local url="$1"
    local output="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "Downloading (attempt $attempt/$MAX_RETRIES)..."
        if curl -fsSL --progress-bar --location -o "$output" "$url"; then
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "Download failed. Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
        attempt=$((attempt + 1))
    done
    
    return 1
}

trap 'echo "Error on line $LINENO"' ERR

echo "--- Executing on Proxmox Server ---"

# Check if template already exists
if qm status "$VMID" > /dev/null 2>&1; then
    echo "✅ Template $VMID already exists. Exiting."
    exit 0
fi

# Validate storage pool exists
if ! pvesm status | awk '{print $1}' | grep -x -q "$STORAGE_POOL"; then
    echo "❌ Storage pool '$STORAGE_POOL' not found."
    exit 1
fi

# Create directory and download image
mkdir -p "$IMAGE_STORAGE_PATH"

if [ ! -f "$FULL_IMAGE_PATH" ]; then
    echo "📥 Downloading Ubuntu 22.04 cloud image..."
    if ! retry_curl "$IMAGE_URL" "$FULL_IMAGE_PATH"; then
        rm -f "$FULL_IMAGE_PATH"
        echo "❌ Download failed."
        exit 1
    fi
else
    echo "💿 Image already cached locally."
fi

# Verify image integrity
echo "🔍 Verifying image..."
file "$FULL_IMAGE_PATH" | grep -q "QEMU" || {
    echo "❌ Invalid image format."
    exit 1
}

# Create the VM
echo "🔧 Creating VM (ID: $VMID)..."
qm create "$VMID" \
    --name "ubuntu-2204-cloudinit-template" \
    --memory 2048 \
    --cores 1 \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-pci \
    --serial0 socket

# Import disk
echo "💿 Importing disk..."
qm set "$VMID" --scsi0 "$STORAGE_POOL:0,import-from=$FULL_IMAGE_PATH"

# Add cloud-init drive
echo "☁️  Adding cloud-init drive..."
qm set "$VMID" --ide2 "$STORAGE_POOL:cloudinit"

# Set boot order and other options
echo "👢 Configuring boot and hardware..."
qm set "$VMID" --boot order=scsi0 --agent 1

# Convert to template
echo "✨ Converting to template..."
qm template "$VMID"

echo "✅ Template creation complete."
REMOTE_EOF
then
    log_error "Template creation failed on remote server."
    exit 1
fi

log_info "🎉 Success! Proxmox template setup is complete."
log_info "Template ID: $VMID"

# Automatically update terraform.tfvars with the template name
TEMPLATE_NAME="ubuntu-2204-cloudinit-template"
if [ -f "$TFVARS_FILE" ]; then
    log_info "Ensuring vm_template is set in terraform.tfvars..."
    if grep -q "^[[:space:]]*vm_template" "$TFVARS_FILE"; then
        sed -i.bak "s/^[[:space:]]*vm_template.*/vm_template = \"$TEMPLATE_NAME\"/" "$TFVARS_FILE"
        rm -f "${TFVARS_FILE}.bak"
    else
        echo "" >> "$TFVARS_FILE"
        echo "vm_template = \"$TEMPLATE_NAME\"" >> "$TFVARS_FILE"
    fi
fi
