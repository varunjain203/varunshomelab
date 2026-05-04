# README.md
# Kubernetes Home Lab with Proxmox, Terraform, and Ansible

This project sets up a complete Kubernetes cluster in a Proxmox home lab environment using Infrastructure as Code principles.

## Architecture

- **3 Master nodes** (HA control plane)
- **3 Worker nodes**
- **1 Load balancer** (HAProxy)
- **Flannel CNI** for pod networking
- **Containerd** as container runtime

## Prerequisites

1. **Proxmox VE** server with:
   - Ubuntu 22.04 template (cloud-init enabled)
   - Sufficient resources (7 VMs total)
   - Network bridge configured

2. **Local machine** with:
   - Terraform >= 1.0
   - Ansible >= 2.9
   - SSH key pair generated

## Setup Instructions

### 1. Run the Setup Wizard

The easiest way to deploy the lab is to run the automated setup script. It will check your environment, automatically generate the configuration file, build the Proxmox template, and deploy the entire cluster.

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The script will create the Ubuntu template and proceed with full cluster deployment.

### 2. Configure Variables

Copy and edit the Terraform variables:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform.tfvars` with your Proxmox details:
```
PROXMOX_URL = "https://your-proxmox-server:8006/api2/json"
PROXMOX_USER = "terraform@pve!provider"
PROXMOX_TOKEN = "put-api-token-here"
PUBLIC_SSH_KEY = "put-contents-of-id_rsa.pub"
target_node = "name-of-the-proxmox-node"
```

### 3. Deploy the Lab

Run the setup script:

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

This will:
1. Create VMs in Proxmox using Terraform
2. Generate Ansible inventory
3. Configure all nodes with Ansible
4. Set up the Kubernetes cluster

### 4. Access the Cluster

The kubeconfig will be available on the first master node:

```bash
ssh ubuntu@192.168.1.100
kubectl get nodes
```

Or copy it to your local machine:

```bash
scp ubuntu@192.168.1.100:~/.kube/config ~/.kube/config-homelab
export KUBECONFIG=~/.kube/config-homelab
kubectl get nodes
```

# Network Configuration

- **Load Balancer**: 192.168.1.140
- **Masters**: 192.168.1.120-102
- **Workers**: 192.168.1.130-112
- **Pod Network**: 10.244.0.0/16



## Monitoring

HAProxy stats are available at: http://192.168.1.140:8080/stats

## Cleanup

To destroy the entire lab:

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```



## Offline Operation

Once fully set up, the lab can operate completely offline:

1. **VM Templates**: Created from local cloud images
2. **Container Images**: Pulled from public registries
3. **System Packages**: Installed from standard repositories
4. **Kubernetes Components**: Downloaded from standard sources

## Customization

### Scaling

Modify the `count` parameters in `terraform/main.tf` to adjust the number of nodes.

### VM Resources

Adjust CPU, memory, and disk in the Terraform configuration as needed.

### Network Settings

Update IP ranges and network configuration in the Terraform variables.

## Troubleshooting

1. **VM Creation Issues**: Check Proxmox template exists and has cloud-init
2. **SSH Connection Issues**: Verify SSH key is correct and accessible
3. **Kubernetes Join Issues**: Check firewall rules and network connectivity
4. **Pod Network Issues**: Verify Flannel CNI installation

## Components

- **Terraform**: Infrastructure provisioning
- **Ansible**: Configuration management
- **Kubernetes**: Container orchestration
- **Containerd**: Container runtime
- **Flannel**: Pod networking
- **HAProxy**: Load balancing

## Architecture Benefits

- **High Availability**: Multiple master nodes for control plane redundancy
- **Scalability**: Easy to add or remove worker nodes
- **Infrastructure as Code**: Reproducible deployments with Terraform and Ansible
- **Container Orchestration**: Full Kubernetes feature set for workload management
