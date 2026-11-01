variable "region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name, used in the env default tag."
  type        = string
  default     = "dev"
}
