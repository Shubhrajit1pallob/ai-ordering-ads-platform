variable "region" {
  description = "AWS region for the state bucket and IAM resources."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repo allowed to assume the roles."
  type        = string
  default     = "Shubhrajit1pallob"
}

variable "github_repo" {
  description = "GitHub repo name allowed to assume the deploy and plan roles."
  type        = string
  default     = "ai-ordering-ads-platform"
}
