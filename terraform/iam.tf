data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# --- backend: can enqueue a request and publish notifications ---

resource "aws_iam_role" "backend" {
  name               = "vmapp-backend-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Project = "vmapp"
  }
}

resource "aws_iam_role_policy" "backend" {
  name = "vmapp-backend-policy"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.requests.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backend" {
  name = "vmapp-backend-profile"
  role = aws_iam_role.backend.name
}

# --- worker: can consume the queue, write to S3 (scoped to a prefix), and publish notifications ---

resource "aws_iam_role" "worker" {
  name               = "vmapp-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Project = "vmapp"
  }
}

resource "aws_iam_role_policy" "worker" {
  name = "vmapp-worker-policy"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.requests.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/user-choices/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "worker" {
  name = "vmapp-worker-profile"
  role = aws_iam_role.worker.name
}
