output "invoke_url" {
  description = "Base URL — append /{branchId} (e.g. /branchA) to call SendMessage (POST) or ReceiveMessage (GET)."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "queue_urls" {
  value = { for k, q in aws_sqs_queue.test_queue : k => q.url }
}

output "jwt_authorizer_function_arn" {
  value = aws_lambda_function.jwt_authorizer.arn
}

output "jwt_secret_arn" {
  description = "Secrets Manager ARN — remember this holds the real production token.secret. Force-delete without recovery at teardown."
  value       = aws_secretsmanager_secret.jwt_secret.arn
}
