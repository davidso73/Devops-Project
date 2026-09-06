resource "aws_sns_topic" "notifications" {
  name = "vmapp-notifications"

  tags = {
    Project = "vmapp"
  }
}

# AWS emails a confirmation link to this address; the subscription stays in
# "PendingConfirmation" until it's clicked - Terraform cannot do that step.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
