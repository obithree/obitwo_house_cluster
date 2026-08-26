output "k3s_master01" {
  description = "Identifiers and network information for k3s-master01."
  value = {
    vm_id         = module.k3s_master01.vm_id
    name          = module.k3s_master01.name
    mac_addresses = module.k3s_master01.mac_addresses
    power_state   = module.k3s_master01.power_state
  }
}
