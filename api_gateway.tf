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