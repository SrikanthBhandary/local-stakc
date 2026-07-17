resource "aws_sqs_queue" "processor" {
  name = "processor-queue"
}