---
task: P1-T1
title: Terraform bootstrap and secure deploy access
status: assigned
assigned_to: worker
date: 2026-10-28
approved_by: user
branch: task1
---

# P1-T1: Terraform bootstrap and secure deploy access

## Goal

Write (do not run) the one-time Terraform that creates the remote state bucket, the GitHub OIDC provider, a permissions boundary, and two GitHub roles (deploy and plan), plus the dev environment's backend and provider wiring. The user reviews it and runs it.

## Rules for this task (read first)

- **You write files only.** The user does all version control and runs every command with real effects.
- **Git:** the user has checked out branch `task1`; work on it as-is. Read-only git only (`git status`, `git diff`). **No** `git add`, `commit`, `branch`, `checkout`, `stash`, `merge`, remotes or push. Leave everything uncommitted.
- **Terraform:** only `terraform fmt`, `terraform init -backend=false` and `terraform validate`. **No** `plan`, `apply`, `import`, `destroy`, or `init` with a backend.
- **AWS:** no AWS calls of any kind (no CLI, no SDK, no MCP).
- **Tools:** don't install anything. If something is missing, report it. tflint is dropped from this task (not in Homebrew core).

## Context

- Account `531640468039`, region `us-east-1`, env `dev` only. GitHub repo: `Shubhrajit1pallob/ai-ordering-ads-platform` (private; the user creates it).
- Terraform 1.12.0 (`.terraform-version`). Naming prefix `lsp-`; default tags `project = "local-store-platform"`, `env`, `managed_by = "terraform"`.
- The user applies the bootstrap with their own admin credentials (`AWS_PROFILE=ai-platform`). Don't hardcode a profile in code.
- Why the boundary: a deploy role allowed to create `lsp-*` roles could otherwise create one with AdministratorAccess and escalate. Every role the pipeline creates must carry `lsp-workload-boundary`, and the deploy role must not be able to remove or change it.

## Steps

### 1. `infra/bootstrap/` (local state; no `backend` block)

Files: `versions.tf`, `providers.tf`, `variables.tf`, `main.tf` (or split as `state.tf`, `oidc.tf`, `boundary.tf`, `roles.tf`), `outputs.tf`, `README.md`.

- `versions.tf`: `required_version = "~> 1.12.0"`; `hashicorp/aws` pinned to the current major (`~> 6.0` unless a newer major is current; the lock file records the exact version).
- `providers.tf`: `region = var.region`; `default_tags` with `project`, `env = "bootstrap"`, `managed_by`.
- `variables.tf`: `region` (default `us-east-1`), `github_owner` (default `Shubhrajit1pallob`), `github_repo` (default `ai-ordering-ads-platform`). Use `data "aws_caller_identity"` for the account ID; don't hardcode it.

**State bucket** `lsp-tfstate-<account_id>`:
- `aws_s3_bucket` with `lifecycle { prevent_destroy = true }`.
- Versioning enabled; SSE (`AES256`, `bucket_key_enabled = true`); public access block (all four `true`); ownership controls `BucketOwnerEnforced`.
- Bucket policy: deny all `s3:*` when `aws:SecureTransport = false`.

**GitHub OIDC provider**: `aws_iam_openid_connect_provider`, url `https://token.actions.githubusercontent.com`, `client_id_list = ["sts.amazonaws.com"]` (no thumbprint needed on current provider versions; add one only if `validate` requires it).

