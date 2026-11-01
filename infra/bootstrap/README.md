# infra/bootstrap

One-time Terraform for the remote state bucket, the GitHub OIDC trust and the deploy roles.
Uses local state, because it creates the place where state will live. Run it once with your
own admin credentials; after that the pipeline takes over.

## What it creates (14 resources)

- `aws_s3_bucket.state`: `lsp-tfstate-<account id>`, with `prevent_destroy`
- `aws_s3_bucket_versioning.state`: versioning on
- `aws_s3_bucket_lifecycle_configuration.state`: expires old state versions (keeps the newest 10, drops the rest after 90 days) and cleans up delete markers
- `aws_s3_bucket_server_side_encryption_configuration.state`: AES256 with bucket key
- `aws_s3_bucket_public_access_block.state`: all four blocks on
- `aws_s3_bucket_ownership_controls.state`: `BucketOwnerEnforced`
- `aws_s3_bucket_policy.state`: denies any request not using TLS
- `aws_iam_openid_connect_provider.github`: trusts tokens from GitHub Actions
- `aws_iam_policy.boundary`: `lsp-workload-boundary`, the ceiling for every role the pipeline creates
- `aws_iam_role.deploy`: `lsp-github-deploy`, assumable only from `main` of the repo
- `aws_iam_role_policy.deploy`: `lsp-github-deploy-policy`, manages platform services and `lsp-*` roles only with the boundary
- `aws_iam_role.plan`: `lsp-github-plan`, assumable only from pull requests of the repo
- `aws_iam_role_policy_attachment.plan_read_only`: AWS `ReadOnlyAccess`
- `aws_iam_role_policy.plan_state`: read state, write `*.tflock` lock files

Account `531640468039`, region `us-east-1`. The repo is `Shubhrajit1pallob/ai-ordering-ads-platform`.

## Steps

1. Point at your admin profile and confirm the account:
   ```sh
   export AWS_PROFILE=ai-platform
   aws sts get-caller-identity
   ```
   Check: `Account` is `531640468039`.
2. Initialise: `cd infra/bootstrap && terraform init`.
   Check: "Terraform has been successfully initialized".
3. Plan: `terraform plan -out=bootstrap.tfplan`.
   Check: `Plan: 14 to add, 0 to change, 0 to destroy.` Anything else, stop and ask.
4. Apply: `terraform apply bootstrap.tfplan`.
   Check: `Apply complete! Resources: 14 added, 0 changed, 0 destroyed.` and the five outputs.
5. Back up `terraform.tfstate` (in this folder) somewhere safe outside git. It is the only
   record of these resources.
6. Initialise the dev environment against the new bucket:
   ```sh
   cd ../envs/dev && terraform init
   ```
   Check: `Successfully configured the backend "s3"`.
7. If the state file is lost, rebuild it with `terraform import` (run `terraform init` in this
   folder first). Import IDs, with `<acct>` = `531640468039`:

   | Resource | Import ID |
   | --- | --- |
   | `aws_s3_bucket.state` | `lsp-tfstate-<acct>` |
   | `aws_s3_bucket_versioning.state` | `lsp-tfstate-<acct>` |
   | `aws_s3_bucket_lifecycle_configuration.state` | `lsp-tfstate-<acct>` |
   | `aws_s3_bucket_server_side_encryption_configuration.state` | `lsp-tfstate-<acct>` |
   | `aws_s3_bucket_public_access_block.state` | `lsp-tfstate-<acct>` |
   | `aws_s3_bucket_ownership_controls.state` | `lsp-tfstate-<acct>` |
   | `aws_s3_bucket_policy.state` | `lsp-tfstate-<acct>` |
   | `aws_iam_openid_connect_provider.github` | `arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com` |
   | `aws_iam_policy.boundary` | `arn:aws:iam::<acct>:policy/lsp-workload-boundary` |
   | `aws_iam_role.deploy` | `lsp-github-deploy` |
   | `aws_iam_role_policy.deploy` | `lsp-github-deploy:lsp-github-deploy-policy` |
   | `aws_iam_role.plan` | `lsp-github-plan` |
   | `aws_iam_role_policy_attachment.plan_read_only` | `lsp-github-plan/arn:aws:iam::aws:policy/ReadOnlyAccess` |
   | `aws_iam_role_policy.plan_state` | `lsp-github-plan:lsp-github-plan-state` |
