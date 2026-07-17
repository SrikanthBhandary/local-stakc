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
