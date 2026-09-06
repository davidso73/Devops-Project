resource "aws_sqs_queue" "requests" {
  name                       = "vmapp-requests-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400

  tags = {
    Project = "vmapp"
  }
}
