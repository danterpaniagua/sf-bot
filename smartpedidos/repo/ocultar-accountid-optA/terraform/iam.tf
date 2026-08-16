# --- Role assumed by API Gateway to call SQS directly (SendMessage/ReceiveMessage) ---

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_sqs_role" {
  name               = "${var.name_prefix}-apigw-sqs-role"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

data "aws_iam_policy_document" "apigw_sqs_access" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:ReceiveMessage"]
    resources = [for q in aws_sqs_queue.test_queue : q.arn]
  }
}

resource "aws_iam_role_policy" "apigw_sqs_access" {
  name   = "${var.name_prefix}-sqs-sendmessage"
  role   = aws_iam_role.apigw_sqs_role.id
  policy = data.aws_iam_policy_document.apigw_sqs_access.json
}

# --- Role assumed by the Lambda authorizer ---

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "authorizer_lambda_role" {
  name               = "${var.name_prefix}-authorizer-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "authorizer_basic_execution" {
  role       = aws_iam_role.authorizer_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "authorizer_secrets_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.jwt_secret.arn]
  }
}

resource "aws_iam_role_policy" "authorizer_secrets_read" {
  name   = "${var.name_prefix}-secrets-read"
  role   = aws_iam_role.authorizer_lambda_role.id
  policy = data.aws_iam_policy_document.authorizer_secrets_read.json
}

# --- Account-level role API Gateway assumes to push execution logs to CloudWatch ---
# Note: aws_api_gateway_account is a single, account-wide (per region) setting — applying
# this will overwrite whatever cloudwatchRoleArn already exists for this account/region,
# not just for this API. Confirm nothing else depends on a different value before applying.

data "aws_iam_policy_document" "apigw_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch_logs_role" {
  name               = "apigateway-cloudwatch-logs-poc"
  assume_role_policy = data.aws_iam_policy_document.apigw_logs_assume.json
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch_logs" {
  role       = aws_iam_role.apigw_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch_logs_role.arn
}
