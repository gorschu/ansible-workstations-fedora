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

variable "scaleway_project_id" {
  description = "Dedicated workstation-backups project owned by the sibling project root."
  type        = string
  default     = "ac990a0c-ae62-435e-9e25-e5b332edda2a"
}

variable "scaleway_region" {
  description = "Scaleway region containing the workstation backup bucket."
  type        = string
  default     = "nl-ams"
}
