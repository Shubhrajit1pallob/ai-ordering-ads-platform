---
date: 2026-10-28
project: local-store-platform
tasks: [P1-T0]
---

# Project kickoff and repo setup (2026-10-28)

Documentation handoff for the vault agent. Everything here is decided or done; nothing is speculative.

## The project

Local Store AI Ordering and Ads Platform: a multi-tenant serverless AWS platform for small local stores. Staff photograph weekly offers; Textract + Bedrock turn them into a deals catalog that staff confirm; customers order for pickup; an ads engine creates, schedules and tracks one ad per offer, with promo codes tying each order to its ad. Built first as a portfolio cloud project; a separate business plan covers taking it into a business setting later. Architecture summary: `CLAUDE.md` in the repo.

## Decisions made

1. **Technical brief is the source of truth; business plan is later background.** The business plan's phases and gates (and features only it mentions, like scan-to-pack and POS integrations) don't set current scope.
2. **Multi-agent workflow.** A planner session writes one task brief at a time in `tasks/`; the user approves each task before it is assigned; a worker session builds and verifies it; the planner reviews; a vault agent documents. The next task is planned only after the current one is verified.
3. **AWS setup:** one account, `dev` environment only for now, region `us-east-1`. Prod comes later.
4. **Platform defaults (planned):** Python 3.13 Lambdas, Terraform 1.12 with S3 remote state, API Gateway HTTP API with Cognito JWT auth, one DynamoDB table per environment, React + Vite frontends, GitHub Actions with OIDC. Bedrock Claude Haiku 5.5 planned for offer extraction.
5. **Phase 1 = the catalog**, split into nine tasks: T0 repo setup, T1 Terraform bootstrap, T2 core infrastructure, T3 upload API, T4 ingestion pipeline, T5 confirm/publish API, T6 public deals API, T7 tablet web app, T8 monitoring + CI/CD.
6. **Source PDFs are git-ignored**, so the business plan never ends up in a repo that may become public.

## What was done: P1-T0 repo setup (commit 8430730)

- Git repo on `main`, local only (no remote yet).
- Folder layout: `infra/{bootstrap,modules,envs/dev}`, `services/{shared,ingestion,catalog,tests}`, `web/`, `tasks/docs/`, `.github/workflows/`.
- Python via uv: ruff (lint + format), pytest, moto, boto3; one smoke test.
- Terraform pinned to 1.12.0.
- Pre-commit hooks: whitespace/EOF/YAML/large-file/merge-conflict checks, ruff, terraform fmt, gitleaks secret scan.
- `CLAUDE.md` gained Commands and How work is organised sections.

## Issues hit

- The AWS MCP server failed to connect at first (`-32602`): the `ai-platform` CLI profile's login session had expired. Fixed with `aws login --profile ai-platform`, then reconnecting in `/mcp`. The session expires periodically; the same fix applies.

## Next up

P1-T1 Terraform bootstrap: the remote state bucket and the GitHub OIDC deploy role. Needs a GitHub repo name first.
