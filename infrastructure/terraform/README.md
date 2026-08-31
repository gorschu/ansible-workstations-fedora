# OpenTofu Infrastructure

Cloud resources used by this repository are managed declaratively with
OpenTofu. Manual bootstrap credentials may issue the permanent identities, but
all durable projects, IAM policies, API keys, and buckets belong in these
roots.

Each child directory is an independent root with its own encrypted state:

- `scaleway-project`: the `workstation-backups` project, permanent
  project-management identity, per-host Restic credentials, and this
  repository's separately revocable state credential;
- `scaleway-object-storage`: the private `gorschu-backup-workstations` bucket
  used for independent per-workstation Restic repositories.

The shared state bucket is managed centrally by `boxes-pilon`. This repository
uses distinct objects below it:

```text
states/ansible-workstations-fedora/scaleway-project/scaleway.tfstate
states/ansible-workstations-fedora/scaleway-object-storage/scaleway.tfstate
```

The Object Storage bucket is not itself a Restic repository. Each workstation
initializes its own prefix automatically on its first Restic run. The legacy
Backblaze B2 repositories were deliberately not migrated; their bucket and
shared application key were retired after Apollo completed a backup and a
controlled restore from Scaleway.
