# Scaleway Workstation Backup Project

This root owns the `workstation-backups` project and three independent identity
boundaries:

- the permanent Object Storage management credential used by the sibling
  bucket root;
- one Restic API key per workstation under a shared object-only policy;
- a separately revocable credential for this repository's remote state.

Scaleway IAM scopes Object Storage permissions to a project rather than an
object prefix. Per-host keys still permit individual revocation, while Restic
repository passwords provide independent repository encryption. OpenTofu state
is encrypted before upload with this root's own passphrase.

## One-time bootstrap

This root creates its own backend credential, so its first apply necessarily
uses encrypted local state. Use the central organization management credential
from `boxes-pilon` as the provider issuer; do not copy it here.

```shell
export TF_VAR_state_encryption_passphrase="$(
  sops --decrypt --extract '["opentofu"]["statePassphrase"]' values-secret.yaml
)"
export SCW_ACCESS_KEY="$(
  sops --decrypt --extract '["credentials"]["default"]["accessKeyId"]' \
    ../../../../boxes-pilon/infrastructure/terraform/scaleway-management/values-secret.yaml
)"
export SCW_SECRET_KEY="$(
  sops --decrypt --extract '["credentials"]["default"]["secretAccessKey"]' \
    ../../../../boxes-pilon/infrastructure/terraform/scaleway-management/values-secret.yaml
)"

tofu init -backend=false
tofu plan -out=bootstrap.tfplan
tofu apply bootstrap.tfplan
```

Transfer the generated management and state keys directly into this root's
SOPS file without displaying them. Transfer per-host Restic keys directly into
Ansible Vault and generate a fresh repository password for every host. Then
load the new state credential as `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` and migrate the encrypted local state:

```shell
tofu init -migrate-state
tofu plan -detailed-exitcode
```

After migration, normal plans use the same state variables plus the central
`SCW_*` provider credential. A clean plan must exit with status 0.
