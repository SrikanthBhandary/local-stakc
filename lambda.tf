resource "aws_lambda_function" "writer" {
  function_name = "writer"

  filename         = "./lambda/writer/writer.zip"
  source_code_hash = filebase64sha256("./lambda/writer/writer.zip")

  role    = aws_iam_role.lambda_role.arn
  runtime = "provided.al2023" # Running compiled custom bootstrap binaries
  handler = "bootstrap"

  environment {
    variables = {
      TABLE            = aws_dynamodb_table.enquiries.name
      BUCKET           = aws_s3_bucket.backup.bucket
      RATE_LIMIT_TABLE = aws_dynamodb_table.rate_limits.name
      SES_FROM_ADDRESS = aws_ses_email_identity.sender.email
      AWS_ENDPOINT_URL = "http://host.docker.internal:4566" # Configured for LocalStack
    }
  }
}

# 5.2 Reader Lambda Function
# Decoupled function tasked exclusively with retrieving and searching geographical dataset.
resource "aws_lambda_function" "reader" {
  function_name = "reader"

  filename         = "./lambda/reader/reader.zip"
  source_code_hash = filebase64sha256("./lambda/reader/reader.zip")

  role    = aws_iam_role.lambda_role.arn
  runtime = "provided.al2023"
  handler = "bootstrap"

  environment {
    variables = {
      TABLE            = aws_dynamodb_table.enquiries.name
      AWS_ENDPOINT_URL = "http://host.docker.internal:4566" # Configured for LocalStack
    }
  }
}

# 5.3 Processor Lambda Function
# Asynchronously processes backups triggered via SQS messages.
resource "aws_lambda_function" "processor" {
  function_name = "processor"

  filename         = "./lambda/processor/processor.zip"
  source_code_hash = filebase64sha256("./lambda/processor/processor.zip")

  role    = aws_iam_role.lambda_role.arn
  runtime = "provided.al2023"
  handler = "bootstrap"

  environment {
    variables = {
      TABLE            = aws_dynamodb_table.enquiries.name
      AWS_ENDPOINT_URL = "http://host.docker.internal:4566" # Configured for LocalStack
    }
  }
}

# 5.4 SQS-to-Processor Integration Map
# Binds the SQS processing queue directly to trigger the processor Lambda.
resource "aws_lambda_event_source_mapping" "processor" {
  event_source_arn = aws_sqs_queue.processor.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 1 # Process one item at a time
}

# 5.5 Reader Gateway Invoke Permissions
# Explicit permission allowing API Gateway to invoke the Reader lambda function.
resource "aws_lambda_permission" "reader_api" {
  statement_id  = "AllowAPIGatewayInvokeReader"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reader.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/admin/enquiries"
}