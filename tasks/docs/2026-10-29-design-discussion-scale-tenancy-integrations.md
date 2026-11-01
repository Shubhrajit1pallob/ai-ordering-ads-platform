---
date: 2026-10-29
project: local-store-platform
tasks: [design-discussion]
---

# Design discussion: Kubernetes, multiple businesses, outside integrations (2026-10-28/29)

Documentation handoff for the vault agent. These are decisions made in discussion; the detailed items are in `tasks/follow-ups.md` (F13–F22) and the rules in `CLAUDE.md` (Design rules).

## Decisions

1. **Serverless by default; Kubernetes not planned.** At pilot scale EKS adds roughly $150+/month in fixed cost before any traffic and would replace Step Functions callbacks, retries and Scheduler with self-run tools. The main costs (Bedrock, Textract, SMS/email) are the same either way. Kubernetes would only be considered for steady all-day heavy traffic (decided from cost data), a client needing on-prem/other-cloud deployment, self-hosted GPU models, a large team standardised on it, or a portfolio demo. Escalation ladder, one service at a time: Lambda → Lambda container image → ECS Fargate → EKS. (F13)
2. **Multiple businesses = pooled multi-tenancy.** All stores share the same infrastructure; isolation is layered: store ID from the Cognito token (never the request), `STORE#<id>#` DynamoDB keys, `dynamodb:LeadingKeys` on Lambda roles, per-store S3 prefixes and presigned URLs, per-store settings record and secrets path, and a store A/store B denial test in every API task. Later: Stripe Connect for per-business payouts, an onboarding workflow, per-business-type settings, and a dedicated-account (silo) option for a large client. (F14, F16–F19)
3. **Outside websites, apps and features connect only through defined entry points:** versioned public API with per-client credentials, signed outbound webhooks via EventBridge API destinations, data imports and POS adapters, embeddable widgets and white label. No tenant code runs inside the platform; no direct database access. The public deals API (P1-T6) is built integration-ready now (`/v1`, OpenAPI). (F15, F20–F22)

## Other notes

- Cost levers planned within serverless: Graviton Lambdas, no NAT gateway, on-demand DynamoDB and HTTP API, Step Functions Express for ordering, Haiku for extraction, short log retention, S3 lifecycle rules, budgets and per-store cost tags.
- Target architecture drawing (Excalidraw, with AWS icons) is in the vault; AWS icon terms should be checked before public use.
