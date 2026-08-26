resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  tags        = var.tags

  node_name = var.node_name
  vm_id     = var.vm_id

  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "ja"

  started    = var.started
  on_boot    = var.on_boot
  protection = var.protection

  # Enable only after qemu-guest-agent is installed and running in Ubuntu.
  agent {
    enabled = var.qemu_guest_agent_enabled
    trim    = var.qemu_guest_agent_enabled
    type    = "virtio"
  }

  startup {
    order      = tostring(var.startup_order)
    up_delay   = "60"
    down_delay = "120"
  }

  cpu {
    sockets = 1
    cores   = var.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = var.memory_mb
    floating  = 0
  }

  efi_disk {
    datastore_id      = var.datastore_id
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    file_format  = "raw"
    cache        = "none"
    discard      = "on"
    iothread     = true
    ssd          = true
    backup       = true
    replicate    = false
  }

  cdrom {
    file_id   = var.attach_install_iso ? var.install_iso_file_id : "none"
    interface = "ide2"
  }

  boot_order = var.boot_from_iso ? ["ide2", "scsi0"] : ["scsi0"]

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = false
    mtu      = var.network_mtu
  }

  operating_system {
    type = "l26"
  }

  tablet_device                        = true
  stop_on_destroy                      = true
  purge_on_destroy                     = false
  delete_unreferenced_disks_on_destroy = false

  timeout_create = 1800

  lifecycle {
    precondition {
      condition     = !var.boot_from_iso || var.attach_install_iso
      error_message = "boot_from_iso cannot be true when attach_install_iso is false."
    }
  }
}
