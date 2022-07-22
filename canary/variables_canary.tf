variable "NAMESPACE" {
  type = string
}

variable "REMOTE_STATE_PASSWORD" {
  type        = string
  description = "Password to access remote state (network)"
}

variable "GITLAB_PULL_SECRET" {
  type        = string
  description = "(required) Secret with docker configuration to pull images from gitlab registy"
}

variable "REPOSITORY_URL" {
  type        = string
  description = "(required) WelcomeBook Registry URL"
}

variable "DOCKER_TAG" {
  type        = string
  description = "(required) Tag of the image to deploy"
}

variable "CANARY_PERCENTAGE" {
  type        = string
  default     = 10
  description = "(required) How many traffic (%) is going to be redirected to canary deployment"
}

variable "CI_PROJECT_PATH_SLUG" {
  type = string
}

variable "CI_ENVIRONMENT_SLUG" {
  type = string
}

locals {
  app_server_snipet = <<EOF
    if ($host !~ ^(app.examplesystems.com|www.app.examplesystems.com)$) {
      return 444;
    }
    EOF
}