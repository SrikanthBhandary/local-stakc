# Serves as the backup registry for items. When a file is uploaded here, it 
# triggers an asynchronous processing pipeline.
resource "aws_s3_bucket" "backup" {
  bucket = "www.highpasses.com"
}


/* remove the notification to sqs as we are handling the same in the 
writer lambda 
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
} */


# Origin Access Control lets CloudFront authenticate to S3 without a public bucket
resource "aws_cloudfront_origin_access_control" "backup_oac" {
  name                              = "backup-oac"
  description                       = "OAC for www.highpasses.com backup bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "backup_cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.backup.bucket_regional_domain_name
    origin_id                = "s3-backup-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.backup_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-backup-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy allowing only this CloudFront distribution to read from the bucket
resource "aws_s3_bucket_policy" "backup_cf_access" {
  bucket = aws_s3_bucket.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backup.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.backup_cdn.arn
          }
        }
      }
    ]
  })
}
