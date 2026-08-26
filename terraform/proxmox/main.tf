data "proxmox_file" "ubuntu_server_iso" {
  content_type = "iso"
  datastore_id = "local"
  file_name    = "ubuntu-24.04.4-live-server-amd64.iso"
  node_name    = "proxmox01"
}

module "k3s_master01" {
  source = "./modules/ubuntu-vm"

  node_name   = "proxmox01"
  vm_id       = 200
  name        = "k3s-master01"
  description = "k3s control-plane VM managed by Terraform"
  tags        = ["control-plane", "k3s", "terraform", "ubuntu"]

  cpu_cores    = 6
  memory_mb    = 24576
  disk_size_gb = 200

  install_iso_file_id      = data.proxmox_file.ubuntu_server_iso.id
  attach_install_iso       = false
  boot_from_iso            = false
  qemu_guest_agent_enabled = false

  started    = true
  on_boot    = false
  protection = false
}
