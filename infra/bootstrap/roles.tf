locals {
  oidc_host  = "token.actions.githubusercontent.com"
  repo_claim = "repo:${var.github_owner}/${var.github_repo}"
  bucket_arn = aws_s3_bucket.state.arn
  role_arn   = "arn:aws:iam::${local.account_id}:role"

  deploy_services = [
    "lambda", "dynamodb", "s3", "states", "events", "scheduler", "textract", "bedrock",
    "cognito-idp", "sqs", "sns", "ses", "logs", "cloudwatch", "xray", "secretsmanager",
    "athena", "glue", "apigateway", "cloudfront", "kms", "acm",
  ]

  # Roles the deploy role may pass, and the services it may pass them to.
  passable_services = [
    "lambda.amazonaws.com", "states.amazonaws.com", "scheduler.amazonaws.com",
    "events.amazonaws.com", "apigateway.amazonaws.com", "cognito-idp.amazonaws.com",
  ]

  # The deploy role may never touch itself or the plan role.
  github_role_write_actions = [
    "iam:PassRole", "iam:UpdateRole", "iam:UpdateRoleDescription",
    "iam:UpdateAssumeRolePolicy", "iam:DeleteRole", "iam:PutRolePolicy",
    "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary",
    "iam:TagRole", "iam:UntagRole",
  ]

  privileged_managed_policies = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/PowerUserAccess",
  ]
}

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.repo_claim}:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.repo_claim}:pull_request"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "lsp-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deploy" {
  name = "lsp-github-deploy-policy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PlatformServices"
        Effect   = "Allow"
        Action   = concat([for s in local.deploy_services : "${s}:*"], ["sts:GetCallerIdentity"])
        Resource = "*"
      },
      {
        # The boundary condition is what stops privilege escalation: a role created or
        # re-attached without lsp-workload-boundary is refused.
        Sid    = "WorkloadRolesOnlyWithBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy",
          "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
        ]
        Resource  = "${local.role_arn}/lsp-*"
        Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.boundary.arn } }
      },
      {
        Sid    = "WorkloadRoleHousekeeping"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
          "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy",
        ]
        Resource = "${local.role_arn}/lsp-*"
      },
      {
        Sid    = "WorkloadManagedPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/lsp-*"
      },
      {
        Sid       = "PassWorkloadRoles"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "${local.role_arn}/lsp-*"
        Condition = { StringEquals = { "iam:PassedToService" = local.passable_services } }
      },
      {
        Sid      = "IamRead"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      },
      {
        Sid      = "DenyRemovingBoundary"
        Effect   = "Deny"
        Action   = "iam:DeleteRolePermissionsBoundary"
        Resource = "*"
      },
      {
        Sid    = "DenyChangingBoundaryPolicy"
        Effect = "Deny"
        Action = [
          "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy",
        ]
        Resource = aws_iam_policy.boundary.arn
      },
      {
        Sid      = "DenyTouchingGithubRoles"
        Effect   = "Deny"
        Action   = local.github_role_write_actions
        Resource = "${local.role_arn}/lsp-github-*"
      },
      {
        Sid       = "DenyAttachingAdminPolicies"
        Effect    = "Deny"
        Action    = "iam:AttachRolePolicy"
        Resource  = "*"
        Condition = { ArnEquals = { "iam:PolicyARN" = local.privileged_managed_policies } }
      },
      {
        Sid      = "DenyAdminAsBoundary"
        Effect   = "Deny"
        Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource = "*"
        Condition = {
          ArnEquals = { "iam:PermissionsBoundary" = local.privileged_managed_policies }
        }
      },
      {
        Sid      = "DenyIdentityAndCredentialActions"
        Effect   = "Deny"
        Action   = ["iam:*User*", "iam:*Group*", "iam:*AccessKey*", "iam:*LoginProfile*"]
        Resource = "*"
      },
      {
        Sid    = "DenyIdentityProviderWrites"
        Effect = "Deny"
        Action = [
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider", "iam:CreateSAMLProvider", "iam:DeleteSAMLProvider",
          "iam:UpdateSAMLProvider", "iam:TagSAMLProvider", "iam:UntagSAMLProvider",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyStateBucketAdmin"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:PutBucketVersioning", "s3:PutBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration",
          "s3:PutBucketOwnershipControls", "s3:PutBucketAcl",
          "s3:PutReplicationConfiguration", "s3:PutBucketObjectLockConfiguration",
        ]
        Resource = local.bucket_arn
      },
      {
        # Object versions are the state history; state reads/writes and lock-file deletes stay allowed.
        Sid      = "DenyStateObjectTampering"
        Effect   = "Deny"
        Action   = ["s3:DeleteObjectVersion", "s3:PutObjectAcl"]
        Resource = "${local.bucket_arn}/*"
      },
    ]
  })
}

resource "aws_iam_role" "plan" {
  name                 = "lsp-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name = "lsp-github-plan-state"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListState"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.bucket_arn
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${local.bucket_arn}/*"
      },
      {
        # use_lockfile writes <state key>.tflock next to the state object.
        Sid      = "WriteLockFile"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket_arn}/*.tflock"
      },
    ]
  })
}
