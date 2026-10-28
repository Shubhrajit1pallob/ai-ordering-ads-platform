# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Pre-pilot. The repo is a skeleton with Python (uv, ruff, pytest) and pre-commit tooling and no application or Terraform code yet; the two source PDFs are kept on disk but git-ignored.

- `Local Store AI Ordering and Ads Platform.pdf`: the technical design brief (architecture, workflows, stack, build plan). **This is the active project and the source of truth for what gets built.**
- `Local Store Platform Business Plan.pdf`: a separate, later use case: taking the finished platform into a business setting (pricing, go-to-market, pilot metrics, phase gates). Use it as background context only; it does not set current scope or build order.

When a design decision isn't covered by the technical brief, flag it as an open question rather than inventing an answer.

## Commands

- Setup: `uv sync`
- All tests: `uv run pytest`
- One test: `uv run pytest services/tests/test_smoke.py::<name>` or `uv run pytest -k <name>`
- Lint: `uv run ruff check .`
- Format: `uv run ruff format .`
- All hooks: `pre-commit run --all-files`
- Terraform format: `terraform fmt -recursive infra`

## How work is organised

A planner session writes task briefs in `tasks/P<phase>-T<n>-<slug>.md` and assigns them one at a time. A worker session implements and verifies each brief and reports back. A vault agent documents in the user's Obsidian vault from notes in `tasks/docs/`. Only one task is in progress at a time; a brief's frontmatter `status` tracks it (`assigned` → `done`). Workers stay within a brief's scope and report anything out of scope instead of doing it.

## What the platform does

A multi-tenant AWS platform for small local stores (pilot: one independent grocery store). Staff photograph weekly offers, AI turns them into a live deals catalog, customers order for pickup, and an ads engine creates, schedules and tracks one ad per offer, with every order attributed to the ad that drove it.

## Architecture (big picture)

The **deals catalog** (API Gateway + Lambda + DynamoDB) is the hub. Two lanes read from it and never call each other: **ordering** and **ads**. They connect only through the catalog and promo codes. The attribution dashboard joins sales (ordering) with ad spend (ads) to compute cost per order.

### Offer ingestion (one Step Functions workflow)
1. Store tablet, signed in with Cognito, gets a short-lived presigned S3 URL and uploads the photo directly to S3.
2. S3 event → EventBridge → starts the Step Functions workflow.
3. Textract reads the text; Bedrock maps it to a fixed JSON schema: product, regular price, offer price, start date, end date.
4. Plain-code validation: prices > 0, offer price < regular price, end date > start date, no active deal for the same product and dates.
5. Deal saved as `pending`; tablet shows photo beside extracted fields with problems highlighted for staff to fix and confirm.
6. On confirm: status → `live`, and a `DealPublished` event goes to EventBridge for the ads module.
7. Failures: Step Functions retries, then a DLQ, then a staff alert. An S3 lifecycle rule expires old raw photos.

### Ordering
Web app on CloudFront (or the Bedrock chat assistant answering from the catalog) → SQS → Step Functions handles Stripe payment, stock checks and status updates with retries → order shows on the store tablet → SMS when ready.

### Ads module (three separate Step Functions workflows, by design)
- **Workflow 1, create and approve:** Bedrock drafts copy and image; pauses on a **callback task token** until the owner taps approve on the tablet; then creates one-time EventBridge Scheduler schedules for offer start and end, and **ends** (it does not wait weeks for the offer to start).
- **Workflow 2, publish or stop:** triggered by those schedules; starts or pauses ads per channel in parallel; saves campaign IDs. Only this workflow retries when a channel API is down.
- **Workflow 3, hourly monitor:** recurring schedule; joins ad spend with promo-code orders; auto-pauses ads above the cost-per-order limit. Runs independently as a safety net.
- Editing an offer's dates updates only its schedules.
- Each ad gets its own promo code or UTM link. Spend and orders land in S3 and are queried with Athena for the dashboard; results feed back into the next AI drafts.
- Channel rollout: SMS, email (SES) and Google Business Profile posts first; Meta and Google Ads only after their API access is approved.

## Design rules that span components

- **Multi-tenant from day one:** every record carries a store ID, with IAM and query-level isolation. Also log usage (AI calls, messages, orders) with the store ID and tag store-specific resources, because per-store cost tracking sets the pricing floor.
- **AI drafts, code checks, humans approve:** nothing AI-generated (deals, ad copy, spend) goes live without code validation and staff or owner approval. Bedrock output that code consumes must be forced to a fixed JSON schema and validated before use.
- **Bedrock usage:** call from Lambda via boto3 (Converse API for text models). Each Lambda role gets `bedrock:InvokeModel` only for the models it uses. Text model (Claude or Amazon Nova) for extraction, ad copy and chat; image model (e.g. Nova Canvas) for ad images. Check the Bedrock console for current model names and regional availability before choosing.
- **No card data stored:** Stripe handles payments, keeping the platform out of PCI scope.
- **Budget guardrails:** daily spend caps and auto-pause on high cost per order; ad API tokens live in Secrets Manager.
- **Everything as code:** Terraform modules per component, GitHub Actions with OIDC (no stored AWS keys), separate dev and prod.
- **Observability:** CloudWatch dashboards and alarms for failed orders, queue depth, AI errors and cost per order.

**Stack:** Terraform, S3, CloudFront, API Gateway, Lambda, DynamoDB, SQS, Step Functions, EventBridge (+ Scheduler), Textract, Bedrock, Cognito, Secrets Manager, Athena, CloudWatch, GitHub Actions, Stripe, Twilio or SNS, SES, Meta and Google ad APIs.

## Build order

Technical build plan: (1) catalog and ingestion, (2) ordering, (3) direct promotion (ad creator, approval, SMS/email/GBP with promo codes), (4) analytics and attribution, (5) paid ads, (6) multi-store onboarding and load testing.

Follow this technical build plan. The business plan's phases and gates (and features only it mentions, like scan-to-pack verification and POS integrations) apply later, when the platform moves into a business setting; don't build them unless the user asks.

## Open questions (from the docs)

- Will the pilot owner commit to click-and-collect, and on what terms?
- Which POS does the pilot store use, and does it have an API?
- Which channels do customers use (Facebook, Instagram, Google Maps, SMS)? Does the store have Meta/Google business accounts?
- Pickup only, or local delivery later?
- External approvals with lead time: Bedrock model access, Stripe live mode, SMS sender registration (10DLC/toll-free), SES production access, Google Business Profile API, Meta app review, Google Ads developer token.
