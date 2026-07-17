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