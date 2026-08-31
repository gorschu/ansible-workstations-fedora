provider "scaleway" {
  organization_id = var.scaleway_organization_id
  project_id      = var.scaleway_state_project_id
  region          = var.scaleway_region
}
