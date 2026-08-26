provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # Credentials are intentionally omitted. Use one of the provider-supported
  # environment variable combinations, preferably PROXMOX_VE_API_TOKEN.
}
