#!/bin/bash
# scripts/destroy.sh

set -e

# Ensure we are executing from the root of the repository
cd "$(dirname "$0")/.."

echo "Destroying Kubernetes Home Lab..."

cd terraform
terraform destroy -auto-approve

echo "Lab environment destroyed!"
