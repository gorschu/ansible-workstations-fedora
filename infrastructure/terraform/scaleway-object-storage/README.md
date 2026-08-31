# Scaleway Workstation Object Storage

This root owns the private `gorschu-backup-workstations` bucket in `nl-ams`.
It was created empty; Restic initializes the `apollo`, `artemis`, and
`hephaestus` prefixes during each host's first backup.

Standard One Zone is an object storage class, not a bucket type. The Ansible
Restic profile therefore supplies `s3.storage-class=ONEZONE_IA` on every Restic
command that writes repository objects. After each first backup, verify the
actual storage class through the S3 API. The bucket has no versioning or
lifecycle transition because Restic owns retention and prune behavior.

Load this root's independent state passphrase, the workstation management
credential, and this repository's state credential from SOPS:

```shell
export TF_VAR_state_encryption_passphrase="$(
  sops --decrypt --extract '["opentofu"]["statePassphrase"]' values-secret.yaml
)"
export SCW_ACCESS_KEY="$(
  sops --decrypt --extract '["credentials"]["management"]["accessKeyId"]' \
    ../scaleway-project/values-secret.yaml
)"
export SCW_SECRET_KEY="$(
  sops --decrypt --extract '["credentials"]["management"]["secretAccessKey"]' \
    ../scaleway-project/values-secret.yaml
)"
export AWS_ACCESS_KEY_ID="$(
  sops --decrypt --extract '["backend"]["scaleway"]["accessKeyId"]' \
    ../scaleway-project/values-secret.yaml
)"
export AWS_SECRET_ACCESS_KEY="$(
  sops --decrypt --extract '["backend"]["scaleway"]["secretAccessKey"]' \
    ../scaleway-project/values-secret.yaml
)"

tofu init
tofu plan -out=change.tfplan
tofu apply change.tfplan
tofu plan -detailed-exitcode
```

All data-bearing resources use `prevent_destroy`; the bucket also has
`force_destroy = false`.
