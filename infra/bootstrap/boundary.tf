locals {
  runtime_services = [
    "lambda", "dynamodb", "s3",
    "states", "events", "scheduler",
    "textract", "bedrock", "cognito-idp",
    "sqs", "sns", "ses",
    "logs", "cloudwatch",
    "xray", "secretsmanager",
    "athena", "glue", "execute-api",
  ]
}

# Ceiling for every workload role the pipeline creates.
# A role's own policy can only
# narrow what this allows, never widen it.
resource "aws_iam_policy" "boundary" {
  name = "lsp-workload-boundary"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RuntimeServices"
        Effect   = "Allow"
        Action   = [for s in local.runtime_services : "${s}:*"]
        Resource = "*"
      },
      {
        Sid      = "Kms"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"]
        Resource = "*"
      },
      {
        # The ads workflows create schedules that pass a role to Scheduler or Step Functions.
        Sid      = "PassRoleToSchedulerAndStates"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/lsp-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["scheduler.amazonaws.com", "states.amazonaws.com"]
          }
        }
      },
      {
        # Verb wildcards cover every iam action except PassRole (allowed above). A Deny
        # with Action "iam:*" would also block PassRole, because explicit deny wins.
        Sid    = "DenyOtherIam"
        Effect = "Deny"
        Action = [
          "iam:Add*", "iam:Attach*", "iam:Change*",
          "iam:Create*", "iam:Deactivate*",
          "iam:Delete*", "iam:Detach*", "iam:Enable*",
          "iam:Generate*", "iam:Get*",
          "iam:List*", "iam:Put*", "iam:Remove*",
          "iam:Reset*", "iam:Resync*", "iam:Set*",
          "iam:Simulate*", "iam:Tag*", "iam:Untag*",
          "iam:Update*", "iam:Upload*",
        ]
        Resource = "*"
      },
      {
        # Wins over the PassRole allow above, so no workload role can pass a GitHub role.
        Sid      = "DenyPassGithubRoles"
        Effect   = "Deny"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/lsp-github-*"
      },
      {
        Sid      = "DenyOrganizationsAndAccount"
        Effect   = "Deny"
        Action   = ["organizations:*", "account:*"]
        Resource = "*"
      },
    ]
  })
}
