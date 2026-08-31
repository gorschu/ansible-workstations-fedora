variable "state_encryption_passphrase" {
  description = "Passphrase used by OpenTofu to encrypt state and saved plans."
  type        = string
  sensitive   = true
}

variable "scaleway_organization_id" {
  description = "Scaleway organization containing the workstation backup project."
  type        = string
  default     = "9177a15b-9733-4143-a83c-ec6605bcd323"
}

variable "scaleway_state_project_id" {
  description = "Built-in default project containing the shared OpenTofu state bucket."
  type        = string
  default     = "9177a15b-9733-4143-a83c-ec6605bcd323"
}

variable "scaleway_region" {
  description = "Scaleway region for workstation backup resources and shared state."
  type        = string
  default     = "fr-par"
}

variable "workstation_hosts" {
  description = "Hosts receiving independently revocable Restic API keys."
  type        = set(string)
  default = [
    "apollo",
    "artemis",
    "hephaestus",
  ]
}
