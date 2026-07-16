# ==============================================================================
# SECTION 1: IDENTITY, ACCESS, & SECRETS MANAGEMENT
# ==============================================================================

# 1.1 Secure Password Generation
# Generates a high-entropy 24-character password used for the initial admin account.
resource "random_password" "admin" {
  length  = 24
  special = true
  
  # Limit special characters to safe ones to prevent shell escaping/parsing issues
  override_special = "_-."

  # Password strength policy constraints
  min_upper   = 2
  min_lower   = 2
  min_numeric = 4
  min_special = 2
}

# 1.2 Secrets Manager: Secret Container
# Creates a logical secret container in AWS Secrets Manager to hold the admin credentials.
resource "aws_secretsmanager_secret" "admin_password" {
  name        = "highpasses/admin/password"
  description = "Auto-generated admin credentials for the Highpasses platform"
}

# 1.3 Secrets Manager: Secret Value
# Stores the generated password as a JSON payload inside the Secrets Manager container.
resource "aws_secretsmanager_secret_version" "admin_password" {
  secret_id     = aws_secretsmanager_secret.admin_password.id
  secret_string = jsonencode({
    password = random_password.admin.result
  })
}

# 1.4 Cognito User Pool
# Acts as the main identity provider (IdP) for platform administrators.
resource "aws_cognito_user_pool" "admin" {
  name = "highpasses-admin"
}

# 1.5 Cognito User Pool Client
# Enables client applications (like a web console) to authenticate against the user pool.
resource "aws_cognito_user_pool_client" "admin" {
  name         = "admin-web"
  user_pool_id = aws_cognito_user_pool.admin.id

  # Disabled because web client architectures cannot safely keep secrets hidden
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# 1.6 Cognito Domain
# Required to host the Cognito hosted UI endpoints.
resource "aws_cognito_user_pool_domain" "admin" {
  domain       = "highpasses-admin"
  user_pool_id = aws_cognito_user_pool.admin.id
}

# 1.7 Default Admin User
# Seeds the user pool with a default admin account assigned a temporary password.
resource "aws_cognito_user" "admin" {
  user_pool_id = aws_cognito_user_pool.admin.id
  username     = "admin@highpasses.com"

  attributes = {
    email          = "admin@highpasses.com"
    email_verified = "true"
  }

  temporary_password = "Dummypassword23@"
}

# 1.8 Password Fetcher (Data Source)
# Pulls the generated secret back into the Terraform state to use in subsequent local execution steps.
data "aws_secretsmanager_secret_version" "admin_password" {
  depends_on = [
    aws_secretsmanager_secret_version.admin_password
  ]
  secret_id = aws_secretsmanager_secret.admin_password.id
}

# Local variable block for parsing the fetched password JSON payload safely.
locals {
  admin_password = jsondecode(
    data.aws_secretsmanager_secret_version.admin_password.secret_string
  ).password
}

# 1.9 Local Password Transition (Local-Exec Provisioner)
# Overrides the temporary Cognito password with the strong randomly generated password.
# Designed for LocalStack emulation (using the local endpoint override).
resource "null_resource" "set_admin_password" {
  depends_on = [
    aws_cognito_user.admin
  ]

  provisioner "local-exec" {
    command = <<EOT
aws --endpoint-url=http://localhost:4566 \
  cognito-idp admin-set-user-password \
  --user-pool-id ${aws_cognito_user_pool.admin.id} \
  --username admin@highpasses.com \
  --password "${random_password.admin.result}" \
  --permanent \
  --region us-east-1
EOT
  }
}


# ==============================================================================
# SECTION 2: DATABASE LAYER (DYNAMODB)
# ==============================================================================

# 2.1 Enquiries Table
# Stores customer enquiry submissions. Configured with a Global Secondary Index (GSI)
# to handle location-based geohash range queries efficiently.
resource "aws_dynamodb_table" "enquiries" {
  name         = "enquiries"
  billing_mode = "PAY_PER_REQUEST" # On-demand pricing ideal for variable traffic

  hash_key = "id"

  # Base table attributes
  attribute {
    name = "id"
    type = "S"
  }

  # Geohash is a fixed-precision string computed from lat/lng by the writer Lambda.
  # Enables query of target cell plus 8 neighbors for exact haversine calculations.
  attribute {
    name = "geohash"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # Secondary index for geospatial and chronological queries
  global_secondary_index {
    name            = "geohash-index"
    hash_key        = "geohash"
    range_key       = "createdAt"
    projection_type = "ALL"
  }
}

# 2.2 Rate Limits Table
# A fast, transient store for distributed per-IP rate-limiting.
# Keys are structured as: "ip#<sourceIP>#<windowStart>"
resource "aws_dynamodb_table" "rate_limits" {
  name         = "rate-limits"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # AWS automatically purges stale records using this attribute, saving storage & costs
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
}


# ==============================================================================
# SECTION 3: STORAGE & ASYNCHRONOUS PROCESSING (S3, SQS, & SES)
# ==============================================================================

# 3.1 Backup S3 Bucket
# Serves as the backup registry for items. When a file is uploaded here, it 
# triggers an asynchronous processing pipeline.
resource "aws_s3_bucket" "backup" {
  bucket = "item-backup"
}

# 3.2 SQS Processor Queue
# Acts as a durable buffer between the S3 storage bucket and the backend processing Lambda.
resource "aws_sqs_queue" "processor" {
  name = "processor-queue"
}

# 3.3 SES Email Identity
# Verifies the platform sender email address. SES will reject outward communications
# unless they originate from this exact verified address.
resource "aws_ses_email_identity" "sender" {
  email = "hello@highpasses.example"
}

# 3.4 S3-to-SQS Event Notification
# Triggers a message to SQS as soon as an item is successfully written to the S3 bucket.
resource "aws_s3_bucket_notification" "notify" {
  bucket = aws_s3_bucket.backup.id

  queue {
    queue_arn = aws_sqs_queue.processor.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_sqs_queue_policy.allow_s3
  ]
}

# 3.5 SQS Policy for S3
# Gives S3 explicit permission to publish notifications directly into the SQS queue.
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.processor.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.backup.arn
          }
        }
      }
    ]
  })
}


