locals {
  bucket_name = "gorschu-backup-workstations"
}

resource "scaleway_object_bucket" "workstations" {
  name          = local.bucket_name
  project_id    = var.scaleway_project_id
  region        = var.scaleway_region
  force_destroy = false

  versioning {
    enabled = false
  }

  lifecycle {
    prevent_destroy = true
    # The dedicated ACL resource below is the sole declarative owner of the
    # deprecated provider-level ACL attribute.
    ignore_changes = [acl]
  }
}

resource "scaleway_object_bucket_acl" "workstations_private" {
  bucket     = scaleway_object_bucket.workstations.name
  acl        = "private"
  project_id = var.scaleway_project_id
  region     = var.scaleway_region
}

resource "scaleway_object_bucket_server_side_encryption_configuration" "workstations" {
  bucket     = scaleway_object_bucket.workstations.name
  project_id = var.scaleway_project_id
  region     = var.scaleway_region

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
