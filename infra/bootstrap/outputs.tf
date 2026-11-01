output "state_bucket_name" {
  description = "Name of the S3 bucket that holds Terraform state."
  value       = aws_s3_bucket.state.id
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "boundary_policy_arn" {
  description = "ARN of lsp-workload-boundary, which every workload role must carry."
  value       = aws_iam_policy.boundary.arn
}

output "deploy_role_arn" {
  description = "ARN of the role GitHub Actions assumes from main to deploy."
  value       = aws_iam_role.deploy.arn
}

output "plan_role_arn" {
  description = "ARN of the read-only role GitHub Actions assumes on pull requests to plan."
  value       = aws_iam_role.plan.arn
}