# ==============================================================================
# SECTION 4: IAM ROLES & SECURITY POLICIES
# ==============================================================================

# 4.1 Shared Lambda Execution Role
# Standard IAM Assume Role policy allowing AWS Lambda to execute the functions.
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# 4.2 Shared Lambda Security Policy
# A consolidated policy containing all required database, backup, queuing, and mailing operations.
# Note: For production systems, it is best practice to decouple this into individual micro-roles.
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB access to main enquiries data and GSI index, as well as rate limits
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
      # S3 access for uploading and pulling back-ups
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.backup.arn}/*"
      },
      # Allow writer to drop jobs onto the processing queue
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processor.arn
      },
      # Restrict SES mailing privileges strictly to verified domain identity
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
      # Allow writing stdout logs directly to CloudWatch Logs
      {
        Effect   = "Allow"
        Action   = "logs:*"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}


# ==============================================================================
# SECTION 5: COMPUTE LAYER (LAMBDA FUNCTIONS)
# ==============================================================================

# 5.1 Writer Lambda Function
# Handles POST ingestion, rate limits requests, writes to DynamoDB, and saves to S3.
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


# ==============================================================================
# SECTION 6: API GATEWAY CONFIGURATION
# ==============================================================================

# 6.1 Base REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "items-api"
  description = "Backend REST API handling items ingestion and admin queries"
}

# 6.2 Gateway Cognito Authorizer
# Secures administrative pathways by requiring a valid Cognito JWT.
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "highpasses-admin-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.api.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.admin.arn]
  identity_source = "method.request.header.Authorization"
}

# --- SUBSECTION 6.A: PUBLIC WRITE PATHWAYS (/items) ---

# Resource: /items
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "items"
}

# Method: POST /items
resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "POST"
  authorization = "NONE" # Public ingestion endpoint
}

# Integration: Link POST /items to the Writer Lambda
resource "aws_api_gateway_integration" "writer" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.items.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.writer.invoke_arn
}

# --- SUBSECTION 6.B: PROTECTED ADMIN PATHWAYS (/admin/enquiries) ---

# Resource: /admin
resource "aws_api_gateway_resource" "admin" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "admin"
}

# Resource: /admin/enquiries
resource "aws_api_gateway_resource" "enquiries" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.admin.id
  path_part   = "enquiries"
}

# Method: GET /admin/enquiries
resource "aws_api_gateway_method" "get_enquiries" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.enquiries.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Integration: Link GET /admin/enquiries to the Reader Lambda
resource "aws_api_gateway_integration" "reader" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.enquiries.id
  http_method             = aws_api_gateway_method.get_enquiries.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.reader.invoke_arn
}

# --- SUBSECTION 6.C: DEPLOYMENT, STAGING, & THROTTLING ---

# 6.3 Deployment Generation
# Compiles and validates endpoints, resources, integrations, and authorizers.
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_integration.writer,
    aws_api_gateway_integration.reader,
    aws_api_gateway_method.get_enquiries,
    aws_api_gateway_authorizer.cognito
  ]

  # Redeploys API Gateway stage when any integration dependency changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.get_enquiries.id,
      aws_api_gateway_integration.reader.id,
      aws_api_gateway_authorizer.cognito.id
    ]))
  }
}

# 6.4 API Gateway Stage Configuration
resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = "dev"
}

# 6.5 Global Throttling Policy
# Configures structural request controls for the public items API.
# Protects downstreams while fine-grained customer rate limiters function in Lambda.
resource "aws_api_gateway_method_settings" "enquiry_throttle" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.dev.stage_name
  method_path = "${aws_api_gateway_resource.items.path_part}/${aws_api_gateway_method.post.http_method}"

  settings {
    throttling_rate_limit  = 10 # 10 requests per second maximum (sustained)
    throttling_burst_limit = 20 # 20 requests burst buffer allowance
  }
}