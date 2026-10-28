---
task: P1-T0
title: Repo setup
status: assigned
assigned_to: worker
date: 2026-10-28
approved_by: user
---

# P1-T0: Repo setup

## Goal

Turn this folder into a working repo skeleton with test and lint tooling, so later tasks have a place for code and a way to check it.

**Local only.** No AWS calls or resources, no GitHub repo, no remote, no push.

## Context

- Project: Local Store AI Ordering and Ads Platform, a multi-tenant serverless AWS platform (Terraform, Python Lambdas, Step Functions, DynamoDB, React frontends later). Read `CLAUDE.md` for the architecture.
- The folder currently holds: `CLAUDE.md`, `.claude/`, two PDFs, and this `tasks/` folder. It is not a git repo yet.
- Tools already on the machine: git 2.44, uv 0.12, Python 3.13.12, Terraform 1.12.0, Node 22. **Missing:** pre-commit, gitleaks (install as below). Don't install tflint (that's T1).

## Steps

1. `git init -b main`.
2. Create `.gitignore` covering at least:
   - Terraform: `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfplan`, `crash.log`, `*.tfvars` but **not** `*.example.tfvars` (use a `!*.example.tfvars` negation)
   - Python: `.venv/`, `__pycache__/`, `*.pyc`, `.pytest_cache/`, `.ruff_cache/`, `.coverage`
   - Node: `node_modules/`, `dist/`
   - Secrets/OS: `.env`, `.env.*`, `.DS_Store`
   - Claude local settings: `.claude/settings.local.json`
   - **Both PDFs by exact name:** `Local Store AI Ordering and Ads Platform.pdf` and `Local Store Platform Business Plan.pdf`. They stay on disk but must never be committed (the repo may become public).
3. Create the folder skeleton. Each folder gets a short `README.md` (2–4 lines) saying what goes there:
   - `infra/bootstrap/`: one-time Terraform for the state bucket and GitHub OIDC role (local state)
   - `infra/modules/`: one Terraform module per component (auth, storage, data, events, ingestion, api, web, observability)
   - `infra/envs/dev/`: root module composing the modules for the dev environment
   - `services/shared/`: shared Python code (tenancy from JWT claims, DynamoDB keys, logging with store ID)
   - `services/ingestion/`: Lambda handlers for the offer ingestion pipeline
   - `services/catalog/`: Lambda handlers for the catalog and deals APIs
   - `services/tests/`: pytest tests; moto for AWS; fixtures for Textract/Bedrock responses
   - `web/`: frontends (tablet app first, customer app later)
   - `tasks/docs/`: documentation handoff notes for the vault agent
   - `.github/workflows/`: CI/CD (filled in a later task; add a `.gitkeep` instead of a README)
4. Python tooling with uv:
   - `uv init --bare` (or write `pyproject.toml` by hand): project name `local-store-platform`, `requires-python = ">=3.13"`, no package build needed for now.
   - `.python-version` containing `3.13`.
   - Dev dependency group, added via `uv add --dev ...` so `uv.lock` is generated: `ruff`, `pytest`, `boto3`, and `moto[s3,dynamodb,events,stepfunctions,sqs,sns,cognitoidp]` (not `moto[all]`, which is too heavy).
   - Ruff config in `pyproject.toml`: `line-length = 100`, `target-version = "py313"`, lint `select = ["E", "F", "I", "B", "UP"]`.
   - Pytest config in `pyproject.toml`: `testpaths = ["services/tests"]`, `pythonpath = ["services"]`.
5. `services/tests/test_smoke.py` with one trivial passing test (e.g. assert that `boto3` imports and the Python version is ≥ 3.13).
6. `.terraform-version` containing `1.12.0`.
7. Pre-commit:
   - Install with `uv tool install pre-commit`.
   - `.pre-commit-config.yaml` with pinned `rev`s (current stable releases) for:
     - `pre-commit/pre-commit-hooks`: `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-added-large-files` (`--maxkb=1000`), `check-merge-conflict`
     - `astral-sh/ruff-pre-commit`: `ruff-check` (with `--fix`) and `ruff-format`
     - `antonbabenko/pre-commit-terraform`: `terraform_fmt` only
     - `gitleaks/gitleaks`: `gitleaks`
   - `pre-commit install`.
8. Root `README.md`: one paragraph on what the platform is (photo of weekly offers → AI-extracted deals catalog → pickup ordering and tracked local ads; multi-tenant on AWS), then a **Setup** block: `uv sync`, `uv tool install pre-commit`, `pre-commit install`, `uv run pytest`.
9. Update `CLAUDE.md` (keep all existing content; replace the "there is no code… record the real commands here" sentence in *Project status* with an accurate one-liner), and add two sections after *Project status*:
   - **Commands**: setup (`uv sync`), all tests (`uv run pytest`), one test (`uv run pytest services/tests/test_smoke.py::<name>` and the `-k` form), lint (`uv run ruff check .`), format (`uv run ruff format .`), all hooks (`pre-commit run --all-files`), Terraform format (`terraform fmt -recursive infra`).
   - **How work is organised**: a planner session writes task briefs in `tasks/P<phase>-T<n>-<slug>.md` and assigns them one at a time; a worker session implements and verifies each brief and reports back; a vault agent documents in the user's Obsidian vault from notes in `tasks/docs/`. Only one task is in progress at a time; a brief's frontmatter `status` tracks it (`assigned` → `done`). Workers stay within a brief's scope and report anything out of scope instead of doing it.
10. Stage everything (including this brief and `tasks/`) and make one commit: `Set up repo skeleton and tooling`. Pre-commit hooks must pass on that commit; fix issues rather than bypassing with `--no-verify`.

## Acceptance checks (run all and paste the output in your report)

1. `uv sync` succeeds.
2. `uv run pytest` shows 1 passed.
3. `uv run ruff check .` and `uv run ruff format --check .` are clean.
4. `pre-commit run --all-files` passes.
5. `git check-ignore -v "Local Store AI Ordering and Ads Platform.pdf" "Local Store Platform Business Plan.pdf"` shows both ignored.
6. `git status --short` is empty after the commit.
7. `git log --oneline` shows exactly one commit; `git remote -v` shows nothing.
8. `git ls-files` contains no PDF and no `.claude/settings.local.json`.

## Out of scope (do not do; mention in the report if you think it's needed)

Any AWS call or resource; Terraform code; tflint; creating a GitHub repo, adding a remote or pushing; application code; Node/web tooling.

## Report back

Message the planner (`ads-platform-3f`) with:
- the files created or changed
- the output of each acceptance check
- anything you deviated from, and why
- any problems or questions

Leave `status` in this file's frontmatter as `assigned`; the planner sets it to `done` after review.
