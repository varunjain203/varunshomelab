# scripts/setup.sh
#!/bin/bash

set -e

echo "Setting up Kubernetes Home Lab..."
bash create_qemu_template.sh

# Check if required tools are installed
command -v terraform >/dev/null 2>&1 || { echo "Terraform is required but not installed. Aborting." >&2; exit 1; }
command -v ansible >/dev/null 2>&1 || { echo "Ansible is required but not installed. Aborting." >&2; exit 1; }

# Create terraform.tfvars if it doesn't exist
if [ ! -f /Users/varun/Documents/git/varunshomelab/terraform/terraform.tfvars ]; then
    echo "Please create terraform/terraform.tfvars from terraform.tfvars.example"
    exit 1
fi

# Initialize and apply Terraform
echo "Initializing Terraform..."
cd terraform
terraform init

echo "Planning Terraform deployment..."
terraform plan

echo "Applying Terraform configuration..."
terraform apply -auto-approve

echo "Waiting for VMs to be ready..."
sleep 1

# Run Ansible playbook
echo "Running Ansible playbook..."
cd ../ansible

# Setup the Kubernetes infrastructure
echo "Setting up Kubernetes cluster..."
ansible-playbook -i inventory/hosts.yml site.yml

echo "Kubernetes cluster setup complete!"
echo ""
echo "Load Balancer: http://$(terraform output -raw lb_ip)"
echo ""
echo "Access your cluster with: kubectl --kubeconfig ~/.kube/config get nodes"
