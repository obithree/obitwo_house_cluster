variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, without /api2/json."
  type        = string
  default     = "https://proxmox01.obitwo.arpa:8006/"

  validation {
    condition     = startswith(var.proxmox_endpoint, "https://")
    error_message = "proxmox_endpoint must use HTTPS."
  }
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the current Proxmox self-signed certificate."
  type        = bool
  default     = true
}
