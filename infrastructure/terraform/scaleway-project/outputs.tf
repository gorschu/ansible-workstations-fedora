output "scaleway_project_id" {
  description = "ID of the dedicated workstation backup project."
  value       = scaleway_account_project.workstation_backups.id
}

output "management_access_key" {
  description = "Access key for the workstation Object Storage management identity."
  value       = scaleway_iam_api_key.opentofu_management.access_key
  sensitive   = true
}

output "management_secret_key" {
  description = "Secret key for the workstation Object Storage management identity."
  value       = scaleway_iam_api_key.opentofu_management.secret_key
  sensitive   = true
}

output "state_backend_access_key" {
  description = "Access key for this repository's state-only identity."
  value       = scaleway_iam_api_key.state_backend.access_key
  sensitive   = true
}

output "state_backend_secret_key" {
  description = "Secret key for this repository's state-only identity."
  value       = scaleway_iam_api_key.state_backend.secret_key
  sensitive   = true
}

output "restic_credentials" {
  description = "Per-host API keys for Restic; transfer directly into Ansible Vault."
  sensitive   = true
  value = {
    for host, key in scaleway_iam_api_key.restic : host => {
      access_key = key.access_key
      secret_key = key.secret_key
    }
  }
}
