terraform {
  required_version = "~> 1.12.0"

  backend "s3" {
    bucket                      = "gorschu-opentofu-state"
    key                         = "states/ansible-workstations-fedora/scaleway-project/scaleway.tfstate"
    region                      = "fr-par"
    use_lockfile                = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
  }

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.80"
    }
  }

  encryption {
    key_provider "pbkdf2" "state" {
      passphrase               = var.state_encryption_passphrase
      encrypted_metadata_alias = "ansible-workstations-fedora-scaleway-project"
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}
