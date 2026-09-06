# The cluster's only StorageClass (gp2) uses the legacy in-tree EBS
# provisioner, and the node role has no EC2 volume permissions - a PVC would
# hang Pending. The EBS CSI driver is the modern, IRSA-based way to fix this
# (same pattern as the LB controller), rather than granting broad EC2 volume
# permissions to every node.

data "aws_iam_policy_document" "irsa_assume_ebs_csi" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa_ebs_csi" {
  name               = "vmapp-eks-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_ebs_csi.json
}

resource "aws_iam_role_policy_attachment" "irsa_ebs_csi" {
  role       = aws_iam_role.irsa_ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.irsa_ebs_csi.arn

  depends_on = [aws_eks_node_group.this]
}
