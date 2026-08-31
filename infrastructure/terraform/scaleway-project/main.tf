locals {
  project_name = "workstation-backups"
}

resource "scaleway_account_project" "workstation_backups" {
  name            = local.project_name
  description     = "One Zone Restic backups for managed workstations"
  organization_id = var.scaleway_organization_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_application" "opentofu_management" {
  name            = "opentofu-workstations-management"
  description     = "Manage workstation backup Object Storage in its dedicated project"
  organization_id = var.scaleway_organization_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "opentofu_management" {
  name            = "opentofu-workstations-management"
  description     = "Manage the declared workstation backup bucket without object mutation"
  organization_id = var.scaleway_organization_id
  application_id  = scaleway_iam_application.opentofu_management.id

  rule {
    project_ids = [scaleway_account_project.workstation_backups.id]
    permission_set_names = [
      "ObjectStorageBucketPolicyFullAccess",
      "ObjectStorageBucketsRead",
      "ObjectStorageBucketsWrite",
      # The provider lists objects while refreshing a bucket even though
      # force_destroy is disabled. It never receives object write or delete.
      "ObjectStorageObjectsRead",
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_api_key" "opentofu_management" {
  application_id     = scaleway_iam_application.opentofu_management.id
  default_project_id = scaleway_account_project.workstation_backups.id
  description        = "OpenTofu management for workstation backup Object Storage"

  depends_on = [scaleway_iam_policy.opentofu_management]

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_application" "restic" {
  name            = "workstations-restic-backup"
  description     = "Restic object access for managed workstations"
  organization_id = var.scaleway_organization_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "restic" {
  name            = "workstations-restic-backup"
  description     = "Read, write, and prune Restic objects in the workstation backup project"
  organization_id = var.scaleway_organization_id
  application_id  = scaleway_iam_application.restic.id

  rule {
    project_ids = [scaleway_account_project.workstation_backups.id]
    permission_set_names = [
      "ObjectStorageBucketsRead",
      "ObjectStorageObjectsDelete",
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_api_key" "restic" {
  for_each = var.workstation_hosts

  application_id     = scaleway_iam_application.restic.id
  default_project_id = scaleway_account_project.workstation_backups.id
  description        = "Restic backup access for ${each.key}"

  depends_on = [scaleway_iam_policy.restic]

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_application" "state_backend" {
  name            = "opentofu-ansible-workstations-state"
  description     = "Separately revocable state backend identity for the workstation repository"
  organization_id = var.scaleway_organization_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "state_backend" {
  name            = "opentofu-ansible-workstations-state"
  description     = "Read and write encrypted OpenTofu state and native lock files"
  organization_id = var.scaleway_organization_id
  application_id  = scaleway_iam_application.state_backend.id

  rule {
    project_ids = [var.scaleway_state_project_id]
    permission_set_names = [
      "ObjectStorageBucketsRead",
      "ObjectStorageObjectsDelete",
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_api_key" "state_backend" {
  application_id     = scaleway_iam_application.state_backend.id
  default_project_id = var.scaleway_state_project_id
  description        = "OpenTofu S3 backend access for ansible-workstations-fedora"

  depends_on = [scaleway_iam_policy.state_backend]

  lifecycle {
    prevent_destroy = true
  }
}
