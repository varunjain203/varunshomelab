#!/bin/bash

# scripts/setup.sh - Main setup orchestrator for Kubernetes home lab

set -e

# Ensure we are executing from the root of the repository
cd "$(dirname "$0")/.."

# --- Color output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

# --- Main Setup ---
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Setting up Kubernetes Home Lab (Proxmox + Terraform)        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if required tools are installed
log_info "Checking for required tools..."
command -v terraform >/dev/null 2>&1 || { 
    log_error "Terraform is required but not installed. Aborting." 
    exit 1 
}
log_success "Terraform found"

command -v ansible >/dev/null 2>&1 || { 
    log_error "Ansible is required but not installed. Aborting." 
    exit 1 
}
log_success "Ansible found"

# Check if QEMU template creation script exists
if [ ! -f "scripts/create_qemu_template.sh" ]; then
    log_error "Template creation script not found at scripts/create_qemu_template.sh"
    exit 1
fi

# Conditional template creation
TEMPLATE_VMID="${VMID:-9000}"
log_info "Checking if QEMU template (ID: $TEMPLATE_VMID) already exists..."

# Try to read terraform vars to get Proxmox connection details
TERRAFORM_VARS_FILE="terraform/terraform.tfvars"

# Check if terraform.tfvars exists
if [ ! -f "$TERRAFORM_VARS_FILE" ]; then
    log_error "Please create terraform/$TERRAFORM_VARS_FILE from terraform/terraform.tfvars.example"
    exit 1
fi

# Attempt to get Proxmox host from terraform.tfvars (optional optimization)
if grep -q "PROXMOX_URL" "$TERRAFORM_VARS_FILE"; then
    log_success "Terraform configuration found"
else
    log_warn "Could not verify Proxmox URL in terraform.tfvars"
fi

# Run template creation if not already present
# The script itself will check and skip if the template exists
log_info "Running QEMU template setup (will skip if already exists)..."
if bash scripts/create_qemu_template.sh; then
    log_success "QEMU template setup completed"
else
    log_warn "Template setup returned non-zero status. Review the output above."
    # Continue anyway as template might already exist
fi

echo ""

# Initialize and apply Terraform
log_info "Initializing Terraform..."
cd terraform

terraform init
log_success "Terraform initialized"

log_info "Planning Terraform deployment..."
terraform plan -out=tfplan

log_info "Applying Terraform configuration..."
terraform apply tfplan

log_success "Terraform deployment completed"

log_info "Waiting for VMs to be ready (10 seconds)..."
sleep 10

# Run Ansible playbook
echo ""
log_info "Configuring infrastructure with Ansible..."
cd ../ansible

if [ ! -f "inventory/hosts.yml" ]; then
    log_error "Ansible inventory not found at inventory/hosts.yml"
    cd ..
    exit 1
fi

log_info "Executing Kubernetes setup playbook..."
ansible-playbook -i inventory/hosts.yml site.yml

log_success "Ansible playbook execution completed"

# Summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               Kubernetes Cluster Setup Complete!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get Load Balancer IP
cd ../terraform
LB_IP=$(terraform output -raw lb_ip 2>/dev/null || echo "Unable to retrieve")
log_info "Load Balancer: http://$LB_IP"
log_info "HAProxy Stats: http://$LB_IP:8080/stats"
echo ""
log_info "Access your cluster with:"
echo "  kubectl --kubeconfig ~/.kube/config get nodes"
echo ""
log_warn "Next steps:"
echo "  1. Copy kubeconfig from master node: scp ubuntu@<master-ip>:~/.kube/config ~/.kube/config-homelab"
echo "  2. Export: export KUBECONFIG=~/.kube/config-homelab"
echo "  3. Verify: kubectl get nodes"
echo ""
