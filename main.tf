resource "aws_dynamodb_table" "items" {
  name         = "items"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_s3_bucket" "backup" {
  bucket = "item-backup"
}

resource "aws_sqs_queue" "processor" {
  name = "processor-queue"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {

  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Action = [
          "dynamodb:*",
          "s3:*",
          "sqs:*",
          "logs:*"
        ]

        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "writer" {

  function_name = "writer"

  filename         = "./lambda/writer/writer.zip"
  source_code_hash = filebase64sha256("./lambda/writer/writer.zip")

  role    = aws_iam_role.lambda_role.arn
  runtime = "provided.al2023"
  handler = "bootstrap"

  environment {
    variables = {
      TABLE  = aws_dynamodb_table.items.name
      BUCKET = aws_s3_bucket.backup.bucket
    }
  }
}

resource "aws_lambda_function" "reader" {

  function_name = "reader"

  filename         = "./lambda/reader/reader.zip"
  source_code_hash = filebase64sha256("./lambda/reader/reader.zip")

  role    = aws_iam_role.lambda_role.arn
  runtime = "provided.al2023"
  handler = "bootstrap"

  environment {
    variables = {
      TABLE = aws_dynamodb_table.items.name
    }
  }
}

resource "aws_lambda_function" "processor" {

  function_name = "processor"

  filename         = "./lambda/processor/processor.zip"
  source_code_hash = filebase64sha256("./lambda/processor/processor.zip")

  role    = aws_iam_role.lambda_role.arn
  runtime = "provided.al2023"
  handler = "bootstrap"

  environment {
    variables = {
      TABLE = aws_dynamodb_table.items.name
    }
  }
}


resource "aws_lambda_event_source_mapping" "processor" {

  event_source_arn = aws_sqs_queue.processor.arn

  function_name = aws_lambda_function.processor.arn

  batch_size = 1
}

resource "aws_s3_bucket_notification" "notify" {

  bucket = aws_s3_bucket.backup.id

  queue {

    queue_arn = aws_sqs_queue.processor.arn

    events = [
      "s3:ObjectCreated:*"
    ]
  }

  depends_on = [
    aws_sqs_queue_policy.allow_s3
  ]
}

resource "aws_sqs_queue_policy" "allow_s3" {

  queue_url = aws_sqs_queue.processor.id

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Principal = "*"

        Action = "sqs:SendMessage"

        Resource = aws_sqs_queue.processor.arn
      }
    ]
  })
}


resource "aws_api_gateway_rest_api" "api" {

  name = "items-api"
}

resource "aws_api_gateway_resource" "items" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  parent_id = aws_api_gateway_rest_api.api.root_resource_id

  path_part = "items"
}

resource "aws_api_gateway_method" "post" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.items.id

  http_method = "POST"

  authorization = "NONE"
}

resource "aws_api_gateway_integration" "writer" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.items.id

  http_method = aws_api_gateway_method.post.http_method

  integration_http_method = "POST"

  type = "AWS_PROXY"

  uri = aws_lambda_function.writer.invoke_arn
}

resource "aws_api_gateway_deployment" "deploy" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_integration.writer
  ]
}

resource "aws_api_gateway_stage" "dev" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  deployment_id = aws_api_gateway_deployment.deploy.id

  stage_name = "dev"
}