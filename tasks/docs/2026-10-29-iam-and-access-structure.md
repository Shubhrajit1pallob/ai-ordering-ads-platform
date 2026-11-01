---
date: 2026-10-29
project: local-store-platform
tasks: [P1-T1, overview]
kind: architecture-diagram-source
---

# IAM and access structure (source for the IAM diagram)

Companion to the target architecture drawing. This one shows **who and what can do what**: the AWS account setup, the human admin, the GitHub pipeline roles, the permissions boundary, the workload roles, and the app-level identities (Cognito) with tenant isolation.

Status legend for the drawing:
- **Exists today:** the account, the admin user/group, the CLI profile.
- **Written, not applied (P1-T1):** OIDC provider, `lsp-github-deploy`, `lsp-github-plan`, `lsp-workload-boundary`, state bucket.
- **Planned:** everything else (workload roles from P1-T2 on, Cognito, AWS Organizations, prod).

Use placeholders, not real IDs: `<account-id>`, `<admin-user>`. The vault is a git repo.

## 1. Account and organisation

- **Today:** one AWS account (`<account-id>`), region `us-east-1`, environment `dev` only. **No AWS Organizations** yet. 4 AWS Budgets exist (credit/cost alerts).
- **Planned later:** an AWS Organization with a management account and separate member accounts **dev** and **prod** (and, per F19, an optional dedicated account per large client, deployed from the same Terraform modules). Draw this as a dashed "future" box beside the current single account.

## 2. Human access

- **Admin IAM user** `<admin-user>` → member of an admin IAM group with AWS-managed **AdministratorAccess**.
- Used locally through the CLI profile **`ai-platform`** (short-lived login session, refreshed with `aws login --profile ai-platform`).
- Used for: the one-time bootstrap (`terraform apply` in `infra/bootstrap/`), and break-glass fixes. Not used by the pipeline.
- The planner agent uses the same profile for **read-only** lookups only (list/describe/get, IAM policy simulation).

## 3. GitHub pipeline access (P1-T1, written)

**GitHub repo** `<owner>/ai-ordering-ads-platform` → GitHub Actions requests a short-lived OIDC token → **IAM OIDC provider** `token.actions.githubusercontent.com` (audience `sts.amazonaws.com`) → `sts:AssumeRoleWithWebIdentity` into one of two roles. No stored AWS keys anywhere.

### `lsp-github-deploy` (deploys Terraform)
- **Trust:** only runs on the `main` branch (`sub = repo:<owner>/<repo>:ref:refs/heads/main`, `aud = sts.amazonaws.com`). Max session 1 hour.
- **Allowed:**
  - Manage platform services: Lambda, DynamoDB, S3, Step Functions, EventBridge + Scheduler, Textract, Bedrock, Cognito, SQS, SNS, SES, CloudWatch + Logs, X-Ray, Secrets Manager, Athena, Glue, API Gateway, CloudFront, KMS, ACM.
  - Create/change `lsp-*` roles **only if they carry `lsp-workload-boundary`**.
  - Manage `lsp-*` customer-managed policies.
  - Pass `lsp-*` roles only to Lambda, Step Functions, Scheduler, EventBridge, API Gateway, Cognito.
  - Read IAM.
- **Explicitly denied:**
  - Removing any permissions boundary; editing or deleting the boundary policy.
  - Any change to (or passing of) `lsp-github-*` roles, i.e. itself and the plan role.
  - Attaching AdministratorAccess, IAMFullAccess or PowerUserAccess, or using them as a boundary.
  - IAM users, groups, access keys, login profiles; OIDC/SAML provider changes.
  - On the state bucket: delete bucket, change policy/versioning/public access block/encryption/lifecycle/ownership/ACL/replication/object lock; delete old object versions.

### `lsp-github-plan` (runs `terraform plan` on pull requests)
- **Trust:** only pull requests of the repo (`sub = repo:<owner>/<repo>:pull_request`). Max session 1 hour.
- **Allowed:** AWS-managed ReadOnlyAccess; read the state bucket; write/delete only `*.tflock` lock files.
- Known follow-up (F1): narrow it and require a GitHub environment in P1-T8.

### Terraform state
- **State bucket** `lsp-tfstate-<account-id>`: versioned, encrypted, TLS only, public access blocked, old versions expire after 90 days (newest 10 kept). Holds `envs/dev/terraform.tfstate` + lock file. Deploy role reads/writes; plan role reads + lock file.
- Bootstrap's own state is a local file on the admin's machine (backed up manually).

## 4. Permissions boundary `lsp-workload-boundary` (the ceiling)

