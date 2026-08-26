variable "node_name" {
  description = "Proxmox node that hosts the VM."
  type        = string
}

variable "vm_id" {
  description = "Unique Proxmox VM identifier."
  type        = number

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999
    error_message = "vm_id must be a valid Proxmox VM ID."
  }
}

variable "name" {
  description = "Proxmox VM name."
  type        = string
}

variable "description" {
  description = "VM description shown in Proxmox."
  type        = string
  default     = "Ubuntu VM managed by Terraform"
}

variable "tags" {
  description = "Proxmox metadata tags. Keep them sorted to avoid perpetual diffs."
  type        = list(string)
  default     = ["terraform", "ubuntu"]
}

variable "cpu_cores" {
  description = "Number of vCPU cores assigned to the VM."
  type        = number

  validation {
    condition     = var.cpu_cores >= 1
    error_message = "cpu_cores must be at least 1."
  }
}

variable "memory_mb" {
  description = "Fixed VM memory in MiB."
  type        = number

  validation {
    condition     = var.memory_mb >= 512
    error_message = "memory_mb must be at least 512 MiB."
  }
}

variable "disk_size_gb" {
  description = "OS disk size in GiB."
  type        = number
  default     = 100
}

variable "datastore_id" {
  description = "Proxmox datastore used for the EFI and OS disks."
  type        = string
  default     = "local-lvm"
}

variable "install_iso_file_id" {
  description = "Proxmox volume ID of the Ubuntu installer ISO."
  type        = string
}

variable "attach_install_iso" {
  description = "Attach the Ubuntu installer ISO. Set false after installation."
  type        = bool
  default     = true
}

variable "boot_from_iso" {
  description = "Place the installer ISO first in the boot order."
  type        = bool
  default     = true
}

variable "qemu_guest_agent_enabled" {
  description = "Enable after qemu-guest-agent is installed and running in Ubuntu."
  type        = bool
  default     = false
}

variable "network_bridge" {
  description = "Proxmox Linux bridge connected to the VM."
  type        = string
  default     = "vmbr0"
}

variable "network_mtu" {
  description = "VirtIO interface MTU."
  type        = number
  default     = 1500
}

variable "startup_order" {
  description = "Proxmox autostart order."
  type        = number
  default     = 1
}

variable "started" {
  description = "Desired VM power state."
  type        = bool
  default     = false
}

variable "on_boot" {
  description = "Start the VM when Proxmox boots."
  type        = bool
  default     = false
}

variable "protection" {
  description = "Protect the VM and disks from deletion."
  type        = bool
  default     = false
}
