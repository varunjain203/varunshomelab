# terraform/main.tf
terraform {
  required_version = ">= 0.13.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.PROXMOX_URL
  pm_api_token_id = var.PROXMOX_USER
  pm_api_token_secret = var.PROXMOX_TOKEN_PASSWORD
  pm_tls_insecure = true
}

# Variables
variable "PROXMOX_URL" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://your-proxmox-server:8006/api2/json"
}

variable "PROXMOX_USER" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"
}

variable "PROXMOX_TOKEN_PASSWORD" {
  description = "Proxmox token"
  type        = string
  sensitive   = true
}

variable "PUBLIC_SSH_KEY" {
  description = "SSH public key for VM access"
  type        = string
}

variable "vm_template" {
  description = "VM template name"
  type        = string
  default     = "ubuntu-22.04-template"
}

variable "target_node" {
  description = "Proxmox node name"
  type        = string
  default     = "catan"
}

# Master nodes
resource "proxmox_vm_qemu" "k8s_master" {
  count       = 1
  name        = "k8s-master-${count.index + 1}"
  target_node = var.target_node
  clone       = var.vm_template
  full_clone  = true
  
  # VM Configuration
  cpu {
    cores   = 2
    sockets = 1
  }
  memory   = 2048
  agent    = 1
  vmid     = "10${count.index +1}"
  onboot   = true
  
  # Display
  vga {
    type = "std"
    memory = 16
  }

  # Network
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr1"
  }
  scsihw = "virtio-scsi-single"
  # Disk
  disks {
        ide {
            ide2 {
                cloudinit {
                    storage = "local-lvm"
                }
            }
        }
        scsi {
            scsi0 {
                disk {
                    size            = 20
                    cache           = "writeback"
                    storage         = "local-lvm"
                    #storage_type    = "rbd"
                    #iothread        = true
                    #discard         = true
                    replicate       = false
                }
            }
        }
    }
  
  boot = "order=scsi0"

  
  # Cloud-init
  os_type                 = "cloud-init"
  ciuser                  = "ubuntu"
  cipassword              = "ubuntu"
  sshkeys                 = var.PUBLIC_SSH_KEY
  ipconfig0               = "ip=192.168.1.${120 + count.index}/24,gw=192.168.1.1"
  nameserver              = "1.1.1.1"
  startup                 = ""
  automatic_reboot        = "true"
}


# Worker nodes
resource "proxmox_vm_qemu" "k8s_worker" {
  count       = 3
  name        = "k8s-worker-${count.index + 1}"
  target_node = var.target_node
  clone       = var.vm_template
  full_clone  = true
  
  # VM Configuration
  cpu {
    cores   = 2
    sockets = 1
  }
  memory   = 4096
  agent    = 1
  vmid     = "20${count.index +1}"
  onboot   = true
  
  # Display
  vga {
    type = "std"
    memory = 16
  }

  # Network
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr1"
  }
  scsihw = "virtio-scsi-single"
  # Disk
  disks {
        ide {
            ide2 {
                cloudinit {
                    storage = "local-lvm"
                }
            }
        }
        scsi {
            scsi0 {
                disk {
                    size            = 20
                    cache           = "writeback"
                    storage         = "local-lvm"
                    #storage_type    = "rbd"
                    #iothread        = true
                    #discard         = true
                    replicate       = false
                }
            }
        }
    }
  
  boot = "order=scsi0"
  
  # Cloud-init
  os_type                 = "cloud-init"
  ciuser                  = "ubuntu"
  cipassword              = "ubuntu"
  sshkeys                 = var.PUBLIC_SSH_KEY
  ipconfig0               = "ip=192.168.1.${130 + count.index}/24,gw=192.168.1.1"
  nameserver              = "1.1.1.1"
  startup                 = ""
  automatic_reboot        = "true"
  
  # Lifecycle
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}

# Load balancer (HAProxy)
resource "proxmox_vm_qemu" "k8s_lb" {

  name        = "k8s-lb"
  target_node = var.target_node
  clone       = var.vm_template
  full_clone  = true
  
  # VM Configuration
  cpu {
    cores   = 2
    sockets = 1
  }
  memory   = 4096
  agent    = 1
  vmid     = "400"
  onboot   = true
    
  # Display
  vga {
    type = "std"
    memory = 16
  }

  # Network
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr1"
  }
  
  scsihw = "virtio-scsi-single"
  # Disk
  disks {
        ide {
            ide2 {
                cloudinit {
                    storage = "local-lvm"
                }
            }
        }
        scsi {
            scsi0 {
                disk {
                    size            = 10
                    cache           = "writeback"
                    storage         = "local-lvm"
                    #storage_type    = "rbd"
                    #iothread        = true
                    #discard         = true
                    replicate       = false
                }
            }
        }
    }
  
  boot = "order=scsi0"
  # Cloud-init
  os_type                 = "cloud-init"
  ciuser                  = "ubuntu"
  cipassword              = "ubuntu"
  sshkeys                 = var.PUBLIC_SSH_KEY
  ipconfig0               = "ip=192.168.1.140/24,gw=192.168.1.1"
  nameserver              = "1.1.1.1"
  startup                 = ""
  automatic_reboot        = "true"
  
  # Lifecycle
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}

# Outputs
output "master_ips" {
  value = [for vm in proxmox_vm_qemu.k8s_master : vm.default_ipv4_address]
}

output "worker_ips" {
  value = [for vm in proxmox_vm_qemu.k8s_worker : vm.default_ipv4_address]
}

output "lb_ip" {
  value = proxmox_vm_qemu.k8s_lb.default_ipv4_address
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    master_ips = [for vm in proxmox_vm_qemu.k8s_master : vm.default_ipv4_address]
    worker_ips = [for vm in proxmox_vm_qemu.k8s_worker : vm.default_ipv4_address]
    lb_ip      = proxmox_vm_qemu.k8s_lb.default_ipv4_address
  })
  filename = "../ansible/inventory/hosts.yml"
}
