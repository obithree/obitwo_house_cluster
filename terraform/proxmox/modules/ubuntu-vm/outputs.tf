output "vm_id" {
  description = "Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "Proxmox VM name."
  value       = proxmox_virtual_environment_vm.this.name
}

output "mac_addresses" {
  description = "VM network adapter MAC addresses."
  value       = proxmox_virtual_environment_vm.this.mac_addresses
}

output "power_state" {
  description = "Terraform-managed desired power state."
  value       = var.started ? "started" : "stopped"
}
