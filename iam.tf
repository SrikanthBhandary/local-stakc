
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

