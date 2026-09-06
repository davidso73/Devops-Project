# CI agent's AWS access: ECR push only, on exactly the 3 app repos. Separate
# from the app's own backend/worker IRSA roles - Jenkins is a different
# workload with different, narrower AWS needs (it never touches SQS/SNS/S3).
# The CD agent gets NO IRSA role at all - it only needs Kubernetes RBAC
# (see Jenkins/rbac/cd-agent-rbac.yaml), not AWS API access.

data "aws_iam_policy_document" "irsa_assume_jenkins_ci" {
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
      values   = ["system:serviceaccount:jenkins:jenkins-ci-agent"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa_jenkins_ci" {
  name               = "vmapp-jenkins-ci-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_jenkins_ci.json
}

resource "aws_iam_role_policy" "irsa_jenkins_ci" {
  name = "vmapp-jenkins-ci-policy"
  role = aws_iam_role.irsa_jenkins_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Needed by every registry client to obtain a short-lived auth token;
        # inherently account-wide in the ECR API (no ARN to scope it to).
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Push (and read-back-to-verify) access, scoped to exactly the 3 app
        # repos - not ecr:*, not other repos, and no delete/lifecycle actions.
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings",
        ]
        Resource = [
          aws_ecr_repository.frontend.arn,
          aws_ecr_repository.backend.arn,
          aws_ecr_repository.worker.arn,
        ]
      }
    ]
  })
}
