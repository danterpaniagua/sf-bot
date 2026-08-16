# Holds the JWT signing secret the Lambda authorizer verifies against. See variables.tf
# for why this is the real production token.secret for this PoC, and the state-file caveat.

resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "${var.name_prefix}/jwt-secret"
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret_value
}
