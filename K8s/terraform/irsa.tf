# IRSA: each IAM role trusts one specific Kubernetes ServiceAccount identity
# (namespace:name) via the cluster's OIDC provider - no static AWS keys ever
# touch a pod. vmapp-frontend deliberately has NO role here at all: it needs
# zero AWS permissions, which is itself the clearest demonstration that not
# every service gets the same privileges.

locals {
  oidc_provider_url  = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
  oidc_provider_arn  = aws_iam_openid_connect_provider.eks.arn
  namespace          = "devops-app"
}

data "aws_iam_policy_document" "irsa_assume_backend" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.namespace}:vmapp-backend"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa_backend" {
  name               = "vmapp-eks-backend-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_backend.json
}

resource "aws_iam_role_policy" "irsa_backend" {
  name = "vmapp-eks-backend-policy"
  role = aws_iam_role.irsa_backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = var.sqs_queue_arn },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = var.sns_topic_arn },
    ]
  })
}

data "aws_iam_policy_document" "irsa_assume_worker" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.namespace}:vmapp-worker"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa_worker" {
  name               = "vmapp-eks-worker-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_worker.json
}

resource "aws_iam_role_policy" "irsa_worker" {
  name = "vmapp-eks-worker-policy"
  role = aws_iam_role.irsa_worker.id

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
        Resource = var.sqs_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/user-choices/*"
      },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = var.sns_topic_arn },
    ]
  })
}

# --- AWS Load Balancer Controller: also IRSA, using AWS's own published policy ---

data "aws_iam_policy_document" "irsa_assume_lbc" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa_lbc" {
  name               = "vmapp-eks-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_lbc.json
}

resource "aws_iam_role_policy" "irsa_lbc" {
  name   = "vmapp-eks-lbc-policy"
  role   = aws_iam_role.irsa_lbc.id
  policy = file("${path.module}/aws-load-balancer-controller-policy.json")
}
