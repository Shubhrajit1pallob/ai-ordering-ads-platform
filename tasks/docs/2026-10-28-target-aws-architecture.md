---
date: 2026-10-28
project: local-store-platform
tasks: [overview]
kind: architecture-diagram-source
---

# Target AWS architecture (source for the overview diagram)

This is the **planned** architecture of the whole platform, not what is built today. Mark built parts as they land (today: only the bootstrap layer from P1-T1 is written, not yet applied).

Account `531640468039`, region `us-east-1`, environment `dev` (prod later). Every resource is named `lsp-<env>-*` and tagged `project`, `env`, `managed_by`. Every record carries a store ID (multi-tenant).

## Zones to draw (left to right / top to bottom)

### 0. Actors (outside AWS)
- **Store staff tablet** (uploads offer photos, confirms deals, sees orders)
- **Store owner** (approves ads on the tablet)
- **Customers** (web app / chat, receive SMS/email)
- **Developer + GitHub** (`Shubhrajit1pallob/ai-ordering-ads-platform`)
- **External services:** Stripe (payments), Twilio or SNS (SMS), Google Business Profile, Meta Ads, Google Ads

### 1. Delivery and identity (edge)
- **CloudFront + S3**: hosts the tablet app and the customer web app (React + Vite)
- **Cognito user pool**: staff/owner sign-in; JWTs carry the store ID
- **API Gateway (HTTP API)** with Cognito JWT authorizer, in front of the Lambdas

### 2. Deals catalog (the hub)
- **Lambda** catalog/deals API handlers
- **DynamoDB** single table `lsp-dev-main` (GSI1 by status: pending / live)
- Everything else reads deals from here; the ordering and ads lanes never call each other

### 3. Offer ingestion pipeline (one Step Functions workflow)
1. Tablet asks the API for a presigned URL, uploads the photo straight to **S3 (raw photos bucket**, lifecycle rule expires old photos)
2. S3 event → **EventBridge** → starts **Step Functions** ingestion workflow
3. **Textract** reads the text → **Bedrock** (Claude Haiku via Converse, fixed JSON schema) maps it to product, regular price, offer price, start, end
4. **Lambda** validation (plain code) → deal saved `pending` in DynamoDB
5. Staff confirm on tablet → status `live` → **`DealPublished` event** on EventBridge
6. Failures: retries → **SQS DLQ** → staff alert (**SNS**)

### 4. Ordering lane
- Customer web app (or **Bedrock chat assistant** answering from the catalog) → **SQS** → **Step Functions** order workflow: **Stripe** payment, stock check, status updates (retries) → order shows on tablet → **SMS** when ready
- No card data stored (Stripe)

### 5. Ads lane (three separate Step Functions workflows)
- **WF1 create and approve:** triggered by `DealPublished`; Bedrock drafts copy (text model) and image (e.g. Nova Canvas); waits on a **callback task token** for owner approval; creates **EventBridge Scheduler** one-time schedules for offer start and end; ends
- **WF2 publish or stop:** started by those schedules; per-channel parallel start/pause (SMS, **SES** email, Google Business Profile first; Meta/Google Ads later); saves campaign IDs; only workflow that retries channel APIs
- **WF3 hourly monitor:** recurring schedule; joins ad spend with promo-code orders; auto-pauses ads above the cost-per-order limit
- Each ad gets its own promo code / UTM link; ad API tokens in **Secrets Manager**

### 6. Analytics and attribution
- Spend and order data land in **S3 (analytics bucket)** → **Glue catalog** → **Athena** queries → attribution dashboard (cost per order); results feed the next AI drafts

### 7. Observability (cross-cutting)
- **CloudWatch** logs, dashboards and alarms (failed orders, queue depth, AI errors, cost per order), **X-Ray** traces

### 8. Platform foundation (bootstrap, P1-T1, written)
- **S3 state bucket** `lsp-tfstate-531640468039` (versioned, encrypted, TLS only, Terraform native lockfile)
- **GitHub OIDC provider** → **`lsp-github-deploy`** role (main branch only) and **`lsp-github-plan`** role (pull requests, read-only)
- **`lsp-workload-boundary`** permissions boundary: the ceiling for every workload role (Lambda, Step Functions, Scheduler roles)
- **GitHub Actions** deploys Terraform via OIDC (no stored AWS keys)

## Key arrows to show
- Tablet → CloudFront; Tablet → API Gateway (JWT) → Lambda → DynamoDB
- Tablet → S3 raw photos (presigned) → EventBridge → Ingestion SFN → Textract / Bedrock / Lambda → DynamoDB
- Staff confirm → DynamoDB `live` → EventBridge `DealPublished` → Ads WF1
- WF1 → owner approval (task token) → Scheduler → WF2 → channels (SMS / SES / GBP / Meta / Google Ads)
- Scheduler (hourly) → WF3 → Athena / pause ads
- Customer → CloudFront → API Gateway → SQS → Order SFN → Stripe / DynamoDB / SMS
- Ordering + ads data → S3 analytics → Athena → dashboard
- GitHub Actions → OIDC → deploy role → (Terraform) all of the above; workload roles carry the boundary

## Build order (for colour or labels)
Phase 1 catalog + ingestion · 2 ordering · 3 direct promotion (ads WF1–3, SMS/email/GBP) · 4 analytics + attribution · 5 paid ads · 6 multi-store onboarding + load testing.
