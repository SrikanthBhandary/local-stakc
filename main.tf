resource "aws_dynamodb_table" "enquiries" {
    name         = "enquiries"
    billing_mode = "PAY_PER_REQUEST"

    hash_key = "id"

    attribute {
      name = "id"
      type = "S"
    }

    # geohash is a fixed-precision string (e.g. 6 chars ~ 0.6km cells) computed
    # by the writer Lambda from lat/lng. Query this index for the enquiry's own
    # cell plus its 8 neighbor cells, then filter by exact haversine distance
    # for a true proximity search.
    attribute {
      name = "geohash"
      type = "S"
    }

    attribute {
      name = "createdAt"
      type = "S"
    }

    global_secondary_index {
      name            = "geohash-index"
      hash_key        = "geohash"
      range_key       = "createdAt"
      projection_type = "ALL"
    }
  }

  # Fixed-window request counter keyed by "ip#<sourceIP>#<windowStart>".
  # The writer Lambda does an atomic ADD + ConditionExpression against this
  # table to decide whether a given IP is over its per-minute limit, so
  # throttling works even for public, unauthenticated callers where API
  # Gateway usage plans (which key off API keys) don't apply.
  resource "aws_dynamodb_table" "rate_limits" {
    name         = "rate-limits"
    billing_mode = "PAY_PER_REQUEST"

    hash_key = "pk"

    attribute {
      name = "pk"
      type = "S"
    }

    ttl {
      attribute_name = "expiresAt"
      enabled        = true
    }
  }

  resource "aws_s3_bucket" "backup" {
    bucket = "item-backup"
  }

  resource "aws_sqs_queue" "processor" {
    name = "processor-queue"
  }

  resource "aws_ses_email_identity" "sender" {
    email = "hello@highpasses.example"
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

    # NOTE: writer/reader/processor currently share this one role. It's scoped
    # to the specific actions each of them needs rather than "*:*", but if you
    # want true least-privilege per function, split this into three roles later.
    policy = jsonencode({

      Version = "2012-10-17"

      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:UpdateItem",
            "dynamodb:Query"
          ]
          Resource = [
            aws_dynamodb_table.enquiries.arn,
            "${aws_dynamodb_table.enquiries.arn}/index/*",
            aws_dynamodb_table.rate_limits.arn
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject"
          ]
          Resource = "${aws_s3_bucket.backup.arn}/*"
        },
        {
          Effect   = "Allow"
          Action   = "sqs:SendMessage"
          Resource = aws_sqs_queue.processor.arn
        },
        {
          Effect   = "Allow"
          Action   = "ses:SendEmail"
          Resource = "*"
          Condition = {
            StringEquals = {
              "ses:FromAddress" = aws_ses_email_identity.sender.email
            }
          }
        },
        {
          Effect   = "Allow"
          Action   = "logs:*"
          Resource = "arn:aws:logs:*:*:*"
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
        TABLE            = aws_dynamodb_table.enquiries.name
        BUCKET           = aws_s3_bucket.backup.bucket
        RATE_LIMIT_TABLE = aws_dynamodb_table.rate_limits.name
        SES_FROM_ADDRESS = aws_ses_email_identity.sender.email
        AWS_ENDPOINT_URL = "http://host.docker.internal:4566"
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
        TABLE            = aws_dynamodb_table.enquiries.name
        AWS_ENDPOINT_URL = "http://host.docker.internal:4566"
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
        TABLE            = aws_dynamodb_table.enquiries.name
        AWS_ENDPOINT_URL = "http://host.docker.internal:4566"
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

          Principal = {
            Service = "s3.amazonaws.com"
          }

          Action = "sqs:SendMessage"

          Resource = aws_sqs_queue.processor.arn

          Condition = {
            ArnEquals = {
              "aws:SourceArn" = aws_s3_bucket.backup.arn
            }
          }
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
    aws_api_gateway_integration.writer,
    aws_api_gateway_integration.reader,
    aws_api_gateway_method.get_enquiries,
    aws_api_gateway_authorizer.cognito
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.get_enquiries.id,
      aws_api_gateway_integration.reader.id,
      aws_api_gateway_authorizer.cognito.id
    ]))
  }
}

  resource "aws_api_gateway_stage" "dev" {

    rest_api_id = aws_api_gateway_rest_api.api.id

    deployment_id = aws_api_gateway_deployment.deploy.id

    stage_name = "dev"
  }

  # Aggregate ceiling across all callers. This is a coarse safety net for the
  # whole stage/method — it won't stop one IP hammering the endpoint below this
  # limit, which is what the Lambda's own per-IP counter (rate_limits table) is
  # for. Keep both: this one protects the account/downstream services, the
  # Lambda one protects individual customers from each other.
  resource "aws_api_gateway_method_settings" "enquiry_throttle" {

    rest_api_id = aws_api_gateway_rest_api.api.id
    stage_name  = aws_api_gateway_stage.dev.stage_name
    method_path = "${aws_api_gateway_resource.items.path_part}/${aws_api_gateway_method.post.http_method}"

    settings {
      throttling_rate_limit  = 10
      throttling_burst_limit = 20
    }
  }

resource "aws_cognito_user_pool" "admin" {
  name = "highpasses-admin"
}

resource "aws_cognito_user_pool_client" "admin" {
  name         = "admin-web"
  user_pool_id = aws_cognito_user_pool.admin.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

resource "aws_cognito_user_pool_domain" "admin" {
  domain       = "highpasses-admin"
  user_pool_id = aws_cognito_user_pool.admin.id
}

resource "aws_cognito_user" "admin" {
  user_pool_id = aws_cognito_user_pool.admin.id
  username     = "admin@highpasses.com"

  attributes = {
    email          = "admin@highpasses.com"
    email_verified = "true"
  }

  temporary_password = "Password123!"
}

resource "null_resource" "set_admin_password" {
  depends_on = [aws_cognito_user.admin]

  provisioner "local-exec" {
    command = <<EOT
aws --endpoint-url=http://localhost:4566 \
  cognito-idp admin-set-user-password \
  --user-pool-id ${aws_cognito_user_pool.admin.id} \
  --username admin@highpasses.com \
  --password Password123! \
  --permanent \
  --region us-east-1
EOT
  }
}

resource "aws_api_gateway_authorizer" "cognito" {

  name = "highpasses-admin-authorizer"

  rest_api_id = aws_api_gateway_rest_api.api.id

  type = "COGNITO_USER_POOLS"

  provider_arns = [
    aws_cognito_user_pool.admin.arn
  ]

  identity_source = "method.request.header.Authorization"
}


resource "aws_api_gateway_resource" "admin" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  parent_id = aws_api_gateway_rest_api.api.root_resource_id

  path_part = "admin"
}


resource "aws_api_gateway_resource" "enquiries" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  parent_id = aws_api_gateway_resource.admin.id

  path_part = "enquiries"
}


resource "aws_api_gateway_method" "get_enquiries" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.enquiries.id

  http_method = "GET"


  authorization = "COGNITO_USER_POOLS"


  authorizer_id = aws_api_gateway_authorizer.cognito.id

}

resource "aws_api_gateway_integration" "reader" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.enquiries.id

  http_method = aws_api_gateway_method.get_enquiries.http_method


  integration_http_method = "POST"

  type = "AWS_PROXY"


  uri = aws_lambda_function.reader.invoke_arn
}

resource "aws_lambda_permission" "reader_api" {

  statement_id = "AllowAPIGatewayInvokeReader"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.reader.function_name

  principal = "apigateway.amazonaws.com"


  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/admin/enquiries"
}
