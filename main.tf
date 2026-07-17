# Serves as the backup registry for items. When a file is uploaded here, it 
# triggers an asynchronous processing pipeline.
resource "aws_s3_bucket" "backup" {
  bucket = "www.highpasses.com"
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

