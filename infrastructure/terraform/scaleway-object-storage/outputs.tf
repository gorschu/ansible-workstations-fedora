output "scaleway_project_id" {
  description = "ID of the dedicated workstation backup project."
  value       = var.scaleway_project_id
}

output "scaleway_bucket_name" {
  description = "Empty bucket in which Restic initializes per-host repositories."
  value       = scaleway_object_bucket.workstations.name
}