Draw it as a **dashed fence around all workload roles**: whatever a workload role's own policy says, it can never exceed this.
- **Allows:** the runtime services (Lambda, DynamoDB, S3, Step Functions, EventBridge, Scheduler, Textract, Bedrock, Cognito, SQS, SNS, SES, Logs, CloudWatch, X-Ray, Secrets Manager, Athena, Glue, API execute) and KMS encrypt/decrypt.
- **Allows** passing `lsp-*` roles only to Scheduler and Step Functions (the ads workflows create schedules).
- **Denies:** every other IAM action, passing `lsp-github-*` roles, AWS Organizations and account actions.
- Each workload role's own policy then narrows to least privilege (only its table, its bucket prefix, its model).

## 5. Workload roles (planned, P1-T2 onward; names illustrative)

All named `lsp-dev-*`, all carry the boundary, one role per function or state machine, created by the deploy role via Terraform.

| Component | Role (example) | Assumed by | Gets (narrowed) |
|---|---|---|---|
| Upload API | `lsp-dev-upload-url-fn` | Lambda | presign `s3:PutObject` on `store/<id>/` prefix of the raw photos bucket |
| Ingestion workflow | `lsp-dev-ingestion-sfn` | Step Functions | invoke ingestion Lambdas, Textract, Bedrock (Haiku only) |
| Ingestion Lambdas | `lsp-dev-validate-deal-fn` | Lambda | DynamoDB on the main table (store-scoped), read raw photo |
| Confirm/publish API | `lsp-dev-confirm-deal-fn` | Lambda | DynamoDB update, `events:PutEvents` (DealPublished) |
| Catalog / deals API | `lsp-dev-deals-api-fn` | Lambda | DynamoDB read (store-scoped) |
| S3 → EventBridge rule target | `lsp-dev-ingestion-start-events` | EventBridge | `states:StartExecution` on the ingestion workflow |
| Order workflow | `lsp-dev-order-sfn` | Step Functions | SQS, DynamoDB, Stripe secret read, SNS SMS |
| Ads WF1 / WF2 / WF3 | `lsp-dev-ads-create-sfn`, `-publish-sfn`, `-monitor-sfn` | Step Functions | Bedrock (text + image), Scheduler create (passes the scheduler role), channel secrets, Athena |
| Scheduler execution | `lsp-dev-ads-scheduler` | EventBridge Scheduler | `states:StartExecution` on WF2 / WF3 |

Show the PassRole hops: deploy role → passes roles to services; ads WF1 role → passes `lsp-dev-ads-scheduler` to Scheduler (allowed by the boundary).

## 6. App identities (Cognito, planned) and tenant isolation

Separate band from IAM: these are **application users**, not AWS principals.
- **Staff and owner** (store tablet): Cognito user pool; token carries `store_id` (and role: staff / owner). API Gateway JWT authorizer checks it.
- **Customers** (web app): later, Cognito or guest checkout; Stripe handles cards.
- **Partner integrations** (F20, later): Cognito app clients with client-credentials flow, scopes `deals:read` / `orders:write`, each tied to one store.
- **Tenant isolation chain:** token `store_id` → Lambda uses it (never the request) → DynamoDB keys `STORE#<id>#…` → Lambda role limited with `dynamodb:LeadingKeys` → S3 prefix `store/<id>/` → per-store secrets `lsp/<env>/store/<id>/…`.

## 7. Arrows to show

1. Admin user → (CLI profile) → AWS account: bootstrap apply.
2. GitHub Actions → OIDC provider → `lsp-github-deploy` (main) / `lsp-github-plan` (PRs).
3. Both GitHub roles → state bucket (read/write vs read + lock).
4. `lsp-github-deploy` → creates workload roles **inside** the boundary fence; red "denied" marks on: remove boundary, edit boundary, touch GitHub roles, attach Admin.
5. Services (Lambda, Step Functions, Scheduler, EventBridge) → assume their workload roles.
6. Ads WF1 role → PassRole → Scheduler role → starts WF2/WF3.
7. Cognito token (store_id) → API Gateway → Lambda → store-scoped data.

## Drawing hints
- Three bands: **Humans & GitHub** (outside AWS) · **IAM control plane** (OIDC, GitHub roles, boundary, state) · **Workloads** (roles inside the boundary fence, grouped by component) · plus a side band **App identities & tenant isolation**.
- Same legend style as the architecture drawing (dashed = planned, solid teal = written not applied, grey = outside AWS), plus **solid = exists today** and **red = explicit deny**.
- AWS icons where they help (IAM, IAM role, STS, Cognito, S3, Organizations).