**Permissions boundary** `aws_iam_policy` named `lsp-workload-boundary` (the ceiling for every workload role the pipeline creates later):
- Allow the runtime services the platform uses: `lambda`, `dynamodb`, `s3`, `states`, `events`, `scheduler`, `textract`, `bedrock`, `cognito-idp`, `sqs`, `sns`, `ses`, `logs`, `cloudwatch`, `xray`, `secretsmanager`, `athena`, `glue`, `execute-api`, and `kms:Decrypt`/`kms:Encrypt`/`kms:GenerateDataKey*`. (`service:*` on `*` is fine here; the workload role's own policy narrows it.)
- Allow `iam:PassRole` on `arn:aws:iam::<acct>:role/lsp-*` only when `iam:PassedToService` is `scheduler.amazonaws.com` or `states.amazonaws.com` (the ads workflows create schedules that pass a role).
- Explicit deny of every other `iam:*` action, plus `organizations:*` and `account:*`.

**Deploy role** `lsp-github-deploy`:
- Trust: federated principal = the OIDC provider; `sts:AssumeRoleWithWebIdentity`; `StringEquals` `token.actions.githubusercontent.com:aud = sts.amazonaws.com` and `token.actions.githubusercontent.com:sub = repo:<owner>/<repo>:ref:refs/heads/main`. `max_session_duration = 3600`.
- Inline or customer-managed policy (name it `lsp-github-deploy-policy`), with statements:
  1. **Platform services management:** `service:*` for `lambda`, `dynamodb`, `s3`, `states`, `events`, `scheduler`, `textract`, `bedrock`, `cognito-idp`, `sqs`, `sns`, `ses`, `logs`, `cloudwatch`, `xray`, `secretsmanager`, `athena`, `glue`, `apigateway`, `cloudfront`, `kms`, `acm`; plus `sts:GetCallerIdentity`.
  2. **Create/modify workload roles only with the boundary:** `iam:CreateRole`, `iam:PutRolePermissionsBoundary`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`, `iam:PutRolePolicy`, `iam:DeleteRolePolicy` on `role/lsp-*`, condition `StringEquals iam:PermissionsBoundary = <boundary ARN>`.
  3. **Other role housekeeping** on `role/lsp-*`: `iam:DeleteRole`, `iam:TagRole`, `iam:UntagRole`, `iam:UpdateRole`, `iam:UpdateRoleDescription`, `iam:UpdateAssumeRolePolicy`.
  4. **Customer-managed policies** on `policy/lsp-*`: `iam:CreatePolicy`, `iam:DeletePolicy`, `iam:CreatePolicyVersion`, `iam:DeletePolicyVersion`, `iam:SetDefaultPolicyVersion`, `iam:TagPolicy`, `iam:UntagPolicy`.
  5. **PassRole** on `role/lsp-*` only, with `iam:PassedToService` limited to `lambda`, `states`, `scheduler`, `events`, `apigateway` and `cognito-idp` (`.amazonaws.com`).
  6. **IAM read:** `iam:Get*`, `iam:List*` on `*`.
  7. **Explicit denies:**
     - `iam:DeleteRolePermissionsBoundary` on `*`.
     - Any IAM write on the boundary policy ARN (`CreatePolicyVersion`, `DeletePolicy`, `DeletePolicyVersion`, `SetDefaultPolicyVersion`, `TagPolicy`, `UntagPolicy`).
     - Any IAM write (and `iam:PassRole`) on `role/lsp-github-*`.
     - `iam:AttachRolePolicy` / `iam:PutRolePermissionsBoundary` where `iam:PolicyARN` or `iam:PermissionsBoundary` is `arn:aws:iam::aws:policy/AdministratorAccess`, `IAMFullAccess` or `PowerUserAccess`.
     - All IAM user/group/access-key/login-profile actions (`iam:*User*`, `iam:*Group*`, `iam:*AccessKey*`, `iam:*LoginProfile*`).
     - OIDC/SAML provider writes (`iam:*OpenIDConnectProvider*` except Get/List, `iam:*SAMLProvider*`).
     - On the state bucket: `s3:DeleteBucket`, `s3:PutBucketPolicy`, `s3:DeleteBucketPolicy`, `s3:PutBucketVersioning`, `s3:PutBucketPublicAccessBlock`, `s3:PutEncryptionConfiguration`.

**Plan role** `lsp-github-plan`:
- Same trust shape, but `sub = repo:<owner>/<repo>:pull_request`. `max_session_duration = 3600`.
- Attach AWS-managed `ReadOnlyAccess`.
- Inline policy: `s3:ListBucket` on the state bucket; `s3:GetObject` on `<bucket>/*`; `s3:PutObject` and `s3:DeleteObject` only on `<bucket>/*.tflock` (for `use_lockfile`).

**Outputs:** `state_bucket_name`, `oidc_provider_arn`, `boundary_policy_arn`, `deploy_role_arn`, `plan_role_arn`.

Write clear but short comments only where the *why* isn't obvious (mainly on the boundary condition and the explicit denies).

### 2. `infra/envs/dev/`

- `versions.tf`: same Terraform and provider pins as the bootstrap.
- `backend.tf`: `backend "s3"` with `bucket = "lsp-tfstate-531640468039"`, `key = "envs/dev/terraform.tfstate"`, `region = "us-east-1"`, `encrypt = true`, `use_lockfile = true` (no DynamoDB lock table).
- `providers.tf`: `region = var.region`, `default_tags` with `project`, `env = var.env`, `managed_by`.
- `variables.tf`: `region` (default `us-east-1`), `env` (default `dev`).
- Keep the existing `README.md`; update it in 1–2 lines if needed. No resources yet (those are T2).

### 3. `infra/bootstrap/README.md` (the user's runbook)

Replace the current README with: what the bootstrap creates (one line per resource), then numbered steps, each with the exact command and what to check:
1. `export AWS_PROFILE=ai-platform` and `aws sts get-caller-identity` (expect account `531640468039`).
2. `cd infra/bootstrap && terraform init`.
3. `terraform plan -out=bootstrap.tfplan`; check the **exact** number of resources to add (count them from your code and write it here), 0 to change, 0 to destroy.
4. `terraform apply bootstrap.tfplan`.
5. Back up `terraform.tfstate` somewhere safe outside git (it's the only record of these resources).
6. `cd ../envs/dev && terraform init` (expect "Successfully configured the backend \"s3\"").
7. How to recover if the state file is lost (`terraform import` of each resource; list the import IDs).

### 4. `CLAUDE.md`

Keep all existing content. Update the *Project status* line to mention the bootstrap Terraform. Add to *Design rules that span components*:
- **Permissions boundary on every role:** any IAM role created by Terraform outside `infra/bootstrap/` must set `permissions_boundary` to `lsp-workload-boundary` and be named `lsp-*`; the deploy role can't create it otherwise.

Add to *How work is organised*:
- **Agents write, the user runs:** agents write code, config and docs and run only static checks (`terraform fmt`/`validate` with `-backend=false`, ruff, pytest with moto, pre-commit). The user does all version control (branches, commits, repo, push) and runs every Terraform or AWS command with real effects. Each brief ends with a runbook of commands for the user.

Add to *Commands*: `terraform -chdir=infra/bootstrap init -backend=false && terraform -chdir=infra/bootstrap validate` (and the same for `infra/envs/dev`).

## Acceptance checks (run all and paste the output in your report)

1. `terraform fmt -check -recursive infra` is clean.
2. `terraform -chdir=infra/bootstrap init -backend=false` and `terraform -chdir=infra/bootstrap validate` succeed.
3. `terraform -chdir=infra/envs/dev init -backend=false` and `terraform -chdir=infra/envs/dev validate` succeed.
4. `pre-commit run --all-files` passes (it may fix whitespace; re-run until clean). This doesn't commit anything.
5. `uv run pytest` still passes.
6. `git status --short` output (expect only new/changed files from this task; `.terraform/` dirs must not appear; `.terraform.lock.hcl` files should appear, the user will commit them).
7. `grep -rn "531640468039" infra/bootstrap` shows the account ID only in README text, not in `.tf` code.

## Out of scope (do not do; mention in the report if you think it's needed)

GitHub Actions workflows (T8); any application resources (T2); prod; tflint; `iam:CreateServiceLinkedRole` (flag it if you think a later service will need it); any git write or AWS call.

## Fix round 1 (after planner review, user-approved 2026-10-28)

Same rules as above (files only, no git writes, no AWS, static checks only).

1. **Use the Terraform skill.** Invoke the `terraform-skill:terraform-skill` skill and use it to review everything already written in `infra/bootstrap/` and `infra/envs/dev/`. **Report** its findings; don't apply anything beyond fixes 2 and 3 below without the planner's go-ahead.
2. **State bucket protection** (`roles.tf`, deploy policy): extend `DenyStateBucketAdmin` so the deploy role also can't:
   - on the bucket ARN: `s3:PutLifecycleConfiguration`, `s3:PutBucketOwnershipControls`, `s3:PutBucketAcl`, `s3:PutReplicationConfiguration`, `s3:PutBucketObjectLockConfiguration` (in addition to the existing six);
   - on `<bucket ARN>/*`: `s3:DeleteObjectVersion`, `s3:PutObjectAcl`.
   Normal state reads/writes (`GetObject`, `PutObject`, `DeleteObject` for the lock file, `ListBucket`) must still be allowed. Split into two statements (bucket and objects) if that reads more clearly.
3. **Boundary** (`boundary.tf`): add an explicit deny of `iam:PassRole` on `arn:aws:iam::<acct>:role/lsp-github-*`, so no workload role can ever pass a GitHub role.
4. Re-run all seven acceptance checks. The resource count must stay 13.

Deferred items from the review are recorded in `tasks/follow-ups.md` (F1–F7). Don't act on them.

## Fix round 2 (terraform-skill findings, user-approved 2026-10-28)

Same rules as above.

1. **Descriptions:** add a short `description` to every variable and output in `infra/bootstrap/` and `infra/envs/dev/`.
2. **State bucket lifecycle rule** (`state.tf`): add `aws_s3_bucket_lifecycle_configuration` for the state bucket with one rule, filter on the whole bucket:
   - `noncurrent_version_expiration`: `noncurrent_days = 90`, `newer_noncurrent_versions = 10` (always keep the newest 10 old versions);
   - `expired_object_delete_marker = true` (clean up delete markers left by lock files);
   - `abort_incomplete_multipart_upload` after 7 days.
   Add `depends_on = [aws_s3_bucket_versioning.state]`.
3. **README:** update the count to 14 (what it creates, plan and apply check lines) and add the lifecycle resource to the list and the import table (import ID = bucket name).
4. Re-run all seven acceptance checks; the count must be 14.

Findings F8–F12 in `tasks/follow-ups.md` are deferred; don't act on them.

## Report back

Message the planner (`ads-platform-3f`) with:
- the files created or changed
- the output of each acceptance check
- the resource count you put in the README
- anything you deviated from, and why
- any IAM design concerns or questions

Leave `status` as `assigned`; the planner sets it to `done` after the user has applied it and the planner has verified it.

## Change log

- 2026-11-01, user-directed (outside a brief): `infra/bootstrap/versions.tf` + `providers.tf` merged into `infra/bootstrap/main.tf`; `infra/envs/dev/versions.tf` + `providers.tf` + `backend.tf` merged into `infra/envs/dev/main.tf`. Content unchanged (same pins, provider, default tags, backend). Checks re-run clean; still 14 resources. File names in steps 1 and 2 above refer to the original layout.

## Fix round 3: harden `.gitignore` (user-requested 2026-11-01)

Same rules as above (files only, no git writes, no AWS). Edit only `.gitignore`; keep every existing entry and its grouping, add to the matching section:

- **Terraform:** `*.tfvars.json` (with `!*.example.tfvars.json`), `override.tf`, `override.tf.json`, `*_override.tf`, `*_override.tf.json`, `.terraform.tfstate.lock.info`, `crash.*.log`, `*.tfstate.backup` is already covered by `*.tfstate.*` (leave it).
- **Secrets and credentials:** `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials`, `credentials.json`, `.aws/`, `*.secret`, `secrets/`; and add `!.env.example` after `.env.*` so an example env file can be committed.
- **Build artifacts:** `build/`, `*.zip` (Lambda packages), `.aws-sam/`, `cdk.out/`.
- **Python:** `.mypy_cache/`, `htmlcov/`, `coverage.xml`, `.tox/`, `*.egg-info/`.
- **Node:** `npm-debug.log*`, `yarn-error.log*`, `.vite/`.
- **Editors / OS:** `.idea/`, `.vscode/`, `*.swp`, `Thumbs.db`.
- **Logs:** `*.log`.

Checks (paste output):
1. `git check-ignore -v` on: `infra/bootstrap/terraform.tfstate`, `infra/bootstrap/bootstrap.tfplan`, `infra/bootstrap/.terraform`, `x.pem`, `.env`, `build/x.zip`, `infra/envs/dev/override.tf`: all ignored.
2. `git check-ignore -v .env.example infra/bootstrap/.terraform.lock.hcl infra/bootstrap/main.tf`: none ignored (exit code 1, no output).
3. `git status --short` shows the same files as before plus `M .gitignore`; nothing that was listed before has disappeared.
4. `pre-commit run --all-files` passes.
