data "archive_file" "authorizer_zip" {
  type        = "zip"
  source_file = "${path.module}/../authorizer/index.js"
  output_path = "${path.module}/build/authorizer.zip"
}

resource "aws_lambda_function" "jwt_authorizer" {
  function_name    = "${var.name_prefix}-jwt-authorizer"
  role             = aws_iam_role.authorizer_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.authorizer_zip.output_path
  source_code_hash = data.archive_file.authorizer_zip.output_base64sha256
}

resource "aws_lambda_permission" "apigw_invoke_authorizer" {
  statement_id  = "apigw-invoke-authorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jwt_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.this.id}/authorizers/${aws_api_gateway_authorizer.jwt.id}"
}
