variable "aws_region" {
  description = "Isolated region for this PoC — must not be a real prod/staging SQS region (prod: us-east-1, staging: us-east-2)."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Disposable naming prefix, kept outside the real ##_<ENV>_PlatformMessages.fifo convention to avoid any confusion with real branch queues."
  type        = string
  default     = "poc-arq009"
}

variable "test_branch_ids" {
  description = "Synthetic branchId values used to prove /{branchId} dynamic resolution. One queue is created per entry."
  type        = list(string)
  default     = ["branchA", "branchB"]
}

variable "stage_name" {
  description = "API Gateway deployment stage name."
  type        = string
  default     = "poc"
}

variable "jwt_secret_value" {
  description = <<-EOT
    JWT signing secret for the authorizer to validate against. This is concentrador-service's
    real `token.secret` (config/env/production.js) by explicit decision for this PoC, shared
    with platforms-service (see 20260720_credenciales-mongodb-hardcodeadas.md, SEC-118/SEC-119).
    Never hardcode this as a default here — supply via TF_VAR_jwt_secret_value or an untracked
    *.auto.tfvars file. It will still land in plain text in Terraform state; treat the state
    file itself as sensitive and delete it as part of PoC teardown.
  EOT
  type        = string
  sensitive   = true
}
