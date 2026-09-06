output "frontend_public_ip" {
  description = "Public IP of the frontend (nginx) instance - browse to this over HTTP"
  value       = aws_instance.frontend.public_ip
}

output "backend_private_ip" {
  description = "Private IP of the backend (Flask/gunicorn) instance - no public IP"
  value       = aws_instance.backend.private_ip
}

output "worker_private_ip" {
  description = "Private IP of the worker (SQS consumer) instance - no public IP"
  value       = aws_instance.worker.private_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL connection endpoint (private - not publicly accessible)"
  value       = aws_db_instance.vmapp.address
}

output "sqs_queue_url" {
  description = "URL of the SQS queue used to hand off submitted requests to the worker"
  value       = aws_sqs_queue.requests.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic that emails notifications for app events"
  value       = aws_sns_topic.notifications.arn
}

output "s3_bucket" {
  description = "S3 bucket used for user-choice files (user-choices/) and the deploy bundle (deploy/)"
  value       = var.s3_bucket_name
}

output "db_password" {
  description = "Generated RDS master password (sensitive - see the state management note in README.md)"
  value       = random_password.db.result
  sensitive   = true
}

output "flask_secret_key" {
  description = "Shared Flask session secret, used by all gunicorn workers so sessions verify consistently (sensitive)"
  value       = random_password.flask_secret.result
  sensitive   = true
}
