# NOTE on the request templates below: Terraform's own interpolation syntax is `${...}`,
# which collides with VTL's formal-reference syntax `${input.params('branchId')}` — the exact
# gotcha discovered manually during this PoC (see 20260720_ocultar-account-id-sqs-urls
# investigation.md). Every `${input.params('branchId')}` here is deliberately written as
# `$${input.params('branchId')}` so Terraform emits it as a literal `${...}` for API Gateway/
# VTL to evaluate at request time, instead of trying to evaluate it itself as a Terraform
# expression (which would fail — there is no Terraform resource named `input`).
# `${var.aws_region}` / `${data.aws_caller_identity.current.account_id}` are genuine Terraform
# interpolations and are NOT escaped.

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.name_prefix}-hide-account-id"
}

resource "aws_api_gateway_resource" "branch" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{branchId}"
}

resource "aws_api_gateway_authorizer" "jwt" {
  name                             = "${var.name_prefix}-jwt-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.this.id
  type                             = "TOKEN"
  authorizer_uri                   = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.jwt_authorizer.arn}/invocations"
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
}

# --- POST /{branchId} -> SQS SendMessage ---

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.branch.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id

  request_parameters = {
    "method.request.path.branchId" = true
  }
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.branch.id
  http_method             = aws_api_gateway_method.post.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:action/SendMessage"
  credentials             = aws_iam_role.apigw_sqs_role.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<-EOT
      Action=SendMessage&Version=2012-11-05&QueueUrl=$util.urlEncode("https://sqs.${var.aws_region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.name_prefix}-$${input.params('branchId')}.fifo")&MessageBody=$util.urlEncode($input.body)&MessageGroupId=$util.urlEncode($input.params('branchId'))
    EOT
  }
}

resource "aws_api_gateway_method_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.branch.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.branch.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = aws_api_gateway_method_response.post_200.status_code

  depends_on = [aws_api_gateway_integration.post]
}

# --- GET /{branchId} -> SQS ReceiveMessage ---

resource "aws_api_gateway_method" "get" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.branch.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id

  request_parameters = {
    "method.request.path.branchId" = true
  }
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.branch.id
  http_method             = aws_api_gateway_method.get.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:action/ReceiveMessage"
  credentials             = aws_iam_role.apigw_sqs_role.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = <<-EOT
      Action=ReceiveMessage&Version=2012-11-05&QueueUrl=$util.urlEncode("https://sqs.${var.aws_region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.name_prefix}-$${input.params('branchId')}.fifo")&MaxNumberOfMessages=1&WaitTimeSeconds=0
    EOT
  }
}

resource "aws_api_gateway_method_response" "get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.branch.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "get_200" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.branch.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = aws_api_gateway_method_response.get_200.status_code

  depends_on = [aws_api_gateway_integration.get]
}

# --- Deployment / stage ---

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.branch.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_method.get.id,
      aws_api_gateway_integration.post.id,
      aws_api_gateway_integration.get.id,
      aws_api_gateway_integration_response.post_200.id,
      aws_api_gateway_integration_response.get_200.id,
      aws_api_gateway_authorizer.jwt.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "apigw_execution_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.this.id}/${var.stage_name}"
  retention_in_days = 7
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name

  depends_on = [aws_api_gateway_account.this, aws_cloudwatch_log_group.apigw_execution_logs]
}

resource "aws_api_gateway_method_settings" "logging" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    data_trace_enabled = true # PoC only — full body logging, do not carry into a real stage
  }
}
